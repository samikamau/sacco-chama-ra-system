-- =========================================================================
-- MIGRATION 004: Contribution types (Share Capital / Share Deposits /
-- Welfare) and split payments across multiple funds in one transaction.
-- Run this after 001, 002, 003. Safe to re-run.
-- =========================================================================

-- -------------------------------------------------------------------------
-- 1. CONTRIBUTION TYPES ("funds")
-- -------------------------------------------------------------------------
create table if not exists contribution_types (
  id                uuid primary key default gen_random_uuid(),
  organisation_id   uuid not null references organisations(id) on delete cascade,
  name              text not null,
  category          text not null check (category in
                       ('share_capital','share_deposit','welfare','development','emergency','other')),
  chart_account_id  uuid not null references chart_of_accounts(id),
  is_recurring      boolean not null default true,
  active            boolean not null default true,
  created_at        timestamptz not null default now(),
  unique (organisation_id, name)
);

alter table contribution_types enable row level security;
drop policy if exists p_contribution_types_select on contribution_types;
create policy p_contribution_types_select on contribution_types for select
  using (is_org_member(organisation_id));
drop policy if exists p_contribution_types_write on contribution_types;
create policy p_contribution_types_write on contribution_types for insert
  with check (has_org_role(organisation_id, array['org_admin']::org_role[]));

-- -------------------------------------------------------------------------
-- 2. LINK CONTRIBUTION RULES TO A FUND TYPE
-- Existing rules (created before this migration) keep contribution_type_id
-- as null, meaning "generic/legacy" — still posts to the original
-- Contribution Income account via the old fn_record_and_post_payment.
-- New rules should always specify a type.
-- -------------------------------------------------------------------------
alter table contribution_rules
  add column if not exists contribution_type_id uuid references contribution_types(id);

-- -------------------------------------------------------------------------
-- 3. PAYMENT ALLOCATIONS (a payment split across one or more fund types)
-- -------------------------------------------------------------------------
create table if not exists payment_allocations (
  id                    uuid primary key default gen_random_uuid(),
  payment_id            uuid not null references payments(id) on delete cascade,
  contribution_type_id  uuid not null references contribution_types(id),
  amount                numeric(14,2) not null check (amount > 0)
);

create index if not exists idx_payment_allocations_payment on payment_allocations(payment_id);

alter table payment_allocations enable row level security;
drop policy if exists p_payment_allocations_select on payment_allocations;
create policy p_payment_allocations_select on payment_allocations for select
  using (exists (
    select 1 from payments p where p.id = payment_allocations.payment_id and is_org_member(p.organisation_id)
  ));
-- No insert policy for client roles — only fn_record_and_post_split_payment
-- (security definer) writes these, same pattern as journal_entries.

drop trigger if exists trg_audit_payment_allocations on payment_allocations;
create trigger trg_audit_payment_allocations after insert or update or delete on payment_allocations
  for each row execute function fn_audit_trigger();

-- -------------------------------------------------------------------------
-- 4. SPLIT PAYMENT POSTING FUNCTION
-- p_allocations is a JSON array like:
--   [{"contribution_type_id": "...", "amount": 1000}, {"contribution_type_id": "...", "amount": 1500}]
-- One payment, one Dr line to the cash/bank/M-Pesa account for the total,
-- and one Cr line per fund type for its share — still balances by
-- construction, still enforced by the existing balance trigger.
-- -------------------------------------------------------------------------
create or replace function fn_record_and_post_split_payment(
  p_organisation_id uuid,
  p_member_id       uuid,
  p_channel         payment_channel,
  p_reference       text,
  p_description     text,
  p_cash_account_id uuid,
  p_allocations     jsonb
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_payment_id uuid;
  v_entry_id   uuid;
  v_total      numeric(14,2) := 0;
  v_alloc      jsonb;
  v_type_id    uuid;
  v_alloc_amt  numeric(14,2);
  v_account_id uuid;
  v_remaining  numeric(14,2);
  v_contrib    record;
  v_apply      numeric(14,2);
begin
  if not is_org_member(p_organisation_id) then
    raise exception 'Not authorised for this organisation';
  end if;

  select coalesce(sum((elem->>'amount')::numeric), 0) into v_total
    from jsonb_array_elements(p_allocations) elem;

  if v_total <= 0 then
    raise exception 'Payment total must be greater than zero';
  end if;

  insert into payments(organisation_id, member_id, amount, channel, reference, description, created_by)
  values (p_organisation_id, p_member_id, v_total, p_channel, p_reference, p_description, auth.uid())
  returning id into v_payment_id;

  insert into journal_entries(organisation_id, description, source_type, source_id, created_by)
  values (p_organisation_id, 'Payment received - ' || coalesce(p_reference,''), 'payment', v_payment_id, auth.uid())
  returning id into v_entry_id;

  -- One debit line for the total cash received
  insert into journal_lines(journal_entry_id, account_id, debit, credit, member_id)
  values (v_entry_id, p_cash_account_id, v_total, 0, p_member_id);

  for v_alloc in select * from jsonb_array_elements(p_allocations)
  loop
    v_type_id   := (v_alloc->>'contribution_type_id')::uuid;
    v_alloc_amt := (v_alloc->>'amount')::numeric;

    insert into payment_allocations(payment_id, contribution_type_id, amount)
    values (v_payment_id, v_type_id, v_alloc_amt);

    select chart_account_id into v_account_id from contribution_types where id = v_type_id;

    -- One credit line per fund type
    insert into journal_lines(journal_entry_id, account_id, debit, credit, member_id)
    values (v_entry_id, v_account_id, 0, v_alloc_amt, p_member_id);

    -- Allocate this fund's share against that fund's own unpaid/partial
    -- contributions, oldest period first — funds never cross-allocate.
    v_remaining := v_alloc_amt;
    for v_contrib in
      select c.id, c.amount_expected, c.amount_paid
      from contributions c
      join contribution_periods cp on cp.id = c.period_id
      join contribution_rules cr on cr.id = cp.rule_id
      where c.member_id = p_member_id
        and cr.contribution_type_id = v_type_id
        and c.status in ('unpaid','partial')
      order by cp.period_start asc
    loop
      exit when v_remaining <= 0;
      v_apply := least(v_remaining, v_contrib.amount_expected - v_contrib.amount_paid);
      update contributions
        set amount_paid = amount_paid + v_apply,
            status = (case
                        when amount_paid + v_apply >= amount_expected then 'paid'
                        else 'partial'
                     end)::contribution_status
        where id = v_contrib.id;
      v_remaining := v_remaining - v_apply;
    end loop;
  end loop;

  update payments set status = 'posted', journal_entry_id = v_entry_id where id = v_payment_id;

  return v_payment_id;
end;
$$;

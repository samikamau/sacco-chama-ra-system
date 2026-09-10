-- =========================================================================
-- MIGRATION 021: Full bank & M-Pesa reconciliation workflow.
-- EXTENDS the existing reconciliations table rather than replacing it.
-- Adds: statement period, opening/closing balances, status lifecycle,
-- prepared/completed by, and a reconciliation_items child table for
-- reconciling items (deposits in transit, outstanding payments, charges).
-- Run after 001-020. Safe to re-run.
-- =========================================================================

-- -------------------------------------------------------------------------
-- A. EXTEND the existing reconciliations table
-- -------------------------------------------------------------------------
alter table reconciliations
  add column if not exists statement_period_start date,
  add column if not exists statement_period_end   date,
  add column if not exists statement_opening_balance numeric(14,2) default 0,
  add column if not exists status text not null default 'draft'
      check (status in ('draft','in_progress','completed','locked')),
  add column if not exists prepared_by  uuid references auth.users(id),
  add column if not exists completed_by uuid references auth.users(id),
  add column if not exists completed_at timestamptz,
  add column if not exists notes_internal text;

-- Ensure a reconciliation belongs to EXACTLY ONE financial account
-- (bank OR M-Pesa, never both, never neither).
do $$ begin
  alter table reconciliations
    add constraint chk_one_account check (
      (bank_account_id is not null and mpesa_account_id is null) or
      (bank_account_id is null and mpesa_account_id is not null)
    );
exception when duplicate_object then null; end $$;

create index if not exists idx_recon_org_status on reconciliations(organisation_id, status);

-- -------------------------------------------------------------------------
-- B. RECONCILING ITEMS (deposits in transit, outstanding payments, charges)
-- -------------------------------------------------------------------------
create table if not exists reconciliation_items (
  id                uuid primary key default gen_random_uuid(),
  reconciliation_id uuid not null references reconciliations(id) on delete cascade,
  organisation_id   uuid not null references organisations(id) on delete cascade,
  item_type         text not null check (item_type in
                       ('deposit_in_transit','outstanding_payment','bank_charge',
                        'bank_interest','bank_error','book_error','other')),
  description       text not null,
  amount            numeric(14,2) not null,
  -- 'add' increases the adjusted balance, 'less' decreases it
  direction         text not null check (direction in ('add','less')),
  -- which side this adjusts: the bank/statement side or the book/ledger side
  adjusts           text not null default 'bank' check (adjusts in ('bank','book')),
  journal_entry_id  uuid references journal_entries(id),  -- if an adjustment was posted
  created_by        uuid references auth.users(id),
  created_at        timestamptz not null default now()
);

create index if not exists idx_recon_items on reconciliation_items(reconciliation_id);

alter table reconciliation_items enable row level security;
drop policy if exists p_recon_items_select on reconciliation_items;
create policy p_recon_items_select on reconciliation_items for select
  using (is_org_member(organisation_id));
drop policy if exists p_recon_items_write on reconciliation_items;
create policy p_recon_items_write on reconciliation_items for insert
  with check (has_org_role(organisation_id, array['org_admin','accountant','treasurer']::org_role[]));
drop policy if exists p_recon_items_delete on reconciliation_items;
create policy p_recon_items_delete on reconciliation_items for delete
  using (has_org_role(organisation_id, array['org_admin','accountant']::org_role[]));

drop trigger if exists trg_audit_recon_items on reconciliation_items;
create trigger trg_audit_recon_items after insert or update or delete on reconciliation_items
  for each row execute function fn_audit_trigger();

drop trigger if exists trg_audit_reconciliations on reconciliations;
create trigger trg_audit_reconciliations after insert or update or delete on reconciliations
  for each row execute function fn_audit_trigger();

-- -------------------------------------------------------------------------
-- C. BOOK BALANCE: ledger balance of a cash account as at a date
-- -------------------------------------------------------------------------
create or replace function fn_book_balance(
  p_account_id uuid,   -- chart_of_accounts id
  p_as_at date default null
) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce(sum(jl.debit - jl.credit), 0)
  from journal_lines jl
  join journal_entries je on je.id = jl.journal_entry_id
  join chart_of_accounts coa on coa.id = jl.account_id
  where jl.account_id = p_account_id
    and je.status = 'posted'
    and is_org_member(coa.organisation_id)
    and (p_as_at is null or je.entry_date <= p_as_at);
$$;

-- -------------------------------------------------------------------------
-- D. CREATE a reconciliation
-- -------------------------------------------------------------------------
create or replace function fn_create_reconciliation(
  p_organisation_id uuid,
  p_bank_account_id uuid,      -- pass one of these, null the other
  p_mpesa_account_id uuid,
  p_period_start    date,
  p_period_end      date,
  p_opening_balance numeric,
  p_closing_balance numeric
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
  v_coa_account uuid;
  v_book numeric(14,2);
begin
  if not has_org_role(p_organisation_id, array['org_admin','accountant','treasurer']::org_role[]) then
    raise exception 'Not authorised to create reconciliations';
  end if;
  if (p_bank_account_id is null) = (p_mpesa_account_id is null) then
    raise exception 'A reconciliation must be for exactly one account — bank OR M-Pesa';
  end if;

  -- Resolve the linked chart-of-accounts row so we can compute the book balance
  if p_bank_account_id is not null then
    select chart_account_id into v_coa_account from bank_accounts where id = p_bank_account_id;
  else
    select chart_account_id into v_coa_account from mpesa_accounts where id = p_mpesa_account_id;
  end if;

  v_book := coalesce(fn_book_balance(v_coa_account, p_period_end), 0);

  insert into reconciliations(organisation_id, bank_account_id, mpesa_account_id,
    reconciliation_date, statement_period_start, statement_period_end,
    statement_opening_balance, statement_balance, ledger_balance,
    status, prepared_by, created_by)
  values (p_organisation_id, p_bank_account_id, p_mpesa_account_id,
    p_period_end, p_period_start, p_period_end,
    coalesce(p_opening_balance,0), coalesce(p_closing_balance,0), v_book,
    'draft', auth.uid(), auth.uid())
  returning id into v_id;

  return v_id;
end;
$$;

-- -------------------------------------------------------------------------
-- E. RECONCILIATION SUMMARY: statement balance, reconciling items,
-- adjusted balances, and the final difference.
-- -------------------------------------------------------------------------
create or replace function fn_reconciliation_summary(p_reconciliation_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_rec record;
  v_bank_add  numeric(14,2);
  v_bank_less numeric(14,2);
  v_book_add  numeric(14,2);
  v_book_less numeric(14,2);
  v_adj_bank  numeric(14,2);
  v_adj_book  numeric(14,2);
begin
  select * into v_rec from reconciliations where id = p_reconciliation_id;
  if v_rec is null then raise exception 'Reconciliation not found'; end if;
  if not is_org_member(v_rec.organisation_id) then raise exception 'Not authorised'; end if;

  select
    coalesce(sum(amount) filter (where adjusts='bank' and direction='add'),0),
    coalesce(sum(amount) filter (where adjusts='bank' and direction='less'),0),
    coalesce(sum(amount) filter (where adjusts='book' and direction='add'),0),
    coalesce(sum(amount) filter (where adjusts='book' and direction='less'),0)
  into v_bank_add, v_bank_less, v_book_add, v_book_less
  from reconciliation_items where reconciliation_id = p_reconciliation_id;

  v_adj_bank := v_rec.statement_balance + v_bank_add - v_bank_less;
  v_adj_book := v_rec.ledger_balance    + v_book_add - v_book_less;

  return jsonb_build_object(
    'statement_balance', v_rec.statement_balance,
    'bank_add', v_bank_add,
    'bank_less', v_bank_less,
    'adjusted_bank_balance', v_adj_bank,
    'book_balance', v_rec.ledger_balance,
    'book_add', v_book_add,
    'book_less', v_book_less,
    'adjusted_book_balance', v_adj_book,
    'difference', v_adj_bank - v_adj_book,
    'is_reconciled', abs(v_adj_bank - v_adj_book) < 0.005,
    'status', v_rec.status
  );
end;
$$;

-- -------------------------------------------------------------------------
-- F. COMPLETE a reconciliation (only when difference is zero)
-- -------------------------------------------------------------------------
create or replace function fn_complete_reconciliation(p_reconciliation_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_rec     record;
  v_summary jsonb;
begin
  select * into v_rec from reconciliations where id = p_reconciliation_id;
  if v_rec is null then raise exception 'Reconciliation not found'; end if;
  if not has_org_role(v_rec.organisation_id, array['org_admin','accountant']::org_role[]) then
    raise exception 'Not authorised to complete reconciliations';
  end if;
  if v_rec.status in ('completed','locked') then
    raise exception 'This reconciliation is already % ', v_rec.status;
  end if;

  v_summary := fn_reconciliation_summary(p_reconciliation_id);
  if not (v_summary->>'is_reconciled')::boolean then
    raise exception 'Cannot complete — there is an unreconciled difference of KES %',
      round((v_summary->>'difference')::numeric, 2);
  end if;

  update reconciliations
     set status = 'completed', completed_by = auth.uid(), completed_at = now()
   where id = p_reconciliation_id;
end;
$$;

-- -------------------------------------------------------------------------
-- G. LOCK / UNLOCK
-- -------------------------------------------------------------------------
create or replace function fn_lock_reconciliation(p_reconciliation_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_org uuid; v_status text;
begin
  select organisation_id, status into v_org, v_status from reconciliations where id = p_reconciliation_id;
  if v_org is null then raise exception 'Reconciliation not found'; end if;
  if not has_org_role(v_org, array['org_admin','accountant']::org_role[]) then
    raise exception 'Not authorised to lock reconciliations';
  end if;
  if v_status <> 'completed' then
    raise exception 'Only a completed reconciliation can be locked';
  end if;
  update reconciliations set status = 'locked' where id = p_reconciliation_id;
end;
$$;

create or replace function fn_unlock_reconciliation(p_reconciliation_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_org uuid;
begin
  select organisation_id into v_org from reconciliations where id = p_reconciliation_id;
  if v_org is null then raise exception 'Reconciliation not found'; end if;
  -- Deliberately stricter: only org_admin may unlock a locked reconciliation.
  if not has_org_role(v_org, array['org_admin']::org_role[]) then
    raise exception 'Only an administrator can unlock a locked reconciliation';
  end if;
  if p_reason is null or trim(p_reason) = '' then
    raise exception 'A reason is required to unlock a reconciliation';
  end if;
  update reconciliations
     set status = 'in_progress',
         notes_internal = coalesce(notes_internal,'') || E'\nUNLOCKED: ' || p_reason || ' (' || now()::date || ')'
   where id = p_reconciliation_id;
end;
$$;

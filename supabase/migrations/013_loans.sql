-- =========================================================================
-- MIGRATION 013 (LOANS - PHASE 2): loan products, applications, eligibility,
-- guarantors, approval, disbursement, repayment schedules and repayments.
-- Interest: flat or reducing, configurable per product.
-- Guarantors: always required (enforced at approval).
-- Run after 001-012 on the SACCO project. Safe to re-run.
-- =========================================================================

do $$ begin
  create type loan_status as enum
    ('draft','pending_approval','approved','disbursed','active','closed','rejected','written_off');
exception when duplicate_object then null; end $$;

-- -------------------------------------------------------------------------
-- LOAN PRODUCTS (configurable rules)
-- -------------------------------------------------------------------------
create table if not exists loan_products (
  id                     uuid primary key default gen_random_uuid(),
  organisation_id        uuid not null references organisations(id) on delete cascade,
  name                   text not null,
  savings_multiplier     numeric(6,2) not null default 3,   -- max loan = multiplier x deposits
  max_amount             numeric(14,2),                     -- optional hard ceiling
  interest_method        text not null default 'reducing' check (interest_method in ('flat','reducing')),
  annual_interest_rate   numeric(7,4) not null default 12,  -- percent per year
  max_term_months        int not null default 12,
  min_savings            numeric(14,2) not null default 0,
  min_membership_months  int not null default 0,
  -- Which fund category counts as "savings/deposits" for eligibility.
  savings_category       text not null default 'share_deposit'
                            check (savings_category in ('share_capital','share_deposit')),
  -- Accounts this product posts to.
  loan_receivable_account_id uuid references chart_of_accounts(id),
  interest_income_account_id uuid references chart_of_accounts(id),
  active                 boolean not null default true,
  created_at             timestamptz not null default now(),
  unique (organisation_id, name)
);

alter table loan_products enable row level security;
drop policy if exists p_loan_products_select on loan_products;
create policy p_loan_products_select on loan_products for select using (is_org_member(organisation_id));
drop policy if exists p_loan_products_write on loan_products;
create policy p_loan_products_write on loan_products for insert
  with check (has_org_role(organisation_id, array['org_admin']::org_role[]));
drop policy if exists p_loan_products_update on loan_products;
create policy p_loan_products_update on loan_products for update
  using (has_org_role(organisation_id, array['org_admin']::org_role[]));

-- -------------------------------------------------------------------------
-- LOANS (application through closure - one table, status-driven)
-- -------------------------------------------------------------------------
create table if not exists loans (
  id                 uuid primary key default gen_random_uuid(),
  organisation_id    uuid not null references organisations(id) on delete cascade,
  member_id          uuid not null references members(id),
  product_id         uuid not null references loan_products(id),
  principal          numeric(14,2) not null check (principal > 0),
  term_months        int not null check (term_months > 0),
  interest_method    text not null,
  annual_interest_rate numeric(7,4) not null,
  status             loan_status not null default 'draft',
  application_date   date not null default current_date,
  approved_by        uuid references auth.users(id),
  approved_at        timestamptz,
  disbursed_at       timestamptz,
  disbursement_entry_id uuid references journal_entries(id),
  notes              text,
  created_by         uuid references auth.users(id),
  created_at         timestamptz not null default now()
);

create index if not exists idx_loans_org on loans(organisation_id, status);
create index if not exists idx_loans_member on loans(member_id);

alter table loans enable row level security;
drop policy if exists p_loans_select on loans;
create policy p_loans_select on loans for select using (is_org_member(organisation_id));
-- Applications can be created by loan-processing roles; approval/disbursement
-- go through security-definer functions.
drop policy if exists p_loans_insert on loans;
create policy p_loans_insert on loans for insert
  with check (has_org_role(organisation_id, array['org_admin','treasurer','accountant']::org_role[]));
drop policy if exists p_loans_update on loans;
create policy p_loans_update on loans for update
  using (has_org_role(organisation_id, array['org_admin','treasurer','accountant']::org_role[]));

drop trigger if exists trg_audit_loans on loans;
create trigger trg_audit_loans after insert or update or delete on loans
  for each row execute function fn_audit_trigger();

-- -------------------------------------------------------------------------
-- GUARANTORS
-- -------------------------------------------------------------------------
create table if not exists loan_guarantors (
  id                uuid primary key default gen_random_uuid(),
  loan_id           uuid not null references loans(id) on delete cascade,
  organisation_id   uuid not null references organisations(id) on delete cascade,
  guarantor_member_id uuid not null references members(id),
  amount_guaranteed numeric(14,2) not null check (amount_guaranteed > 0),
  created_at        timestamptz not null default now()
);

create index if not exists idx_guarantors_loan on loan_guarantors(loan_id);
create index if not exists idx_guarantors_member on loan_guarantors(guarantor_member_id);

alter table loan_guarantors enable row level security;
drop policy if exists p_guarantors_select on loan_guarantors;
create policy p_guarantors_select on loan_guarantors for select using (is_org_member(organisation_id));
drop policy if exists p_guarantors_write on loan_guarantors;
create policy p_guarantors_write on loan_guarantors for insert
  with check (has_org_role(organisation_id, array['org_admin','treasurer','accountant']::org_role[]));
drop policy if exists p_guarantors_delete on loan_guarantors;
create policy p_guarantors_delete on loan_guarantors for delete
  using (has_org_role(organisation_id, array['org_admin','treasurer','accountant']::org_role[]));

-- -------------------------------------------------------------------------
-- REPAYMENT SCHEDULE
-- -------------------------------------------------------------------------
create table if not exists loan_schedule (
  id                uuid primary key default gen_random_uuid(),
  loan_id           uuid not null references loans(id) on delete cascade,
  organisation_id   uuid not null references organisations(id) on delete cascade,
  installment_no    int not null,
  due_date          date not null,
  principal_due     numeric(14,2) not null default 0,
  interest_due      numeric(14,2) not null default 0,
  total_due         numeric(14,2) not null default 0,
  principal_paid    numeric(14,2) not null default 0,
  interest_paid     numeric(14,2) not null default 0,
  status            text not null default 'pending' check (status in ('pending','partial','paid')),
  unique (loan_id, installment_no)
);

create index if not exists idx_schedule_loan on loan_schedule(loan_id);

alter table loan_schedule enable row level security;
drop policy if exists p_schedule_select on loan_schedule;
create policy p_schedule_select on loan_schedule for select using (is_org_member(organisation_id));

-- -------------------------------------------------------------------------
-- LOAN REPAYMENTS
-- -------------------------------------------------------------------------
create table if not exists loan_repayments (
  id                uuid primary key default gen_random_uuid(),
  loan_id           uuid not null references loans(id) on delete cascade,
  organisation_id   uuid not null references organisations(id) on delete cascade,
  payment_date      date not null default current_date,
  amount            numeric(14,2) not null check (amount > 0),
  principal_portion numeric(14,2) not null default 0,
  interest_portion  numeric(14,2) not null default 0,
  channel           payment_channel not null,
  reference         text,
  journal_entry_id  uuid references journal_entries(id),
  created_by        uuid references auth.users(id),
  created_at        timestamptz not null default now()
);

create index if not exists idx_loan_repay_loan on loan_repayments(loan_id);

alter table loan_repayments enable row level security;
drop policy if exists p_loan_repay_select on loan_repayments;
create policy p_loan_repay_select on loan_repayments for select using (is_org_member(organisation_id));

drop trigger if exists trg_audit_loan_repay on loan_repayments;
create trigger trg_audit_loan_repay after insert or update or delete on loan_repayments
  for each row execute function fn_audit_trigger();

-- -------------------------------------------------------------------------
-- ELIGIBILITY: returns a member's savings, max eligible, and existing loans.
-- -------------------------------------------------------------------------
create or replace function fn_loan_eligibility(
  p_member_id  uuid,
  p_product_id uuid
) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_org uuid;
  v_prod record;
  v_savings numeric(14,2);
  v_existing numeric(14,2);
  v_max numeric(14,2);
begin
  select * into v_prod from loan_products where id = p_product_id;
  if v_prod is null then raise exception 'Loan product not found'; end if;
  v_org := v_prod.organisation_id;
  if not is_org_member(v_org) then raise exception 'Not authorised'; end if;

  -- Savings = posted allocations to the product's savings category for this member.
  select coalesce(sum(pa.amount),0) into v_savings
  from payment_allocations pa
  join payments p on p.id = pa.payment_id
  join contribution_types ct on ct.id = pa.contribution_type_id
  where p.member_id = p_member_id and p.status = 'posted'
    and ct.category = v_prod.savings_category;

  -- Existing outstanding principal (disbursed/active loans not yet closed).
  select coalesce(sum(l.principal - coalesce((
            select sum(lr.principal_portion) from loan_repayments lr where lr.loan_id = l.id
         ),0)),0) into v_existing
  from loans l
  where l.member_id = p_member_id and l.status in ('disbursed','active');

  v_max := v_savings * v_prod.savings_multiplier;
  if v_prod.max_amount is not null then v_max := least(v_max, v_prod.max_amount); end if;

  return jsonb_build_object(
    'savings', v_savings,
    'savings_multiplier', v_prod.savings_multiplier,
    'max_eligible', greatest(v_max - v_existing, 0),
    'existing_outstanding', v_existing,
    'min_savings', v_prod.min_savings,
    'meets_min_savings', v_savings >= v_prod.min_savings
  );
end;
$$;

-- -------------------------------------------------------------------------
-- APPROVE + DISBURSE: validates eligibility and guarantor coverage, then
-- posts the disbursement journal entry and builds the repayment schedule.
-- Guarantors are ALWAYS required: total guaranteed must cover the principal.
-- -------------------------------------------------------------------------
create or replace function fn_approve_and_disburse_loan(
  p_loan_id uuid,
  p_cash_account_id uuid
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_loan record;
  v_prod record;
  v_elig jsonb;
  v_guaranteed numeric(14,2);
  v_entry_id uuid;
  v_monthly_rate numeric(12,8);
  v_i int;
  v_principal_part numeric(14,2);
  v_interest_part numeric(14,2);
  v_balance numeric(14,2);
  v_flat_interest numeric(14,2);
  v_annuity numeric(14,2);
begin
  select * into v_loan from loans where id = p_loan_id;
  if v_loan is null then raise exception 'Loan not found'; end if;
  if not has_org_role(v_loan.organisation_id, array['org_admin','accountant']::org_role[]) then
    raise exception 'Not authorised to approve/disburse loans';
  end if;
  if v_loan.status not in ('draft','pending_approval') then
    raise exception 'Loan is not in an approvable state (current: %)', v_loan.status;
  end if;

  select * into v_prod from loan_products where id = v_loan.product_id;

  -- Eligibility check
  v_elig := fn_loan_eligibility(v_loan.member_id, v_loan.product_id);
  if v_loan.principal > (v_elig->>'max_eligible')::numeric then
    raise exception 'Principal % exceeds maximum eligible %', v_loan.principal, (v_elig->>'max_eligible');
  end if;
  if not (v_elig->>'meets_min_savings')::boolean then
    raise exception 'Member does not meet the minimum savings requirement';
  end if;

  -- Guarantor coverage (always required)
  select coalesce(sum(amount_guaranteed),0) into v_guaranteed
    from loan_guarantors where loan_id = p_loan_id;
  if v_guaranteed < v_loan.principal then
    raise exception 'Guarantors cover only % of principal % — full coverage required', v_guaranteed, v_loan.principal;
  end if;

  -- Post disbursement: Dr Loan Receivable, Cr Cash/Bank
  insert into journal_entries(organisation_id, description, source_type, source_id, created_by)
  values (v_loan.organisation_id, 'Loan disbursement', 'loan_disbursement', p_loan_id, auth.uid())
  returning id into v_entry_id;

  insert into journal_lines(journal_entry_id, account_id, debit, credit, member_id)
  values (v_entry_id, v_prod.loan_receivable_account_id, v_loan.principal, 0, v_loan.member_id);
  insert into journal_lines(journal_entry_id, account_id, debit, credit, member_id)
  values (v_entry_id, p_cash_account_id, 0, v_loan.principal, v_loan.member_id);

  -- Build repayment schedule
  v_monthly_rate := (v_loan.annual_interest_rate / 100.0) / 12.0;
  v_balance := v_loan.principal;

  if v_loan.interest_method = 'flat' then
    -- Flat: interest = principal * annual_rate/100 * term/12, spread evenly.
    v_flat_interest := round(v_loan.principal * (v_loan.annual_interest_rate/100.0) * (v_loan.term_months/12.0), 2);
    for v_i in 1..v_loan.term_months loop
      v_principal_part := round(v_loan.principal / v_loan.term_months, 2);
      v_interest_part := round(v_flat_interest / v_loan.term_months, 2);
      insert into loan_schedule(loan_id, organisation_id, installment_no, due_date,
        principal_due, interest_due, total_due)
      values (p_loan_id, v_loan.organisation_id, v_i,
        (v_loan.application_date + (v_i || ' months')::interval)::date,
        v_principal_part, v_interest_part, v_principal_part + v_interest_part);
    end loop;
  else
    -- Reducing balance annuity payment
    if v_monthly_rate = 0 then
      v_annuity := round(v_loan.principal / v_loan.term_months, 2);
    else
      v_annuity := round(v_loan.principal * v_monthly_rate /
                     (1 - power(1 + v_monthly_rate, -v_loan.term_months)), 2);
    end if;
    for v_i in 1..v_loan.term_months loop
      v_interest_part := round(v_balance * v_monthly_rate, 2);
      v_principal_part := v_annuity - v_interest_part;
      if v_i = v_loan.term_months then
        v_principal_part := v_balance;  -- clear any rounding on the last one
      end if;
      v_balance := v_balance - v_principal_part;
      insert into loan_schedule(loan_id, organisation_id, installment_no, due_date,
        principal_due, interest_due, total_due)
      values (p_loan_id, v_loan.organisation_id, v_i,
        (v_loan.application_date + (v_i || ' months')::interval)::date,
        v_principal_part, v_interest_part, v_principal_part + v_interest_part);
    end loop;
  end if;

  update loans set status = 'active', approved_by = auth.uid(), approved_at = now(),
    disbursed_at = now(), disbursement_entry_id = v_entry_id
  where id = p_loan_id;
end;
$$;

-- -------------------------------------------------------------------------
-- RECORD A REPAYMENT: splits into interest then principal across due
-- installments, posts Dr Cash / Cr Loan Receivable (principal) + Cr
-- Interest Income (interest).
-- -------------------------------------------------------------------------
create or replace function fn_record_loan_repayment(
  p_loan_id uuid,
  p_amount numeric,
  p_channel payment_channel,
  p_reference text,
  p_cash_account_id uuid
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_loan record;
  v_prod record;
  v_entry_id uuid;
  v_remaining numeric(14,2) := p_amount;
  v_sched record;
  v_int_pay numeric(14,2);
  v_prin_pay numeric(14,2);
  v_total_interest numeric(14,2) := 0;
  v_total_principal numeric(14,2) := 0;
  v_repay_id uuid;
begin
  select * into v_loan from loans where id = p_loan_id;
  if v_loan is null then raise exception 'Loan not found'; end if;
  if not has_org_role(v_loan.organisation_id, array['org_admin','treasurer','accountant']::org_role[]) then
    raise exception 'Not authorised to record repayments';
  end if;
  select * into v_prod from loan_products where id = v_loan.product_id;

  -- Apply to installments oldest-first: interest portion first, then principal.
  for v_sched in
    select * from loan_schedule where loan_id = p_loan_id and status <> 'paid'
    order by installment_no asc
  loop
    exit when v_remaining <= 0;
    v_int_pay := least(v_remaining, v_sched.interest_due - v_sched.interest_paid);
    v_remaining := v_remaining - v_int_pay;
    v_prin_pay := least(v_remaining, v_sched.principal_due - v_sched.principal_paid);
    v_remaining := v_remaining - v_prin_pay;

    update loan_schedule
      set interest_paid = interest_paid + v_int_pay,
          principal_paid = principal_paid + v_prin_pay,
          status = case when (interest_paid + v_int_pay) >= interest_due
                          and (principal_paid + v_prin_pay) >= principal_due then 'paid'
                        when (interest_paid + v_int_pay) > 0 or (principal_paid + v_prin_pay) > 0 then 'partial'
                        else 'pending' end
      where id = v_sched.id;

    v_total_interest := v_total_interest + v_int_pay;
    v_total_principal := v_total_principal + v_prin_pay;
  end loop;

  -- Post: Dr Cash; Cr Loan Receivable (principal); Cr Interest Income (interest)
  insert into journal_entries(organisation_id, description, source_type, source_id, created_by)
  values (v_loan.organisation_id, 'Loan repayment', 'loan_repayment', p_loan_id, auth.uid())
  returning id into v_entry_id;

  insert into journal_lines(journal_entry_id, account_id, debit, credit, member_id)
  values (v_entry_id, p_cash_account_id, v_total_principal + v_total_interest, 0, v_loan.member_id);
  if v_total_principal > 0 then
    insert into journal_lines(journal_entry_id, account_id, debit, credit, member_id)
    values (v_entry_id, v_prod.loan_receivable_account_id, 0, v_total_principal, v_loan.member_id);
  end if;
  if v_total_interest > 0 then
    insert into journal_lines(journal_entry_id, account_id, debit, credit, member_id)
    values (v_entry_id, v_prod.interest_income_account_id, 0, v_total_interest, v_loan.member_id);
  end if;

  insert into loan_repayments(loan_id, organisation_id, amount, principal_portion,
    interest_portion, channel, reference, journal_entry_id, created_by)
  values (p_loan_id, v_loan.organisation_id, v_total_principal + v_total_interest,
    v_total_principal, v_total_interest, p_channel, p_reference, v_entry_id, auth.uid())
  returning id into v_repay_id;

  -- Close the loan if fully repaid.
  if not exists (select 1 from loan_schedule where loan_id = p_loan_id and status <> 'paid') then
    update loans set status = 'closed' where id = p_loan_id;
  end if;

  return v_repay_id;
end;
$$;

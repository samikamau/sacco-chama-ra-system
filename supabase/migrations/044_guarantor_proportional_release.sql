-- =========================================================================
-- MIGRATION 044: Proportional guarantor release on loan repayment.
--
-- When a loan repayment is recorded, each guarantor's committed amount
-- reduces proportionally to the principal repaid.
--
-- Example: Loan 100,000. Guarantor A committed 60,000, B committed 40,000.
-- Repayment of 20,000 principal:
--   A released: 60,000/100,000 * 20,000 = 12,000 (committed → 48,000)
--   B released: 40,000/100,000 * 20,000 =  8,000 (committed → 32,000)
--
-- Implementation: add amount_released column to loan_guarantors, updated
-- by a trigger on loan_repayments. fn_guarantor_capacity already uses
-- (amount_guaranteed - amount_released) as the effective commitment.
-- =========================================================================

-- Add release tracking column
alter table loan_guarantors
  add column if not exists amount_released numeric(14,2) not null default 0;

-- Update fn_guarantor_capacity to use net commitment (guaranteed - released)
create or replace function fn_guarantor_capacity(
  p_member_id       uuid,
  p_exclude_loan_id uuid default null
) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_org       uuid;
  v_deposits  numeric(14,2);
  v_committed numeric(14,2);
  v_available numeric(14,2);
begin
  select organisation_id into v_org from members where id = p_member_id;
  if not is_org_member(v_org) then raise exception 'Not authorised'; end if;

  -- Total share deposits
  select coalesce(sum(pa.amount), 0) into v_deposits
  from payment_allocations pa
  join payments p on p.id = pa.payment_id
  join contribution_types ct on ct.id = pa.contribution_type_id
  where p.member_id = p_member_id
    and p.status = 'posted'
    and ct.category = 'share_deposit';

  -- Net commitment = (amount_guaranteed - amount_released) on active loans
  select coalesce(sum(lg.amount_guaranteed - lg.amount_released), 0) into v_committed
  from loan_guarantors lg
  join loans l on l.id = lg.loan_id
  where lg.guarantor_member_id = p_member_id
    and l.status in ('active', 'disbursed', 'pending_approval', 'approved')
    and (p_exclude_loan_id is null or l.id <> p_exclude_loan_id);

  v_available := greatest(v_deposits - v_committed, 0);

  return jsonb_build_object(
    'total_deposits', v_deposits,
    'committed',      v_committed,
    'available',      v_available
  );
end;
$$;

-- Function to release guarantor shares proportionally after a repayment
create or replace function fn_release_guarantors_proportionally(
  p_loan_id          uuid,
  p_principal_repaid numeric
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_loan          record;
  v_total_guaranteed numeric(14,2);
  v_guar          record;
  v_release       numeric(14,2);
begin
  select * into v_loan from loans where id = p_loan_id;
  if v_loan is null then return; end if;

  -- Total originally guaranteed
  select coalesce(sum(amount_guaranteed), 0) into v_total_guaranteed
  from loan_guarantors where loan_id = p_loan_id;

  if v_total_guaranteed <= 0 then return; end if;

  -- Release each guarantor proportionally
  for v_guar in
    select id, amount_guaranteed, amount_released
    from loan_guarantors where loan_id = p_loan_id
  loop
    -- Their share of this repayment
    v_release := round(
      (v_guar.amount_guaranteed / v_total_guaranteed) * p_principal_repaid,
      2
    );

    -- Cap release at what they originally guaranteed (never release more)
    v_release := least(v_release, v_guar.amount_guaranteed - v_guar.amount_released);

    if v_release > 0 then
      update loan_guarantors
         set amount_released = amount_released + v_release
       where id = v_guar.id;
    end if;
  end loop;
end;
$$;

-- Update fn_record_loan_repayment to call the release function
create or replace function fn_record_loan_repayment(
  p_loan_id            uuid,
  p_amount             numeric,
  p_channel            payment_channel,
  p_reference          text,
  p_cash_account_id    uuid
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_loan           record;
  v_prod           record;
  v_entry_id       uuid;
  v_remaining      numeric(14,2) := p_amount;
  v_sched          record;
  v_int_pay        numeric(14,2);
  v_prin_pay       numeric(14,2);
  v_total_interest numeric(14,2) := 0;
  v_total_principal numeric(14,2) := 0;
  v_repay_id       uuid;
begin
  select * into v_loan from loans where id = p_loan_id;
  if v_loan is null then raise exception 'Loan not found'; end if;
  if not has_org_role(v_loan.organisation_id, array['org_admin','treasurer','accountant']::org_role[]) then
    raise exception 'Not authorised to record repayments';
  end if;
  select * into v_prod from loan_products where id = v_loan.product_id;

  -- Apply to installments oldest-first: interest first, then principal
  for v_sched in
    select * from loan_schedule
    where loan_id = p_loan_id and status <> 'paid'
    order by installment_no asc
  loop
    exit when v_remaining <= 0;
    v_int_pay  := least(v_remaining, v_sched.interest_due - v_sched.interest_paid);
    v_remaining := v_remaining - v_int_pay;
    v_prin_pay := least(v_remaining, v_sched.principal_due - v_sched.principal_paid);
    v_remaining := v_remaining - v_prin_pay;

    update loan_schedule
       set interest_paid   = interest_paid + v_int_pay,
           principal_paid  = principal_paid + v_prin_pay,
           status = case
             when (interest_paid + v_int_pay)  >= interest_due
              and (principal_paid + v_prin_pay) >= principal_due then 'paid'
             when (interest_paid + v_int_pay)  > 0
               or (principal_paid + v_prin_pay) > 0 then 'partial'
             else 'pending' end
     where id = v_sched.id;

    v_total_interest  := v_total_interest  + v_int_pay;
    v_total_principal := v_total_principal + v_prin_pay;
  end loop;

  -- Post journal entry
  insert into journal_entries(organisation_id, description, source_type, source_id, created_by)
  values (v_loan.organisation_id, 'Loan repayment', 'loan_repayment', p_loan_id, auth.uid())
  returning id into v_entry_id;

  -- Dr Cash
  insert into journal_lines(journal_entry_id, account_id, debit, credit, member_id)
  values (v_entry_id, p_cash_account_id, v_total_principal + v_total_interest, 0, v_loan.member_id);

  -- Cr Loan Receivable (principal portion)
  if v_total_principal > 0 then
    insert into journal_lines(journal_entry_id, account_id, debit, credit, member_id)
    values (v_entry_id, v_prod.loan_receivable_account_id, 0, v_total_principal, v_loan.member_id);
  end if;

  -- Cr Interest Income (interest portion)
  if v_total_interest > 0 then
    insert into journal_lines(journal_entry_id, account_id, debit, credit, member_id)
    values (v_entry_id, v_prod.interest_income_account_id, 0, v_total_interest, v_loan.member_id);
  end if;

  insert into loan_repayments(
    loan_id, organisation_id, amount, principal_portion,
    interest_portion, channel, reference, journal_entry_id, created_by)
  values (
    p_loan_id, v_loan.organisation_id,
    v_total_principal + v_total_interest,
    v_total_principal, v_total_interest,
    p_channel, p_reference, v_entry_id, auth.uid())
  returning id into v_repay_id;

  -- ── RELEASE GUARANTORS PROPORTIONALLY ─────────────────────────────────
  perform fn_release_guarantors_proportionally(p_loan_id, v_total_principal);

  -- Close loan if fully repaid
  if not exists (
    select 1 from loan_schedule
    where loan_id = p_loan_id and status <> 'paid'
  ) then
    update loans set status = 'closed' where id = p_loan_id;
    -- On full closure, release any remaining rounding on guarantors
    update loan_guarantors
       set amount_released = amount_guaranteed
     where loan_id = p_loan_id
       and amount_released < amount_guaranteed;
  end if;

  return v_repay_id;
end;
$$;

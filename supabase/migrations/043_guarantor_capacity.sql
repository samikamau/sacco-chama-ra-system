-- =========================================================================
-- MIGRATION 043: Guarantor capacity check.
-- 
-- A member can only guarantee up to their UNCOMMITTED deposits.
-- Uncommitted = total deposits - already pledged to other active loans.
--
-- Adds:
--   fn_guarantor_capacity(member_id) → available amount
--   Updated fn_approve_and_disburse_loan → checks each guarantor's capacity
-- =========================================================================

-- ── GUARANTOR CAPACITY ────────────────────────────────────────────────────
create or replace function fn_guarantor_capacity(
  p_member_id       uuid,
  p_exclude_loan_id uuid default null   -- exclude current loan from check
) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_org          uuid;
  v_deposits     numeric(14,2);
  v_committed    numeric(14,2);
  v_available    numeric(14,2);
begin
  select organisation_id into v_org from members where id = p_member_id;
  if not is_org_member(v_org) then raise exception 'Not authorised'; end if;

  -- Total deposits (share_deposit category only — used for loan eligibility)
  select coalesce(sum(pa.amount), 0) into v_deposits
  from payment_allocations pa
  join payments p on p.id = pa.payment_id
  join contribution_types ct on ct.id = pa.contribution_type_id
  where p.member_id = p_member_id
    and p.status = 'posted'
    and ct.category = 'share_deposit';

  -- Already committed as guarantor on OTHER active loans
  select coalesce(sum(lg.amount_guaranteed), 0) into v_committed
  from loan_guarantors lg
  join loans l on l.id = lg.loan_id
  where lg.guarantor_member_id = p_member_id
    and l.status in ('active', 'disbursed', 'pending_approval', 'approved')
    and (p_exclude_loan_id is null or l.id <> p_exclude_loan_id);

  v_available := greatest(v_deposits - v_committed, 0);

  return jsonb_build_object(
    'total_deposits',   v_deposits,
    'committed',        v_committed,
    'available',        v_available
  );
end;
$$;

-- ── UPDATED DISBURSEMENT: checks each guarantor's capacity ────────────────
create or replace function fn_approve_and_disburse_loan(
  p_loan_id         uuid,
  p_cash_account_id uuid
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_loan           record;
  v_prod           record;
  v_elig           jsonb;
  v_guaranteed     numeric(14,2);
  v_entry_id       uuid;
  v_monthly_rate   numeric(12,8);
  v_i              int;
  v_principal_part numeric(14,2);
  v_interest_part  numeric(14,2);
  v_balance        numeric(14,2);
  v_flat_interest  numeric(14,2);
  v_annuity        numeric(14,2);
  v_guar           record;
  v_capacity       jsonb;
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
    raise exception 'Principal % exceeds maximum eligible %',
      v_loan.principal, (v_elig->>'max_eligible');
  end if;
  if not (v_elig->>'meets_min_savings')::boolean then
    raise exception 'Member does not meet the minimum savings requirement';
  end if;

  -- Total guarantor coverage check
  select coalesce(sum(amount_guaranteed), 0) into v_guaranteed
    from loan_guarantors where loan_id = p_loan_id;
  if v_guaranteed < v_loan.principal then
    raise exception
      'Guarantors cover only KES % of principal KES % — full coverage required',
      v_guaranteed, v_loan.principal;
  end if;

  -- Per-guarantor capacity check (blocks over-commitment)
  for v_guar in
    select lg.guarantor_member_id, lg.amount_guaranteed,
           m.full_name
    from loan_guarantors lg
    join members m on m.id = lg.guarantor_member_id
    where lg.loan_id = p_loan_id
  loop
    v_capacity := fn_guarantor_capacity(v_guar.guarantor_member_id, p_loan_id);
    if v_guar.amount_guaranteed > (v_capacity->>'available')::numeric then
      raise exception
        'Guarantor % can only commit KES % (deposits KES % less KES % already committed). Reduce their guarantee amount.',
        v_guar.full_name,
        (v_capacity->>'available')::numeric,
        (v_capacity->>'total_deposits')::numeric,
        (v_capacity->>'committed')::numeric;
    end if;
  end loop;

  -- Post disbursement journal entry
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
    v_flat_interest := round(v_loan.principal * (v_loan.annual_interest_rate/100.0)
                             * (v_loan.term_months/12.0), 2);
    for v_i in 1..v_loan.term_months loop
      v_principal_part := round(v_loan.principal / v_loan.term_months, 2);
      v_interest_part  := round(v_flat_interest / v_loan.term_months, 2);
      insert into loan_schedule(loan_id, organisation_id, installment_no, due_date,
        principal_due, interest_due, total_due)
      values (p_loan_id, v_loan.organisation_id, v_i,
        (v_loan.application_date + (v_i || ' months')::interval)::date,
        v_principal_part, v_interest_part, v_principal_part + v_interest_part);
    end loop;
  else
    if v_monthly_rate = 0 then
      v_annuity := round(v_loan.principal / v_loan.term_months, 2);
    else
      v_annuity := round(v_loan.principal * v_monthly_rate /
                     (1 - power(1 + v_monthly_rate, -v_loan.term_months)), 2);
    end if;
    for v_i in 1..v_loan.term_months loop
      v_interest_part  := round(v_balance * v_monthly_rate, 2);
      v_principal_part := v_annuity - v_interest_part;
      if v_i = v_loan.term_months then v_principal_part := v_balance; end if;
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

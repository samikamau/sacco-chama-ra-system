-- =========================================================================
-- MIGRATION 016: Loan arrears / overdue tracking.
-- No new tables — arrears are DERIVED from loan_schedule vs today's date,
-- so they can never drift out of sync with actual repayments.
-- Run after 001-015 on the SACCO project. Safe to re-run.
-- =========================================================================

-- Per-loan arrears summary: overdue amount = sum of (total_due - paid) on
-- installments whose due_date has passed and aren't fully paid.
create or replace function fn_loan_arrears(p_organisation_id uuid)
returns table (
  loan_id          uuid,
  member_name      text,
  product_name     text,
  principal        numeric,
  outstanding      numeric,     -- remaining principal
  overdue_amount   numeric,     -- past-due unpaid (principal + interest)
  oldest_due_date  date,
  days_overdue     int,
  installments_overdue int
)
language sql stable security definer set search_path = public as $$
  select
    l.id,
    m.full_name,
    lp.name,
    l.principal,
    l.principal - coalesce((
      select sum(lr.principal_portion) from loan_repayments lr where lr.loan_id = l.id
    ),0) as outstanding,
    coalesce(sum((s.total_due - s.principal_paid - s.interest_paid))
             filter (where s.due_date < current_date and s.status <> 'paid'), 0) as overdue_amount,
    min(s.due_date) filter (where s.due_date < current_date and s.status <> 'paid') as oldest_due_date,
    coalesce(current_date - min(s.due_date) filter (where s.due_date < current_date and s.status <> 'paid'), 0) as days_overdue,
    count(*) filter (where s.due_date < current_date and s.status <> 'paid')::int as installments_overdue
  from loans l
  join members m on m.id = l.member_id
  join loan_products lp on lp.id = l.product_id
  left join loan_schedule s on s.loan_id = l.id
  where l.organisation_id = p_organisation_id
    and l.status in ('active','disbursed')
    and is_org_member(p_organisation_id)
  group by l.id, m.full_name, lp.name, l.principal
  having coalesce(sum((s.total_due - s.principal_paid - s.interest_paid))
             filter (where s.due_date < current_date and s.status <> 'paid'), 0) > 0
  order by days_overdue desc;
$$;

-- A compact portfolio view for the dashboard: totals for at-a-glance health.
create or replace function fn_loan_portfolio_summary(p_organisation_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_active int;
  v_outstanding numeric(14,2);
  v_overdue_loans int;
  v_overdue_amount numeric(14,2);
begin
  if not is_org_member(p_organisation_id) then
    raise exception 'Not authorised';
  end if;

  select count(*),
         coalesce(sum(l.principal - coalesce((
            select sum(lr.principal_portion) from loan_repayments lr where lr.loan_id = l.id),0)),0)
    into v_active, v_outstanding
    from loans l
    where l.organisation_id = p_organisation_id and l.status in ('active','disbursed');

  select count(*), coalesce(sum(overdue_amount),0)
    into v_overdue_loans, v_overdue_amount
    from fn_loan_arrears(p_organisation_id);

  return jsonb_build_object(
    'active_loans', v_active,
    'total_outstanding', v_outstanding,
    'overdue_loans', v_overdue_loans,
    'overdue_amount', v_overdue_amount
  );
end;
$$;

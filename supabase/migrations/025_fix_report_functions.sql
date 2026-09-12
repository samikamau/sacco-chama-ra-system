-- =========================================================================
-- MIGRATION 025 v2: Drop and recreate all four report functions cleanly.
-- Fixes balance sheet, I&E, trial balance and cash flow to exclude
-- control/group accounts which were causing double-counting.
-- =========================================================================

-- Drop existing versions first to allow return type changes
drop function if exists fn_balance_sheet(uuid, date);
drop function if exists fn_income_expenditure(uuid, date, date);
drop function if exists fn_trial_balance(uuid, date, date);
drop function if exists fn_cash_flow(uuid, date, date);

-- ── BALANCE SHEET ─────────────────────────────────────────────────────────
create or replace function fn_balance_sheet(
  p_organisation_id uuid,
  p_as_at date default null
) returns table (
  section      text,
  account_code text,
  account_name text,
  amount       numeric
)
language sql stable security definer set search_path = public as $$
  with posted_lines as (
    select
      coa.account_type, coa.code, coa.name,
      coalesce(sum(jl.debit), 0)  as dr,
      coalesce(sum(jl.credit), 0) as cr
    from chart_of_accounts coa
    left join journal_lines jl on jl.account_id = coa.id
    left join journal_entries je on je.id = jl.journal_entry_id
      and je.status = 'posted'
      and (p_as_at is null or je.entry_date <= p_as_at)
    where coa.organisation_id = p_organisation_id
      and is_org_member(p_organisation_id)
      and coalesce(coa.is_control, false) = false
      and coalesce(coa.subtype, '') not in ('group','bank_cash_control')
    group by coa.account_type, coa.code, coa.name
  ),
  surplus as (
    select coalesce(sum(
      case
        when account_type = 'income'  then cr - dr
        when account_type = 'expense' then dr - cr
        else 0
      end
    ), 0) as net_surplus
    from posted_lines
    where account_type in ('income','expense')
  )
  select 'asset'::text, code, name, (dr - cr)
    from posted_lines where account_type = 'asset' and (dr - cr) <> 0
  union all
  select 'liability'::text, code, name, (cr - dr)
    from posted_lines where account_type = 'liability' and (cr - dr) <> 0
  union all
  select 'equity'::text, code, name, (cr - dr)
    from posted_lines where account_type = 'equity' and (cr - dr) <> 0
  union all
  select 'equity'::text, 'RE', 'Accumulated surplus / (deficit)',
    (select net_surplus from surplus)
  order by 1, 2;
$$;

-- ── INCOME & EXPENDITURE ──────────────────────────────────────────────────
create or replace function fn_income_expenditure(
  p_organisation_id uuid,
  p_from date default null,
  p_to   date default null
) returns table (
  account_type text,
  account_code text,
  account_name text,
  amount       numeric
)
language sql stable security definer set search_path = public as $$
  select
    coa.account_type, coa.code, coa.name,
    abs(coalesce(sum(jl.debit),0) - coalesce(sum(jl.credit),0)) as amount
  from chart_of_accounts coa
  join journal_lines jl on jl.account_id = coa.id
  join journal_entries je on je.id = jl.journal_entry_id
    and je.status = 'posted'
    and (p_from is null or je.entry_date >= p_from)
    and (p_to   is null or je.entry_date <= p_to)
  where coa.organisation_id = p_organisation_id
    and is_org_member(p_organisation_id)
    and coa.account_type in ('income','expense')
    and coalesce(coa.is_control, false) = false
    and coalesce(coa.subtype,'') not in ('group','bank_cash_control')
  group by coa.account_type, coa.code, coa.name
  having abs(coalesce(sum(jl.debit),0) - coalesce(sum(jl.credit),0)) > 0
  order by coa.account_type, coa.code;
$$;

-- ── TRIAL BALANCE ─────────────────────────────────────────────────────────
create or replace function fn_trial_balance(
  p_organisation_id uuid,
  p_from date default null,
  p_to   date default null
) returns table (
  account_code text,
  account_name text,
  account_type text,
  total_debit  numeric,
  total_credit numeric,
  balance      numeric
)
language sql stable security definer set search_path = public as $$
  with net as (
    select
      coa.code, coa.name, coa.account_type,
      coalesce(sum(jl.debit),0) - coalesce(sum(jl.credit),0) as bal
    from chart_of_accounts coa
    left join journal_lines jl on jl.account_id = coa.id
    left join journal_entries je on je.id = jl.journal_entry_id
      and je.status = 'posted'
      and (p_from is null or je.entry_date >= p_from)
      and (p_to   is null or je.entry_date <= p_to)
    where coa.organisation_id = p_organisation_id
      and is_org_member(p_organisation_id)
      and coalesce(coa.is_control, false) = false
      and coalesce(coa.subtype,'') not in ('group','bank_cash_control')
    group by coa.code, coa.name, coa.account_type
  )
  select
    code, name, account_type,
    case when bal > 0 then bal else 0 end,
    case when bal < 0 then -bal else 0 end,
    bal
  from net where bal <> 0
  order by code;
$$;

-- ── CASH FLOW ─────────────────────────────────────────────────────────────
create or replace function fn_cash_flow(
  p_organisation_id uuid,
  p_from date default null,
  p_to   date default null
) returns table (
  direction text,
  category  text,
  amount    numeric
)
language sql stable security definer set search_path = public as $$
  select
    case when jl.debit > jl.credit then 'inflow' else 'outflow' end,
    coa.name,
    abs(jl.debit - jl.credit)
  from journal_lines jl
  join journal_entries je on je.id = jl.journal_entry_id
  join chart_of_accounts coa on coa.id = jl.account_id
  where coa.organisation_id = p_organisation_id
    and is_org_member(p_organisation_id)
    and je.status = 'posted'
    and coalesce(coa.is_payment_account, false) = true
    and (p_from is null or je.entry_date >= p_from)
    and (p_to   is null or je.entry_date <= p_to)
  order by 1, 2;
$$;

-- =========================================================================
-- MIGRATION 011 (REPORTS): Trial balance + income & expenditure, derived
-- entirely from posted journal_lines. Read-only functions.
-- Run after 001-010 on the SACCO project. Safe to re-run.
-- =========================================================================

-- -------------------------------------------------------------------------
-- TRIAL BALANCE
-- For each account: sum of debits and credits from POSTED entries only,
-- with a net side. A correct double-entry ledger MUST have total debits =
-- total credits. Optional date range (null = all time).
-- -------------------------------------------------------------------------
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
  balance      numeric      -- debit-positive; assets/expenses normally +, others -
)
language sql stable security definer set search_path = public as $$
  select
    coa.code,
    coa.name,
    coa.account_type,
    coalesce(sum(jl.debit), 0)  as total_debit,
    coalesce(sum(jl.credit), 0) as total_credit,
    coalesce(sum(jl.debit), 0) - coalesce(sum(jl.credit), 0) as balance
  from chart_of_accounts coa
  left join journal_lines jl on jl.account_id = coa.id
  left join journal_entries je on je.id = jl.journal_entry_id
    and je.status = 'posted'
    and (p_from is null or je.entry_date >= p_from)
    and (p_to   is null or je.entry_date <= p_to)
  where coa.organisation_id = p_organisation_id
    and is_org_member(p_organisation_id)
  group by coa.code, coa.name, coa.account_type
  having coalesce(sum(jl.debit),0) <> 0 or coalesce(sum(jl.credit),0) <> 0
  order by coa.code;
$$;

-- -------------------------------------------------------------------------
-- INCOME & EXPENDITURE
-- Income accounts (credit-positive) and expense accounts (debit-positive)
-- over a period, with a surplus/deficit line derivable by the caller.
-- -------------------------------------------------------------------------
create or replace function fn_income_expenditure(
  p_organisation_id uuid,
  p_from date default null,
  p_to   date default null
) returns table (
  account_code text,
  account_name text,
  account_type text,
  amount       numeric
)
language sql stable security definer set search_path = public as $$
  select
    coa.code,
    coa.name,
    coa.account_type,
    case
      when coa.account_type = 'income'  then coalesce(sum(jl.credit),0) - coalesce(sum(jl.debit),0)
      when coa.account_type = 'expense' then coalesce(sum(jl.debit),0)  - coalesce(sum(jl.credit),0)
      else 0
    end as amount
  from chart_of_accounts coa
  left join journal_lines jl on jl.account_id = coa.id
  left join journal_entries je on je.id = jl.journal_entry_id
    and je.status = 'posted'
    and (p_from is null or je.entry_date >= p_from)
    and (p_to   is null or je.entry_date <= p_to)
  where coa.organisation_id = p_organisation_id
    and coa.account_type in ('income','expense')
    and is_org_member(p_organisation_id)
  group by coa.code, coa.name, coa.account_type
  having coalesce(sum(jl.debit),0) <> 0 or coalesce(sum(jl.credit),0) <> 0
  order by coa.account_type, coa.code;
$$;

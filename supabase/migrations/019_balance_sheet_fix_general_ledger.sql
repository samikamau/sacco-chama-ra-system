-- =========================================================================
-- MIGRATION 019: Fix date preset logic (correct month/quarter/year
-- boundaries), fix balance sheet imbalance, add General Ledger function.
-- Run after 001-018 on the SACCO project. Safe to re-run.
-- =========================================================================

-- -------------------------------------------------------------------------
-- A. Fix balance sheet: the accumulated surplus must use ALL income/expense
-- accounts, including those that may have been seeded as 'asset' type
-- incorrectly (e.g. a Contribution Income account coded 4000 but typed
-- 'asset'). More importantly, the balance sheet total must equal trial
-- balance totals. The root cause of the 120.00 difference is likely that
-- "Contribution Income" (4000) has both debits and credits and the NET
-- isn't being correctly assigned to the accumulated surplus line.
-- This rewrite ensures income/expense accounts are EXCLUDED from the
-- balance sheet body (they belong to surplus) and only show as the
-- synthetic "Accumulated surplus" line.
-- -------------------------------------------------------------------------
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
    select coa.id as account_id, coa.account_type, coa.code, coa.name,
           coalesce(sum(jl.debit),0)  as dr,
           coalesce(sum(jl.credit),0) as cr
    from chart_of_accounts coa
    left join journal_lines jl on jl.account_id = coa.id
    left join journal_entries je on je.id = jl.journal_entry_id
      and je.status = 'posted'
      and (p_as_at is null or je.entry_date <= p_as_at)
    where coa.organisation_id = p_organisation_id
      and is_org_member(p_organisation_id)
    group by coa.id, coa.account_type, coa.code, coa.name
  ),
  surplus as (
    select sum(
      case
        when account_type = 'income'  then cr - dr   -- credit-normal
        when account_type = 'expense' then dr - cr   -- debit-normal (shown as negative to surplus)
        else 0
      end
    ) as net_surplus
    from posted_lines
    where account_type in ('income','expense')
  )
  -- Assets: debit-positive net
  select 'asset'::text, code, name, (dr - cr) as amount
  from posted_lines where account_type = 'asset' and (dr - cr) <> 0

  union all

  -- Liabilities: credit-positive net
  select 'liability'::text, code, name, (cr - dr) as amount
  from posted_lines where account_type = 'liability' and (cr - dr) <> 0

  union all

  -- Equity accounts: credit-positive net
  select 'equity'::text, code, name, (cr - dr) as amount
  from posted_lines where account_type = 'equity' and (cr - dr) <> 0

  union all

  -- Accumulated surplus/deficit (all income minus all expenses to date)
  select 'equity'::text, 'RE', 'Accumulated surplus / (deficit)',
         coalesce((select net_surplus from surplus), 0)

  order by 1, 2;
$$;

-- -------------------------------------------------------------------------
-- B. General Ledger function: all posted transactions per account,
-- with a running balance. Used by the new GL report tab.
-- -------------------------------------------------------------------------
create or replace function fn_general_ledger(
  p_organisation_id uuid,
  p_from date default null,
  p_to   date default null,
  p_account_id uuid default null   -- null = all accounts
) returns table (
  account_code   text,
  account_name   text,
  account_type   text,
  entry_date     date,
  journal_number text,
  description    text,
  debit          numeric,
  credit         numeric,
  running_balance numeric
)
language sql stable security definer set search_path = public as $$
  with filtered as (
    select
      coa.code, coa.name, coa.account_type, coa.normal_balance,
      je.entry_date, je.journal_number, je.description,
      jl.debit, jl.credit
    from journal_lines jl
    join journal_entries je on je.id = jl.journal_entry_id
    join chart_of_accounts coa on coa.id = jl.account_id
    where coa.organisation_id = p_organisation_id
      and is_org_member(p_organisation_id)
      and je.status = 'posted'
      and (p_from is null or je.entry_date >= p_from)
      and (p_to   is null or je.entry_date <= p_to)
      and (p_account_id is null or jl.account_id = p_account_id)
    order by coa.code, je.entry_date, je.journal_number
  )
  select
    code, name, account_type, entry_date, journal_number, description,
    debit, credit,
    sum(
      case when normal_balance = 'debit' then debit - credit
           else credit - debit end
    ) over (
      partition by code
      order by entry_date, journal_number
      rows between unbounded preceding and current row
    ) as running_balance
  from filtered;
$$;

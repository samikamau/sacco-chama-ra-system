-- =========================================================================
-- MIGRATION 012: Balance Sheet (Statement of Financial Position) and a
-- simple Cash Flow, both derived from posted journal_lines.
-- Run after 001-011 on the SACCO project. Safe to re-run.
-- =========================================================================

-- -------------------------------------------------------------------------
-- BALANCE SHEET
-- Returns grouped balances as at a date (p_as_at, null = today).
-- Assets are debit-positive; liabilities & equity are credit-positive.
-- Accumulated surplus/deficit (income - expense, all time up to as-at) is
-- returned as a synthetic equity line so the statement balances:
--   total assets = total liabilities + total equity + accumulated surplus
-- -------------------------------------------------------------------------
create or replace function fn_balance_sheet(
  p_organisation_id uuid,
  p_as_at date default null
) returns table (
  section      text,      -- 'asset' | 'liability' | 'equity'
  account_code text,
  account_name text,
  amount       numeric
)
language sql stable security definer set search_path = public as $$
  with lines as (
    select coa.account_type, coa.code, coa.name,
           coalesce(sum(jl.debit),0)  as dr,
           coalesce(sum(jl.credit),0) as cr
    from chart_of_accounts coa
    left join journal_lines jl on jl.account_id = coa.id
    left join journal_entries je on je.id = jl.journal_entry_id
      and je.status = 'posted'
      and (p_as_at is null or je.entry_date <= p_as_at)
    where coa.organisation_id = p_organisation_id
      and is_org_member(p_organisation_id)
    group by coa.account_type, coa.code, coa.name
  )
  -- Assets: debit-positive
  select 'asset'::text, code, name, (dr - cr) as amount
  from lines where account_type = 'asset' and (dr - cr) <> 0
  union all
  -- Liabilities: credit-positive
  select 'liability'::text, code, name, (cr - dr) as amount
  from lines where account_type = 'liability' and (cr - dr) <> 0
  union all
  -- Equity accounts: credit-positive
  select 'equity'::text, code, name, (cr - dr) as amount
  from lines where account_type = 'equity' and (cr - dr) <> 0
  union all
  -- Accumulated surplus/deficit as a synthetic equity line
  select 'equity'::text, 'RE', 'Accumulated surplus / (deficit)',
         coalesce((
           select sum(case when coa.account_type = 'income' then jl.credit - jl.debit
                           when coa.account_type = 'expense' then jl.debit - jl.credit
                           else 0 end)
           from journal_lines jl
           join journal_entries je on je.id = jl.journal_entry_id
           join chart_of_accounts coa on coa.id = jl.account_id
           where coa.organisation_id = p_organisation_id
             and je.status = 'posted'
             and (p_as_at is null or je.entry_date <= p_as_at)
         ), 0)
  order by 1, 2;
$$;

-- -------------------------------------------------------------------------
-- CASH FLOW (direct, simple)
-- Movement on cash/bank/M-Pesa accounts over a period, grouped by the
-- other side of each entry so you can see what drove the movement.
-- "Cash accounts" = asset accounts whose code is in the cash range or that
-- are linked to a bank/mpesa account. Here we treat asset accounts with
-- codes 1000-1099 as cash/bank/M-Pesa (matches the seeded COA).
-- -------------------------------------------------------------------------
create or replace function fn_cash_flow(
  p_organisation_id uuid,
  p_from date default null,
  p_to   date default null
) returns table (
  direction   text,       -- 'inflow' | 'outflow'
  category    text,       -- name of the counterpart account
  amount      numeric
)
language sql stable security definer set search_path = public as $$
  with cash_accounts as (
    select id from chart_of_accounts
    where organisation_id = p_organisation_id
      and account_type = 'asset'
      and code between '1000' and '1099'
  ),
  cash_entries as (
    -- entries that touch a cash account
    select distinct jl.journal_entry_id
    from journal_lines jl
    join cash_accounts ca on ca.id = jl.account_id
  ),
  movements as (
    select
      je.id as entry_id,
      -- net cash movement for this entry (debit to cash = inflow)
      sum(case when jl.account_id in (select id from cash_accounts) then jl.debit - jl.credit else 0 end) as cash_delta
    from journal_entries je
    join journal_lines jl on jl.journal_entry_id = je.id
    where je.organisation_id = p_organisation_id
      and je.status = 'posted'
      and je.id in (select journal_entry_id from cash_entries)
      and (p_from is null or je.entry_date >= p_from)
      and (p_to   is null or je.entry_date <= p_to)
    group by je.id
  ),
  counterparts as (
    -- the non-cash account(s) on each cash-touching entry, with their amount
    select
      m.entry_id,
      m.cash_delta,
      coa.name as category,
      sum(jl.debit + jl.credit) as line_amount
    from movements m
    join journal_lines jl on jl.journal_entry_id = m.entry_id
    join chart_of_accounts coa on coa.id = jl.account_id
    where jl.account_id not in (select id from cash_accounts)
    group by m.entry_id, m.cash_delta, coa.name
  )
  select
    case when cash_delta >= 0 then 'inflow' else 'outflow' end as direction,
    category,
    sum(abs(line_amount)) as amount
  from counterparts
  group by (case when cash_delta >= 0 then 'inflow' else 'outflow' end), category
  order by 1, 3 desc;
$$;

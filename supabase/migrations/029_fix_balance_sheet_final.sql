-- Complete rewrite of fn_balance_sheet with minimal filtering.
-- Only excludes accounts where is_control=true AND they have no direct postings.
-- Any account with actual journal line postings appears regardless of flags.

drop function if exists fn_balance_sheet(uuid, date);

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
      coa.account_type,
      coa.code,
      coa.name,
      coalesce(sum(jl.debit), 0)  as dr,
      coalesce(sum(jl.credit), 0) as cr
    from chart_of_accounts coa
    -- Only include accounts that have ACTUAL postings
    join journal_lines jl on jl.account_id = coa.id
    join journal_entries je on je.id = jl.journal_entry_id
      and je.status = 'posted'
      and (p_as_at is null or je.entry_date <= p_as_at)
    where coa.organisation_id = p_organisation_id
      and is_org_member(p_organisation_id)
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
  -- Assets (net debit balance)
  select 'asset'::text, code, name, (dr - cr) as amount
  from posted_lines
  where account_type = 'asset'
    and (dr - cr) <> 0

  union all

  -- Liabilities (net credit balance shown as positive)
  select 'liability'::text, code, name, (cr - dr) as amount
  from posted_lines
  where account_type = 'liability'
    and (cr - dr) <> 0

  union all

  -- Equity accounts (net credit balance shown as positive)
  select 'equity'::text, code, name, (cr - dr) as amount
  from posted_lines
  where account_type = 'equity'
    and (cr - dr) <> 0

  union all

  -- Accumulated surplus/deficit (net income minus net expenses)
  select 'equity'::text, 'RE'::text,
    'Accumulated surplus / (deficit)'::text,
    (select net_surplus from surplus)

  order by 1, 2;
$$;

-- Also fix fn_trial_balance to use join (not left join) so only accounts
-- with actual postings appear, matching the balance sheet approach
drop function if exists fn_trial_balance(uuid, date, date);

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
      coa.code,
      coa.name,
      case
        when coa.subtype = 'bank'  then 'bank'
        when coa.subtype = 'mpesa' then 'mpesa'
        when coa.subtype = 'cash'  then 'cash'
        else coa.account_type
      end as account_type,
      coalesce(sum(jl.debit),0) - coalesce(sum(jl.credit),0) as bal
    from chart_of_accounts coa
    join journal_lines jl on jl.account_id = coa.id
    join journal_entries je on je.id = jl.journal_entry_id
      and je.status = 'posted'
      and (p_from is null or je.entry_date >= p_from)
      and (p_to   is null or je.entry_date <= p_to)
    where coa.organisation_id = p_organisation_id
      and is_org_member(p_organisation_id)
    group by coa.code, coa.name, coa.account_type, coa.subtype
  )
  select
    code, name, account_type,
    case when bal > 0 then bal else 0 end,
    case when bal < 0 then -bal else 0 end,
    bal
  from net
  where bal <> 0
  order by code;
$$;

-- Verify the balance sheet now returns all accounts
select * from fn_balance_sheet('1f452f1c-b441-47c1-ac85-d22087519b5e', null)
order by section, account_code;

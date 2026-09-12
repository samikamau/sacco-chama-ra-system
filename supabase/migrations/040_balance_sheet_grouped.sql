-- =========================================================================
-- MIGRATION 040: Balance sheet with grouped sections matching the new COA.
-- Groups accounts under their parent category (Bank, Member Receivables etc.)
-- for a professional grouped balance sheet presentation.
-- =========================================================================

drop function if exists fn_balance_sheet(uuid, date);

create or replace function fn_balance_sheet(
  p_organisation_id uuid,
  p_as_at           date default null
) returns table (
  section      text,   -- asset / liability / equity
  group_name   text,   -- e.g. Bank, Member Receivables, Member Funds
  account_code text,
  account_name text,
  amount       numeric
)
language plpgsql stable security invoker set search_path = public as $$
begin
  return query
  with posted as (
    select
      coa.id,
      coa.account_type,
      coa.code,
      coa.name,
      coa.parent_account_id,
      coalesce(sum(jl.debit),  0) as dr,
      coalesce(sum(jl.credit), 0) as cr
    from chart_of_accounts coa
    join journal_lines     jl on jl.account_id   = coa.id
    join journal_entries   je on je.id            = jl.journal_entry_id
                               and je.status      = 'posted'
                               and (p_as_at is null or je.entry_date <= p_as_at)
    where coa.organisation_id = p_organisation_id
    group by coa.id, coa.account_type, coa.code, coa.name, coa.parent_account_id
  ),
  surplus as (
    select coalesce(sum(
      case when account_type='income'  then cr - dr
           when account_type='expense' then dr - cr
           else 0 end), 0) as net
    from posted
    where account_type in ('income','expense')
  ),
  parent_names as (
    select id, name from chart_of_accounts
    where organisation_id = p_organisation_id
  )
  -- Assets
  select 'asset'::text,
    coalesce(pn.name, 'Other Assets') as group_name,
    p.code, p.name, (p.dr - p.cr)
  from posted p
  left join parent_names pn on pn.id = p.parent_account_id
  where p.account_type = 'asset' and (p.dr - p.cr) <> 0

  union all

  -- Liabilities
  select 'liability'::text,
    coalesce(pn.name, 'Other Liabilities'),
    p.code, p.name, (p.cr - p.dr)
  from posted p
  left join parent_names pn on pn.id = p.parent_account_id
  where p.account_type = 'liability' and (p.cr - p.dr) <> 0

  union all

  -- Equity
  select 'equity'::text,
    coalesce(pn.name, 'Member Funds'),
    p.code, p.name, (p.cr - p.dr)
  from posted p
  left join parent_names pn on pn.id = p.parent_account_id
  where p.account_type = 'equity' and (p.cr - p.dr) <> 0

  union all

  -- Accumulated surplus
  select 'equity'::text, 'Retained Earnings', 'RE',
    'Accumulated surplus / (deficit)', (select net from surplus)

  order by 1, 2, 3;
end;
$$;

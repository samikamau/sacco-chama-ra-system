-- =========================================================================
-- MIGRATION 041: Final balance sheet fix.
-- Fixes the left join fan-out bug by using a subquery with DISTINCT
-- instead of joining parent_names which caused row multiplication.
-- Also fixes the surplus sign.
-- =========================================================================

drop function if exists fn_balance_sheet(uuid, date);

create or replace function fn_balance_sheet(
  p_organisation_id uuid,
  p_as_at           date default null
) returns table (
  section      text,
  group_name   text,
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
    join journal_lines   jl on jl.account_id = coa.id
    join journal_entries je on je.id = jl.journal_entry_id
      and je.status = 'posted'
      and (p_as_at is null or je.entry_date <= p_as_at)
    where coa.organisation_id = p_organisation_id
    group by coa.id, coa.account_type, coa.code, coa.name, coa.parent_account_id
  ),
  surplus as (
    select
      coalesce(sum(case when account_type='income'  then cr - dr else 0 end), 0)
    - coalesce(sum(case when account_type='expense' then dr - cr else 0 end), 0)
      as net
    from posted
    where account_type in ('income','expense')
  )
  -- Assets
  select
    'asset'::text,
    coalesce(
      (select name from chart_of_accounts
         where id = p.parent_account_id limit 1),
      'Other Assets'
    ),
    p.code, p.name, (p.dr - p.cr)
  from posted p
  where p.account_type = 'asset' and (p.dr - p.cr) <> 0

  union all

  -- Liabilities
  select
    'liability'::text,
    coalesce(
      (select name from chart_of_accounts
         where id = p.parent_account_id limit 1),
      'Other Liabilities'
    ),
    p.code, p.name, (p.cr - p.dr)
  from posted p
  where p.account_type = 'liability' and (p.cr - p.dr) <> 0

  union all

  -- Equity
  select
    'equity'::text,
    coalesce(
      (select name from chart_of_accounts
         where id = p.parent_account_id limit 1),
      'Member Funds'
    ),
    p.code, p.name, (p.cr - p.dr)
  from posted p
  where p.account_type = 'equity' and (p.cr - p.dr) <> 0

  union all

  -- Accumulated surplus/deficit
  select 'equity'::text, 'Retained Earnings'::text,
    'RE'::text, 'Accumulated surplus / (deficit)'::text,
    (select net from surplus)

  order by 1, 2, 3;
end;
$$;

-- Verify
select section, group_name, account_code, account_name, amount
from fn_balance_sheet('1f452f1c-b441-47c1-ac85-d22087519b5e', null)
order by section, group_name, account_code;

-- Also reverse the migration 027 correcting entries that are now incorrect
-- (the 50,000 and 946.19 correcting entries posted to 1110 Member Loans
-- but were not reversed when we reset the loan data in migration 032)
update journal_entries
   set status = 'reversed'
 where organisation_id = '1f452f1c-b441-47c1-ac85-d22087519b5e'
   and source_type = 'manual'
   and description like 'Correcting entry%'
   and status = 'posted';

-- Re-verify after cleanup
select section, group_name, account_code, account_name, amount
from fn_balance_sheet('1f452f1c-b441-47c1-ac85-d22087519b5e', null)
order by section, group_name, account_code;

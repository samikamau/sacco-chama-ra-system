-- =========================================================================
-- MIGRATION 042: Fix accumulated surplus sign in balance sheet.
-- Surplus = income - expenses. If expenses > income, result is negative
-- (a deficit), displayed as a negative number on the balance sheet.
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
      coa.id, coa.account_type, coa.code, coa.name, coa.parent_account_id,
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
    -- Positive = surplus (income > expenses), Negative = deficit
    select
        coalesce(sum(case when account_type = 'income'  then cr - dr else 0 end), 0)
      - coalesce(sum(case when account_type = 'expense' then dr - cr else 0 end), 0)
      as net
    from posted
    where account_type in ('income', 'expense')
  )
  select 'asset'::text,
    coalesce((select name from chart_of_accounts where id = p.parent_account_id limit 1), 'Other Assets'),
    p.code, p.name, (p.dr - p.cr)
  from posted p where p.account_type = 'asset' and (p.dr - p.cr) <> 0

  union all

  select 'liability'::text,
    coalesce((select name from chart_of_accounts where id = p.parent_account_id limit 1), 'Other Liabilities'),
    p.code, p.name, (p.cr - p.dr)
  from posted p where p.account_type = 'liability' and (p.cr - p.dr) <> 0

  union all

  select 'equity'::text,
    coalesce((select name from chart_of_accounts where id = p.parent_account_id limit 1), 'Member Funds'),
    p.code, p.name, (p.cr - p.dr)
  from posted p where p.account_type = 'equity' and (p.cr - p.dr) <> 0

  union all

  -- Accumulated surplus: positive = surplus adds to equity,
  -- negative = deficit reduces equity
  select 'equity'::text, 'Retained Earnings'::text,
    'RE'::text, 'Accumulated surplus / (deficit)'::text,
    (select net from surplus)

  order by 1, 2, 3;
end;
$$;

-- Verify surplus sign
select account_code, account_name, amount
from fn_balance_sheet('1f452f1c-b441-47c1-ac85-d22087519b5e', null)
where account_code = 'RE';

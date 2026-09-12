-- =========================================================================
-- MIGRATION 033: Final balance sheet fix.
--
-- The surplus calculation was wrong: income account 4000 nets to zero
-- (debits = credits = 15,813) so it contributes nothing to surplus.
-- Only expense 5200 has a real net: 3,500 Dr = a deficit of 3,500.
-- Correct accumulated surplus = income_net - expense_net = 0 - 3,500 = -3,500
--
-- The balance sheet function surplus CTE was:
--   income:  cr - dr  (correct: credits exceed debits = income)
--   expense: dr - cr  (correct: debits exceed credits = expense cost)
-- But because income nets to 0, surplus = 0 - 3,500 = -3,500 (deficit).
-- The function was returning 3,500 positive — it was using expense dr - cr
-- but adding it instead of subtracting. Fix below.
-- =========================================================================

drop function if exists fn_balance_sheet(uuid, date);

create or replace function fn_balance_sheet(
  p_organisation_id uuid,
  p_as_at           date default null
) returns table (
  section      text,
  account_code text,
  account_name text,
  amount       numeric
)
language plpgsql stable security invoker set search_path = public as $$
begin
  return query
  with posted as (
    select
      coa.account_type,
      coa.code,
      coa.name,
      coalesce(sum(jl.debit),  0) as dr,
      coalesce(sum(jl.credit), 0) as cr
    from chart_of_accounts coa
    join journal_lines     jl on jl.account_id   = coa.id
    join journal_entries   je on je.id            = jl.journal_entry_id
                               and je.status      = 'posted'
                               and (p_as_at is null or je.entry_date <= p_as_at)
    where coa.organisation_id = p_organisation_id
    group by coa.account_type, coa.code, coa.name
  ),
  surplus as (
    -- Net surplus = sum of all income credit-nets MINUS sum of all expense debit-nets
    select
      coalesce(sum(case when account_type = 'income'  then cr - dr else 0 end), 0)
    - coalesce(sum(case when account_type = 'expense' then dr - cr else 0 end), 0)
      as net
    from posted
    where account_type in ('income','expense')
  )
  select 'asset'::text,     code, name, (dr - cr)
    from posted where account_type = 'asset'     and (dr - cr) <> 0
  union all
  select 'liability'::text, code, name, (cr - dr)
    from posted where account_type = 'liability' and (cr - dr) <> 0
  union all
  select 'equity'::text,    code, name, (cr - dr)
    from posted where account_type = 'equity'    and (cr - dr) <> 0
  union all
  select 'equity'::text, 'RE', 'Accumulated surplus / (deficit)',
    (select net from surplus)
  order by 1, 2;
end;
$$;

-- Verify
select section, account_code, account_name, amount
from fn_balance_sheet('1f452f1c-b441-47c1-ac85-d22087519b5e', null)
order by section, account_code;

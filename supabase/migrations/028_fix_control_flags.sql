-- =========================================================================
-- MIGRATION 028: Fix is_control flags on accounts that have real postings.
--
-- Root cause: migrations 018 and 022 marked some accounts as control/group
-- accounts, but those same accounts already had real journal postings from
-- earlier migrations. The report functions correctly exclude control accounts
-- but this caused accounts with real balances to disappear from reports.
--
-- Fix:
--   1000 Assets          — has 5,025.19 in postings → unmark as control
--   3000 Member Share Capital — has 23,013 in postings → unmark as control
--
-- Going forward: the control account trigger (fn_block_control_account_posting)
-- prevents NEW postings to control accounts. These fixes only affect the
-- historical accounts that had postings before the trigger existed.
-- =========================================================================

-- Fix 1000: it has real postings — it is not a pure group header.
-- Keep it as the Assets parent but allow it to hold its historical balance.
update chart_of_accounts
   set is_control = false,
       subtype    = 'cash',          -- it was seeded as "Cash on Hand"
       name       = 'Cash on Hand',  -- restore the original name
       description = 'Cash on hand (historical postings before bank accounts were separated)'
 where organisation_id = '1f452f1c-b441-47c1-ac85-d22087519b5e'
   and code = '1000'
   and subtype = 'group';

-- Fix 3000: Member Share Capital has real postings — not a control account.
update chart_of_accounts
   set is_control = false,
       subtype    = 'retained_earnings'
 where organisation_id = '1f452f1c-b441-47c1-ac85-d22087519b5e'
   and code = '3000';

-- Verify: run a quick balance check after the fix
-- Total assets should now equal total liabilities + equity + net income
with balances as (
  select
    coa.account_type,
    coalesce(coa.subtype,'') as subtype,
    coalesce(coa.is_control, false) as is_ctrl,
    coalesce(sum(jl.debit),0) - coalesce(sum(jl.credit),0) as net
  from chart_of_accounts coa
  left join journal_lines jl on jl.account_id = coa.id
  left join journal_entries je on je.id = jl.journal_entry_id
    and je.status = 'posted'
  where coa.organisation_id = '1f452f1c-b441-47c1-ac85-d22087519b5e'
    and coalesce(coa.is_control, false) = false
    and coalesce(coa.subtype,'') not in ('group','bank_cash_control')
  group by coa.account_type, coa.subtype, coa.is_control
)
select
  sum(case when account_type = 'asset'   then net else 0 end) as total_assets,
  sum(case when account_type = 'liability' then -net else 0 end) as total_liabilities,
  sum(case when account_type = 'equity'  then -net else 0 end) as total_equity,
  sum(case when account_type = 'income'  then -net else 0 end) as total_income,
  sum(case when account_type = 'expense' then  net else 0 end) as total_expenses,
  sum(case when account_type = 'asset'   then net else 0 end) -
  sum(case when account_type in ('liability','equity') then -net else 0 end) -
  (sum(case when account_type = 'income' then -net else 0 end) -
   sum(case when account_type = 'expense' then net else 0 end)) as balance_sheet_difference
from balances;

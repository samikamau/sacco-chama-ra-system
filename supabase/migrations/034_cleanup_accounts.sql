-- =========================================================================
-- MIGRATION 034: Clean up account 4000.
-- 4000 "Contribution Income" has a wash entry (Dr=Cr=15,813) from an old
-- reallocation. Since contributions correctly post to fund accounts (2010,
-- 2020, 3000), not to income, 4000 is not needed. We deactivate it and
-- rename it to clarify it should not be used.
-- Also deactivate the seeded "Cash on Hand" (1000) group account since
-- it was originally a seed artifact and all cash now correctly flows through
-- 1010 Bank Account and 1020 M-Pesa Account.
-- =========================================================================

-- Rename and deactivate 4000 — it has a wash balance so it doesn't affect reports
update chart_of_accounts
   set name = 'Contribution Income (legacy - do not use)',
       is_active = false,
       description = 'Legacy account with wash entries from reallocation. Deactivated.'
 where organisation_id = '1f452f1c-b441-47c1-ac85-d22087519b5e'
   and code = '4000';

-- Confirm 4100 Interest Income exists and is active (this is the real income account)
insert into chart_of_accounts(organisation_id, code, name, account_type,
    subtype, normal_balance, is_active, description)
  values ('1f452f1c-b441-47c1-ac85-d22087519b5e', '4100', 'Interest Income',
    'income', 'operating', 'credit', true,
    'Interest earned on member loans. Primary income account.')
  on conflict (organisation_id, code) do update
    set is_active = true,
        name = 'Interest Income',
        description = 'Interest earned on member loans. Primary income account.';

-- Verify final balance sheet
select section, account_code, account_name, amount
from fn_balance_sheet('1f452f1c-b441-47c1-ac85-d22087519b5e', null)
order by section, account_code;

-- =========================================================================
-- MIGRATION 037: Rename 1000 "Bank & Cash" to "Bank".
-- Bank is the main account under which all cash, bank and M-Pesa
-- sub-accounts are grouped.
-- =========================================================================
update chart_of_accounts
   set name = 'Bank'
 where organisation_id = '1f452f1c-b441-47c1-ac85-d22087519b5e'
   and code = '1000';

-- Confirm
select code, name, subtype, is_control
  from chart_of_accounts
 where organisation_id = '1f452f1c-b441-47c1-ac85-d22087519b5e'
   and code like '1%'
   and is_active = true
 order by code;

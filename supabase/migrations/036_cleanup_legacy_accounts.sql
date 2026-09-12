-- =========================================================================
-- MIGRATION 036: Clean up legacy temp-coded accounts left from migration 035.
-- 9011 and 9012 are deactivated; give them proper codes so they don't look odd.
-- =========================================================================
update chart_of_accounts set code='2099', name='Current Liabilities (legacy)'
  where organisation_id='1f452f1c-b441-47c1-ac85-d22087519b5e' and code='9011';
update chart_of_accounts set code='2098', name='Loan Interest Payable (legacy)'
  where organisation_id='1f452f1c-b441-47c1-ac85-d22087519b5e' and code='9012';

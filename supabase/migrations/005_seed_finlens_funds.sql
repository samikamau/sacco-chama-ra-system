-- =========================================================================
-- MIGRATION 005: Seed Share Capital / Share Deposits / Welfare for
-- Finlens Ledgers specifically. Replace v_org_id if reusing for another org.
-- =========================================================================
do $$
declare
  v_org_id uuid := '1f452f1c-b441-47c1-ac85-d22087519b5e';
  v_share_capital_account uuid;
  v_share_deposit_account uuid;
  v_welfare_account uuid;
begin
  -- New chart of accounts entries for each fund
  insert into chart_of_accounts (organisation_id, code, name, account_type)
  values (v_org_id, '3000', 'Member Share Capital', 'equity')
  on conflict (organisation_id, code) do nothing;

  insert into chart_of_accounts (organisation_id, code, name, account_type)
  values (v_org_id, '2010', 'Member Share Deposits', 'liability')
  on conflict (organisation_id, code) do nothing;

  insert into chart_of_accounts (organisation_id, code, name, account_type)
  values (v_org_id, '2020', 'Member Welfare Fund', 'liability')
  on conflict (organisation_id, code) do nothing;

  select id into v_share_capital_account from chart_of_accounts where organisation_id = v_org_id and code = '3000';
  select id into v_share_deposit_account from chart_of_accounts where organisation_id = v_org_id and code = '2010';
  select id into v_welfare_account from chart_of_accounts where organisation_id = v_org_id and code = '2020';

  insert into contribution_types (organisation_id, name, category, chart_account_id, is_recurring)
  values
    (v_org_id, 'Share Capital', 'share_capital', v_share_capital_account, false),
    (v_org_id, 'Share Deposits', 'share_deposit', v_share_deposit_account, true),
    (v_org_id, 'Welfare', 'welfare', v_welfare_account, true)
  on conflict (organisation_id, name) do nothing;
end $$;

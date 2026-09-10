-- =========================================================================
-- MIGRATION 014: Seed a default loan product for Finlens Ledgers.
-- Uses existing accounts 1100 (Member Loans Receivable) and 4100 (Interest
-- Income) from the original chart of accounts.
-- =========================================================================
do $$
declare
  v_org uuid := '1f452f1c-b441-47c1-ac85-d22087519b5e';
  v_recv uuid;
  v_int  uuid;
begin
  select id into v_recv from chart_of_accounts where organisation_id = v_org and code = '1100';
  select id into v_int  from chart_of_accounts where organisation_id = v_org and code = '4100';

  insert into loan_products(organisation_id, name, savings_multiplier, interest_method,
    annual_interest_rate, max_term_months, min_savings, savings_category,
    loan_receivable_account_id, interest_income_account_id)
  values (v_org, 'Standard Loan (3x deposits, reducing balance)', 3, 'reducing',
    12, 12, 0, 'share_deposit', v_recv, v_int)
  on conflict (organisation_id, name) do nothing;
end $$;

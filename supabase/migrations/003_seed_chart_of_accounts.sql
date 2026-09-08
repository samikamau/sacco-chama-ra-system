-- =========================================================================
-- SEED: Standard chart of accounts for a new organisation (SACCO/Chama)
-- Run once per organisation, after phase1_schema.sql, replacing the UUID
-- below with the real organisation id (from the `organisations` table).
-- =========================================================================

do $$
declare
  v_org_id uuid := '00000000-0000-0000-0000-000000000000'; -- <-- replace me
begin
  insert into chart_of_accounts (organisation_id, code, name, account_type) values
    (v_org_id, '1000', 'Cash on Hand',            'asset'),
    (v_org_id, '1010', 'Bank Account',            'asset'),
    (v_org_id, '1020', 'M-Pesa Account',          'asset'),
    (v_org_id, '1100', 'Member Loans Receivable', 'asset'),
    (v_org_id, '2000', 'Member Contributions',    'liability'),
    (v_org_id, '2100', 'Member Loan Interest Payable', 'liability'),
    (v_org_id, '4000', 'Contribution Income',     'income'),
    (v_org_id, '4100', 'Interest Income',         'income'),
    (v_org_id, '4200', 'Fine Income',             'income'),
    (v_org_id, '5000', 'Administration Expense',  'expense'),
    (v_org_id, '5100', 'Bank Charges',            'expense')
  on conflict (organisation_id, code) do nothing;
end $$;

-- After running, note the ids of "Bank Account" / "M-Pesa Account" / "Cash
-- on Hand" and "Contribution Income" — the frontend payment form passes
-- these into fn_record_and_post_payment() as p_cash_account_id and
-- p_contribution_income_account_id.

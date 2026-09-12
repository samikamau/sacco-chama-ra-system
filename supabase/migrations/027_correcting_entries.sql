-- =========================================================================
-- MIGRATION 027: Correcting journal entries for test data issues.
--
-- Fix 1: Reverse the orphaned loan repayment on Loan 1 (946.19).
--         The disbursement was reversed but the repayment journal remained,
--         leaving a 946.19 credit on Member Loans Receivable with no
--         matching disbursement debit.
--
-- Fix 2: Post the missing disbursement for Loan 2 (50,000).
--         Repayments of 20,550.75 exist but no disbursement journal was
--         ever posted, leaving the loan receivable understated by 50,000.
--
-- Both entries use admin user id: 1b135187-4015-4c40-83c6-5d5e7782990c
-- Account IDs confirmed from live database:
--   1010 Bank Account:            1c595b01-6733-4353-bba9-967a52ef27fd
--   1020 M-Pesa Account:          02793c29-ff22-4753-baf1-1e429d2dd943
--   1100 Member Loans Receivable: 5f9b25e8-1995-4dd4-a76e-5611c64f6753
-- =========================================================================

do $$
declare
  v_org   uuid := '1f452f1c-b441-47c1-ac85-d22087519b5e';
  v_admin uuid := '1b135187-4015-4c40-83c6-5d5e7782990c';
  v_bank  uuid := '1c595b01-6733-4353-bba9-967a52ef27fd';
  v_loans uuid := '5f9b25e8-1995-4dd4-a76e-5611c64f6753';
  v_entry1 uuid;
  v_entry2 uuid;
  v_num1   text;
  v_num2   text;
begin

  -- ── FIX 1: Reverse orphaned repayment on Loan 1 (946.19) ──────────────
  -- The repayment credited Loans Receivable and debited Bank.
  -- Reversing it: Dr Loans Receivable 946.19 / Cr Bank 946.19
  v_num1 := fn_next_journal_number(v_org);
  insert into journal_entries(
    organisation_id, entry_date, description, source_type,
    status, journal_number, created_by)
  values (
    v_org, current_date,
    'Correcting entry: reverse orphaned Loan 1 repayment (disbursement was reversed but repayment journal remained)',
    'manual', 'posted', v_num1, v_admin)
  returning id into v_entry1;

  -- Dr Loans Receivable (restores debit, cancels the credit from orphaned repayment)
  insert into journal_lines(journal_entry_id, account_id, debit, credit)
  values (v_entry1, v_loans, 946.19, 0);

  -- Cr Bank Account (returns the cash notionally taken out by the repayment)
  insert into journal_lines(journal_entry_id, account_id, debit, credit)
  values (v_entry1, v_bank, 0, 946.19);

  raise notice 'Fix 1 posted: % — reverse orphaned Loan 1 repayment', v_num1;

  -- ── FIX 2: Post missing disbursement for Loan 2 (50,000) ──────────────
  -- The 50,000 loan had repayments posted but no disbursement journal.
  -- Dr Loans Receivable 50,000 / Cr Bank Account 50,000
  v_num2 := fn_next_journal_number(v_org);
  insert into journal_entries(
    organisation_id, entry_date, description, source_type,
    status, journal_number, created_by)
  values (
    v_org, '2026-09-09',
    'Correcting entry: post missing disbursement for Loan 2 (50,000) — disbursement was approved but journal was not posted',
    'manual', 'posted', v_num2, v_admin)
  returning id into v_entry2;

  -- Dr Loans Receivable 50,000
  insert into journal_lines(journal_entry_id, account_id, debit, credit)
  values (v_entry2, v_loans, 50000.00, 0);

  -- Cr Bank Account 50,000 (the cash that went out when the loan was disbursed)
  insert into journal_lines(journal_entry_id, account_id, debit, credit)
  values (v_entry2, v_bank, 0, 50000.00);

  raise notice 'Fix 2 posted: % — missing Loan 2 disbursement', v_num2;

end $$;

-- Verify: after this runs, account 1100 should net to a DEBIT
-- (total disbursed minus total repaid = outstanding principal)
select
  coalesce(sum(jl.debit),0)  as total_debit,
  coalesce(sum(jl.credit),0) as total_credit,
  coalesce(sum(jl.debit),0) - coalesce(sum(jl.credit),0) as net_balance,
  case
    when coalesce(sum(jl.debit),0) - coalesce(sum(jl.credit),0) > 0
    then '✓ Correct — net debit (money owed to SACCO)'
    else '✗ Still wrong — net credit'
  end as status
from journal_lines jl
join journal_entries je on je.id = jl.journal_entry_id
join chart_of_accounts coa on coa.id = jl.account_id
where coa.code = '1100'
  and coa.organisation_id = '1f452f1c-b441-47c1-ac85-d22087519b5e'
  and je.status = 'posted';

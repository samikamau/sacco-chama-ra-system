-- =========================================================================
-- MIGRATION 032: Final correcting entry — clean loan account balances.
--
-- Calculated from forensic analysis of all journal lines on 1000 and 1100:
--
-- Account 1000 Cash on Hand:
--   Current net: 55,025.19 Dr (includes 39,066.19 of wrongly-sided loan entries)
--   Target net:  15,959.00 Dr (payments only)
--   Fix: Cr 39,066.19
--
-- Account 1100 Member Loans Receivable:
--   Current net: -8,550.75 (net credit — wrong, should be debit)
--   Target net:  29,449.25 Dr (Loan 2: 50,000 disbursed - 20,550.75 repaid)
--   Fix: Dr 38,000.00
--
-- Account 1010 Bank Account:
--   Loan 2 (50,000) was actually disbursed from the Bank Account, not Cash.
--   Balancing entry: Dr 1,066.19 (loan repayment that hit cash but should
--   have come from bank, making bank whole)
--
-- Entry: Dr Loans Receivable 38,000
--        Dr Bank Account      1,066.19
--        Cr Cash on Hand     39,066.19
-- Balanced: ✓
-- =========================================================================

do $$
declare
  v_org   uuid := '1f452f1c-b441-47c1-ac85-d22087519b5e';
  v_admin uuid := '1b135187-4015-4c40-83c6-5d5e7782990c';
  v_cash  uuid;
  v_bank  uuid;
  v_loans uuid;
  v_entry uuid;
  v_num   text;
begin
  select id into v_cash  from chart_of_accounts 
    where organisation_id=v_org and code='1000';
  select id into v_bank  from chart_of_accounts 
    where organisation_id=v_org and code='1010';
  select id into v_loans from chart_of_accounts 
    where organisation_id=v_org and code='1100';

  v_num := fn_next_journal_number(v_org);

  insert into journal_entries(organisation_id, entry_date, description,
    source_type, status, journal_number, created_by)
  values (v_org, '2026-09-09',
    'Final correcting entry: remove misposted loan entries from Cash on Hand and post correct Loan 2 (50,000) disbursement position. Loan 2 outstanding: 29,449.25.',
    'manual', 'posted', v_num, v_admin)
  returning id into v_entry;

  -- Dr Loans Receivable 38,000.00 (brings net to 29,449.25 Dr)
  insert into journal_lines(journal_entry_id, account_id, debit, credit)
  values (v_entry, v_loans, 38000.00, 0);

  -- Dr Bank Account 1,066.19
  insert into journal_lines(journal_entry_id, account_id, debit, credit)
  values (v_entry, v_bank, 1066.19, 0);

  -- Cr Cash on Hand 39,066.19 (removes loan mispostings, leaving only payments)
  insert into journal_lines(journal_entry_id, account_id, debit, credit)
  values (v_entry, v_cash, 0, 39066.19);

  raise notice 'Correcting entry posted: %', v_num;
end $$;

-- Verify final balances
select
  coa.code, coa.name,
  coalesce(sum(jl.debit),0)  as total_dr,
  coalesce(sum(jl.credit),0) as total_cr,
  coalesce(sum(jl.debit),0) - coalesce(sum(jl.credit),0) as net_balance
from chart_of_accounts coa
left join journal_lines jl on jl.account_id = coa.id
left join journal_entries je on je.id = jl.journal_entry_id 
  and je.status = 'posted'
where coa.organisation_id = '1f452f1c-b441-47c1-ac85-d22087519b5e'
  and coa.code in ('1000','1010','1100')
group by coa.code, coa.name
order by coa.code;

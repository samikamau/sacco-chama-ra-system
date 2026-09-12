-- =========================================================================
-- MIGRATION 032 v2: Reset test loan data.
-- Uses 'reversed' status instead of 'void' (which doesn't exist in the enum).
-- =========================================================================

do $$
declare
  v_org  uuid := '1f452f1c-b441-47c1-ac85-d22087519b5e';
  v_l1   uuid := '92a22a80-9b05-4692-8fbd-a120938df566';
  v_l2   uuid := '92df75ca-f515-43dd-8c60-6d7a09a6a09a';
  v_1100 uuid := '5f9b25e8-1995-4dd4-a76e-5611c64f6753';
begin
  -- Add 'cancelled' to the enum if not present, else use 'reversed'
  -- First check what values exist
  -- We'll use 'reversed' as it already exists

  -- Mark all journal entries touching account 1100 as reversed
  update journal_entries
     set status = 'reversed'
   where id in (
     select distinct je.id
     from journal_entries je
     join journal_lines jl on jl.journal_entry_id = je.id
     where jl.account_id = v_1100
       and je.organisation_id = v_org
   );

  -- Also mark the null-numbered reversal entry
  update journal_entries
     set status = 'reversed'
   where organisation_id = v_org
     and source_type = 'reversal'
     and journal_number is null;

  -- Delete loan repayments
  delete from loan_repayments where loan_id in (v_l1, v_l2);

  -- Delete loan schedules
  delete from loan_schedule where loan_id in (v_l1, v_l2);

  -- Reset loans to draft
  update loans
     set status = 'draft',
         approved_by = null,
         approved_at = null,
         disbursed_at = null,
         disbursement_entry_id = null
   where id in (v_l1, v_l2);

  raise notice 'Done. Both loans reset to draft.';
end $$;

-- Verify account 1100 net on POSTED entries only
select
  coalesce(sum(jl.debit),0)  as total_dr,
  coalesce(sum(jl.credit),0) as total_cr,
  coalesce(sum(jl.debit),0) - coalesce(sum(jl.credit),0) as net
from journal_lines jl
join journal_entries je on je.id = jl.journal_entry_id
join chart_of_accounts coa on coa.id = jl.account_id
where coa.code = '1100'
  and coa.organisation_id = '1f452f1c-b441-47c1-ac85-d22087519b5e'
  and je.status = 'posted';

-- Full balance sheet
select section, account_code, account_name, amount
from fn_balance_sheet('1f452f1c-b441-47c1-ac85-d22087519b5e', null)
order by section, account_code;

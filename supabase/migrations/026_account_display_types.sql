-- =========================================================================
-- MIGRATION 026: Add 'bank' and 'mpesa' as recognised account subtypes
-- for display purposes, and update report functions to group bank/mpesa
-- accounts under a "Bank" display category rather than plain "asset".
--
-- We do NOT change account_type (that stays 'asset' for accounting
-- correctness — bank accounts ARE assets). We use the existing subtype
-- column to drive the display label in reports and the trial balance.
-- =========================================================================

-- Update subtypes for the payment accounts
update chart_of_accounts
   set subtype = 'bank'
 where organisation_id = '1f452f1c-b441-47c1-ac85-d22087519b5e'
   and code = '1010';

update chart_of_accounts
   set subtype = 'mpesa'
 where organisation_id = '1f452f1c-b441-47c1-ac85-d22087519b5e'
   and code = '1020';

-- Update the trial balance to show a friendly type label
-- (bank/mpesa instead of just 'asset') without changing accounting logic
create or replace function fn_trial_balance(
  p_organisation_id uuid,
  p_from date default null,
  p_to   date default null
) returns table (
  account_code text,
  account_name text,
  account_type text,
  total_debit  numeric,
  total_credit numeric,
  balance      numeric
)
language sql stable security definer set search_path = public as $$
  with net as (
    select
      coa.code, coa.name,
      -- Show meaningful display type
      case
        when coa.subtype = 'bank'  then 'bank'
        when coa.subtype = 'mpesa' then 'mpesa'
        when coa.subtype = 'cash'  then 'cash'
        else coa.account_type
      end as account_type,
      coalesce(sum(jl.debit),0) - coalesce(sum(jl.credit),0) as bal
    from chart_of_accounts coa
    left join journal_lines jl on jl.account_id = coa.id
    left join journal_entries je on je.id = jl.journal_entry_id
      and je.status = 'posted'
      and (p_from is null or je.entry_date >= p_from)
      and (p_to   is null or je.entry_date <= p_to)
    where coa.organisation_id = p_organisation_id
      and is_org_member(p_organisation_id)
      and coalesce(coa.is_control, false) = false
      and coalesce(coa.subtype,'') not in ('group','bank_cash_control')
    group by coa.code, coa.name, coa.account_type, coa.subtype
  )
  select
    code, name, account_type,
    case when bal > 0 then bal else 0 end,
    case when bal < 0 then -bal else 0 end,
    bal
  from net where bal <> 0
  order by code;
$$;

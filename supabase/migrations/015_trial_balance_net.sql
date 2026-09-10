-- =========================================================================
-- MIGRATION 015: Trial balance shows the NET balance per account in a
-- single column (debit OR credit), per standard TB presentation.
-- Assets & expenses normally net to the debit side; liabilities, equity
-- and income to the credit side, but we place each account by the sign of
-- its actual net so contra positions still display correctly.
-- Run after 001-014. Safe to re-run.
-- =========================================================================

create or replace function fn_trial_balance(
  p_organisation_id uuid,
  p_from date default null,
  p_to   date default null
) returns table (
  account_code text,
  account_name text,
  account_type text,
  total_debit  numeric,   -- net debit (0 if the account nets to credit)
  total_credit numeric,   -- net credit (0 if the account nets to debit)
  balance      numeric    -- signed net (debit-positive)
)
language sql stable security definer set search_path = public as $$
  with net as (
    select
      coa.code, coa.name, coa.account_type,
      coalesce(sum(jl.debit),0) - coalesce(sum(jl.credit),0) as bal
    from chart_of_accounts coa
    left join journal_lines jl on jl.account_id = coa.id
    left join journal_entries je on je.id = jl.journal_entry_id
      and je.status = 'posted'
      and (p_from is null or je.entry_date >= p_from)
      and (p_to   is null or je.entry_date <= p_to)
    where coa.organisation_id = p_organisation_id
      and is_org_member(p_organisation_id)
    group by coa.code, coa.name, coa.account_type
  )
  select
    code, name, account_type,
    case when bal > 0 then bal else 0 end as total_debit,
    case when bal < 0 then -bal else 0 end as total_credit,
    bal as balance
  from net
  where bal <> 0
  order by code;
$$;

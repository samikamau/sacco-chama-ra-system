-- =========================================================================
-- MIGRATION 030: Final balance sheet fix.
-- Removes is_org_member() from inside CTEs — it was silently filtering
-- out all rows when called in a security definer context.
-- Membership is checked once at the start, not inside the data query.
-- =========================================================================

drop function if exists fn_balance_sheet(uuid, date);

create or replace function fn_balance_sheet(
  p_organisation_id uuid,
  p_as_at           date default null
) returns table (
  section      text,
  account_code text,
  account_name text,
  amount       numeric
)
language plpgsql stable security definer set search_path = public as $$
begin
  -- Single membership check up front
  if not is_org_member(p_organisation_id) then
    raise exception 'Not authorised';
  end if;

  return query
  with posted as (
    select
      coa.account_type,
      coa.code,
      coa.name,
      coalesce(sum(jl.debit),  0) as dr,
      coalesce(sum(jl.credit), 0) as cr
    from chart_of_accounts coa
    join journal_lines     jl  on jl.account_id       = coa.id
    join journal_entries   je  on je.id               = jl.journal_entry_id
                               and je.status          = 'posted'
                               and (p_as_at is null or je.entry_date <= p_as_at)
    where coa.organisation_id = p_organisation_id
    group by coa.account_type, coa.code, coa.name
  ),
  surplus as (
    select coalesce(sum(
      case
        when account_type = 'income'  then cr - dr
        when account_type = 'expense' then dr - cr
        else 0
      end
    ), 0) as net
    from posted
    where account_type in ('income','expense')
  )
  select 'asset'::text,     code, name, (dr - cr)
    from posted where account_type = 'asset'     and (dr - cr) <> 0
  union all
  select 'liability'::text, code, name, (cr - dr)
    from posted where account_type = 'liability' and (cr - dr) <> 0
  union all
  select 'equity'::text,    code, name, (cr - dr)
    from posted where account_type = 'equity'    and (cr - dr) <> 0
  union all
  select 'equity'::text, 'RE', 'Accumulated surplus / (deficit)', (select net from surplus)
  order by 1, 2;
end;
$$;

-- Same fix for fn_income_expenditure
drop function if exists fn_income_expenditure(uuid, date, date);

create or replace function fn_income_expenditure(
  p_organisation_id uuid,
  p_from date default null,
  p_to   date default null
) returns table (
  account_type text,
  account_code text,
  account_name text,
  amount       numeric
)
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_org_member(p_organisation_id) then
    raise exception 'Not authorised';
  end if;

  return query
  select
    coa.account_type,
    coa.code,
    coa.name,
    abs(coalesce(sum(jl.debit),0) - coalesce(sum(jl.credit),0)) as amount
  from chart_of_accounts coa
  join journal_lines   jl on jl.account_id       = coa.id
  join journal_entries je on je.id               = jl.journal_entry_id
                          and je.status          = 'posted'
                          and (p_from is null or je.entry_date >= p_from)
                          and (p_to   is null or je.entry_date <= p_to)
  where coa.organisation_id = p_organisation_id
    and coa.account_type in ('income','expense')
  group by coa.account_type, coa.code, coa.name
  having abs(coalesce(sum(jl.debit),0) - coalesce(sum(jl.credit),0)) > 0
  order by coa.account_type, coa.code;
end;
$$;

-- Same fix for fn_trial_balance
drop function if exists fn_trial_balance(uuid, date, date);

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
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_org_member(p_organisation_id) then
    raise exception 'Not authorised';
  end if;

  return query
  with net as (
    select
      coa.code,
      coa.name,
      case
        when coa.subtype = 'bank'  then 'bank'
        when coa.subtype = 'mpesa' then 'mpesa'
        when coa.subtype = 'cash'  then 'cash'
        else coa.account_type
      end as acct_type,
      coalesce(sum(jl.debit),0) - coalesce(sum(jl.credit),0) as bal
    from chart_of_accounts coa
    join journal_lines   jl on jl.account_id       = coa.id
    join journal_entries je on je.id               = jl.journal_entry_id
                            and je.status          = 'posted'
                            and (p_from is null or je.entry_date >= p_from)
                            and (p_to   is null or je.entry_date <= p_to)
    where coa.organisation_id = p_organisation_id
    group by coa.code, coa.name, coa.account_type, coa.subtype
  )
  select
    code, name, acct_type,
    case when bal > 0 then bal else 0 end,
    case when bal < 0 then -bal else 0 end,
    bal
  from net where bal <> 0
  order by code;
end;
$$;

-- Same fix for fn_cash_flow
drop function if exists fn_cash_flow(uuid, date, date);

create or replace function fn_cash_flow(
  p_organisation_id uuid,
  p_from date default null,
  p_to   date default null
) returns table (
  direction text,
  category  text,
  amount    numeric
)
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_org_member(p_organisation_id) then
    raise exception 'Not authorised';
  end if;

  return query
  select
    case when jl.debit > jl.credit then 'inflow' else 'outflow' end,
    coa.name,
    abs(jl.debit - jl.credit)
  from journal_lines   jl
  join journal_entries je  on je.id             = jl.journal_entry_id
  join chart_of_accounts coa on coa.id          = jl.account_id
  where coa.organisation_id = p_organisation_id
    and je.status            = 'posted'
    and coalesce(coa.is_payment_account, false) = true
    and (p_from is null or je.entry_date >= p_from)
    and (p_to   is null or je.entry_date <= p_to)
  order by 1, 2;
end;
$$;

-- Verify
select * from fn_balance_sheet('1f452f1c-b441-47c1-ac85-d22087519b5e', null)
order by section, account_code;

-- =========================================================================
-- MIGRATION 018 FIX: Corrected chart of accounts hierarchy seed.
-- Avoids code collisions with existing accounts (1100 = Member Loans
-- Receivable, so Current Assets group gets code 1050 instead).
-- Run this INSTEAD OF or AFTER the failed 018 run.
-- Safe to re-run — uses ON CONFLICT.
-- =========================================================================

-- Re-run the column additions (idempotent)
alter table chart_of_accounts
  add column if not exists parent_account_id uuid references chart_of_accounts(id),
  add column if not exists subtype text,
  add column if not exists description text,
  add column if not exists normal_balance text default 'debit'
    check (normal_balance in ('debit','credit'));

do $$ begin
  alter table chart_of_accounts
    add constraint chk_no_self_parent check (parent_account_id <> id);
exception when duplicate_object then null; end $$;

create index if not exists idx_coa_parent on chart_of_accounts(organisation_id, parent_account_id);

-- Fix normal_balance for existing accounts
update chart_of_accounts set normal_balance = 'credit'
  where account_type in ('liability','equity','income') and normal_balance = 'debit';
update chart_of_accounts set normal_balance = 'debit'
  where account_type in ('asset','expense') and (normal_balance is null or normal_balance = 'debit');

-- Add update RLS policy
drop policy if exists p_coa_update on chart_of_accounts;
create policy p_coa_update on chart_of_accounts for update
  using (has_org_role(organisation_id, array['org_admin','accountant']::org_role[]));

-- Seed hierarchy for Finlens Ledgers
do $$
declare
  v_org      uuid := '1f452f1c-b441-47c1-ac85-d22087519b5e';
  v_assets   uuid; v_curr_assets uuid; v_fixed_assets uuid;
  v_liab     uuid; v_curr_liab   uuid;
  v_equity   uuid;
  v_income   uuid;
  v_expenses uuid;
begin
  -- 1000 Assets (top-level group)
  insert into chart_of_accounts(organisation_id, code, name, account_type, subtype, normal_balance, is_active)
    values(v_org,'1000','Assets','asset','group','debit',true)
    on conflict(organisation_id, code) do update set name='Assets', subtype='group';
  select id into v_assets from chart_of_accounts where organisation_id=v_org and code='1000';

  -- 1050 Current Assets (avoids clash with existing 1100 = Member Loans Receivable)
  insert into chart_of_accounts(organisation_id, code, name, account_type, subtype, normal_balance, parent_account_id, is_active)
    values(v_org,'1050','Current Assets','asset','current_asset','debit',v_assets,true)
    on conflict(organisation_id, code) do update set parent_account_id=excluded.parent_account_id, subtype='current_asset';
  select id into v_curr_assets from chart_of_accounts where organisation_id=v_org and code='1050';

  -- 1250 Fixed Assets
  insert into chart_of_accounts(organisation_id, code, name, account_type, subtype, normal_balance, parent_account_id, is_active)
    values(v_org,'1250','Fixed Assets','asset','fixed_asset','debit',v_assets,true)
    on conflict(organisation_id, code) do update set parent_account_id=excluded.parent_account_id, subtype='fixed_asset';
  select id into v_fixed_assets from chart_of_accounts where organisation_id=v_org and code='1250';

  -- Re-parent existing cash/bank/M-Pesa under Current Assets (1000=group, 1010=Bank, 1020=M-Pesa, 1000=Cash on Hand seeded as 1000)
  -- Note: 1000 is now the group so we skip it; re-parent only the cash/bank/mpesa leaf accounts
  update chart_of_accounts
    set parent_account_id = v_curr_assets, subtype = 'current_asset'
    where organisation_id = v_org
      and code in ('1010','1020')
      and id <> v_assets;   -- never re-parent the group itself

  -- Re-parent Member Loans Receivable under Current Assets
  update chart_of_accounts
    set parent_account_id = v_curr_assets, subtype = 'current_asset'
    where organisation_id = v_org and code = '1100';

  -- 2000 Liabilities
  insert into chart_of_accounts(organisation_id, code, name, account_type, subtype, normal_balance, is_active)
    values(v_org,'2000','Liabilities','liability','group','credit',true)
    on conflict(organisation_id, code) do update set name='Liabilities', subtype='group';
  select id into v_liab from chart_of_accounts where organisation_id=v_org and code='2000';

  insert into chart_of_accounts(organisation_id, code, name, account_type, subtype, normal_balance, parent_account_id, is_active)
    values(v_org,'2050','Current Liabilities','liability','current_liability','credit',v_liab,true)
    on conflict(organisation_id, code) do update set parent_account_id=excluded.parent_account_id;
  select id into v_curr_liab from chart_of_accounts where organisation_id=v_org and code='2050';

  update chart_of_accounts
    set parent_account_id = v_curr_liab, subtype = 'current_liability'
    where organisation_id = v_org
      and account_type = 'liability'
      and code not in ('2000','2050')
      and parent_account_id is null;

  -- 3000 Equity
  insert into chart_of_accounts(organisation_id, code, name, account_type, subtype, normal_balance, is_active)
    values(v_org,'3000','Equity','equity','group','credit',true)
    on conflict(organisation_id, code) do update set subtype='group';
  select id into v_equity from chart_of_accounts where organisation_id=v_org and code='3000';

  update chart_of_accounts
    set parent_account_id = v_equity
    where organisation_id = v_org
      and account_type = 'equity'
      and code <> '3000'
      and parent_account_id is null;

  -- 4000 Income
  insert into chart_of_accounts(organisation_id, code, name, account_type, subtype, normal_balance, is_active)
    values(v_org,'4000','Income','income','group','credit',true)
    on conflict(organisation_id, code) do update set subtype='group';
  select id into v_income from chart_of_accounts where organisation_id=v_org and code='4000';

  update chart_of_accounts
    set parent_account_id = v_income
    where organisation_id = v_org
      and account_type = 'income'
      and code <> '4000'
      and parent_account_id is null;

  -- 5000 Expenses
  insert into chart_of_accounts(organisation_id, code, name, account_type, subtype, normal_balance, is_active)
    values(v_org,'5000','Expenses','expense','group','debit',true)
    on conflict(organisation_id, code) do update set subtype='group';
  select id into v_expenses from chart_of_accounts where organisation_id=v_org and code='5000';

  update chart_of_accounts
    set parent_account_id = v_expenses
    where organisation_id = v_org
      and account_type = 'expense'
      and code <> '5000'
      and parent_account_id is null;
end $$;

-- Recursive hierarchy view
create or replace view v_coa_hierarchy as
with recursive coa_tree as (
  select id, organisation_id, code, name, account_type, subtype,
         normal_balance, is_active, parent_account_id, description,
         0 as depth,
         code::text as sort_path
  from chart_of_accounts
  where parent_account_id is null

  union all

  select c.id, c.organisation_id, c.code, c.name, c.account_type, c.subtype,
         c.normal_balance, c.is_active, c.parent_account_id, c.description,
         t.depth + 1,
         t.sort_path || '.' || c.code
  from chart_of_accounts c
  join coa_tree t on t.id = c.parent_account_id
)
select * from coa_tree order by sort_path;

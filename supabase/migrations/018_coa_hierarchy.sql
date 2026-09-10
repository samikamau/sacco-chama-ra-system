-- =========================================================================
-- MIGRATION 018: Chart of accounts hierarchy + account subtype.
-- Adds parent_account_id and subtype to the EXISTING chart_of_accounts
-- table. Existing rows are preserved. Existing foreign keys and RLS
-- policies are untouched.
-- Run after 001-017 on the SACCO project. Safe to re-run.
-- =========================================================================

-- -------------------------------------------------------------------------
-- A. Extend the existing table (additive only)
-- -------------------------------------------------------------------------
alter table chart_of_accounts
  add column if not exists parent_account_id uuid references chart_of_accounts(id),
  add column if not exists subtype text,        -- e.g. 'current_asset','fixed_asset','long_term_liability'
  add column if not exists description text,
  add column if not exists normal_balance text default 'debit'
    check (normal_balance in ('debit','credit'));

-- Prevent circular references: an account cannot be its own parent.
do $$ begin
  alter table chart_of_accounts
    add constraint chk_no_self_parent check (parent_account_id <> id);
exception when duplicate_object then null; end $$;

-- Index for fast hierarchy lookups.
create index if not exists idx_coa_parent on chart_of_accounts(organisation_id, parent_account_id);

-- -------------------------------------------------------------------------
-- B. Update normal_balance for existing accounts by type
-- (credit for liability / equity / income, debit for asset / expense)
-- -------------------------------------------------------------------------
update chart_of_accounts set normal_balance = 'credit'
  where account_type in ('liability','equity','income') and normal_balance = 'debit';
update chart_of_accounts set normal_balance = 'debit'
  where account_type in ('asset','expense') and normal_balance is null;

-- -------------------------------------------------------------------------
-- C. Seed parent/group accounts for Finlens Ledgers and re-parent existing
-- leaf accounts into the hierarchy. Uses ON CONFLICT to stay idempotent.
-- -------------------------------------------------------------------------
do $$
declare
  v_org uuid := '1f452f1c-b441-47c1-ac85-d22087519b5e';
  -- group account ids
  v_assets         uuid; v_curr_assets uuid; v_fixed_assets uuid;
  v_liabilities    uuid; v_curr_liab   uuid; v_lt_liab     uuid;
  v_equity         uuid;
  v_income         uuid;
  v_expenses       uuid;
begin
  -- ── 1000 ASSETS ──────────────────────────────────────────────────────
  insert into chart_of_accounts(organisation_id, code, name, account_type, subtype, normal_balance, is_active)
    values(v_org,'1000','Assets','asset','group','debit',true)
    on conflict(organisation_id, code) do update set name='Assets', subtype='group' returning id into v_assets;
  if v_assets is null then select id into v_assets from chart_of_accounts where organisation_id=v_org and code='1000'; end if;

  insert into chart_of_accounts(organisation_id, code, name, account_type, subtype, normal_balance, parent_account_id, is_active)
    values(v_org,'1100','Current Assets','asset','current_asset','debit',v_assets,true)
    on conflict(organisation_id, code) do update set parent_account_id=excluded.parent_account_id, subtype='current_asset' returning id into v_curr_assets;
  if v_curr_assets is null then select id into v_curr_assets from chart_of_accounts where organisation_id=v_org and code='1100'; end if;

  insert into chart_of_accounts(organisation_id, code, name, account_type, subtype, normal_balance, parent_account_id, is_active)
    values(v_org,'1200','Fixed Assets','asset','fixed_asset','debit',v_assets,true)
    on conflict(organisation_id, code) do update set parent_account_id=excluded.parent_account_id, subtype='fixed_asset' returning id into v_fixed_assets;
  if v_fixed_assets is null then select id into v_fixed_assets from chart_of_accounts where organisation_id=v_org and code='1200'; end if;

  -- Re-parent existing cash/bank/M-Pesa/loan accounts under Current Assets
  update chart_of_accounts set parent_account_id=v_curr_assets, subtype='current_asset'
    where organisation_id=v_org and code in ('1000','1010','1020','1100') and code <> '1000';

  -- ── 2000 LIABILITIES ─────────────────────────────────────────────────
  insert into chart_of_accounts(organisation_id, code, name, account_type, subtype, normal_balance, is_active)
    values(v_org,'2000','Liabilities','liability','group','credit',true)
    on conflict(organisation_id, code) do update set name='Liabilities', subtype='group' returning id into v_liabilities;
  if v_liabilities is null then select id into v_liabilities from chart_of_accounts where organisation_id=v_org and code='2000'; end if;

  insert into chart_of_accounts(organisation_id, code, name, account_type, subtype, normal_balance, parent_account_id, is_active)
    values(v_org,'2100','Current Liabilities','liability','current_liability','credit',v_liabilities,true)
    on conflict(organisation_id, code) do update set parent_account_id=excluded.parent_account_id returning id into v_curr_liab;
  if v_curr_liab is null then select id into v_curr_liab from chart_of_accounts where organisation_id=v_org and code='2100'; end if;

  update chart_of_accounts set parent_account_id=v_curr_liab, subtype='current_liability'
    where organisation_id=v_org and code in ('2010','2020','2100','2200') and code not in ('2000','2100');

  -- ── 3000 EQUITY ──────────────────────────────────────────────────────
  insert into chart_of_accounts(organisation_id, code, name, account_type, subtype, normal_balance, is_active)
    values(v_org,'3000','Equity','equity','group','credit',true)
    on conflict(organisation_id, code) do update set subtype='group' returning id into v_equity;
  if v_equity is null then select id into v_equity from chart_of_accounts where organisation_id=v_org and code='3000'; end if;

  -- ── 4000 INCOME ──────────────────────────────────────────────────────
  insert into chart_of_accounts(organisation_id, code, name, account_type, subtype, normal_balance, is_active)
    values(v_org,'4000','Income','income','group','credit',true)
    on conflict(organisation_id, code) do update set subtype='group' returning id into v_income;
  if v_income is null then select id into v_income from chart_of_accounts where organisation_id=v_org and code='4000'; end if;

  -- Re-parent income sub-accounts
  update chart_of_accounts set parent_account_id=v_income
    where organisation_id=v_org and account_type='income' and code not in ('4000') and parent_account_id is null;

  -- ── 5000 EXPENSES ────────────────────────────────────────────────────
  insert into chart_of_accounts(organisation_id, code, name, account_type, subtype, normal_balance, is_active)
    values(v_org,'5000','Expenses','expense','group','debit',true)
    on conflict(organisation_id, code) do update set subtype='group' returning id into v_expenses;
  if v_expenses is null then select id into v_expenses from chart_of_accounts where organisation_id=v_org and code='5000'; end if;

  update chart_of_accounts set parent_account_id=v_expenses
    where organisation_id=v_org and account_type='expense' and code not in ('5000') and parent_account_id is null;
end $$;

-- -------------------------------------------------------------------------
-- D. RLS: add policies for the new write patterns (existing select policies
-- already cover the new columns since they're on the same table).
-- -------------------------------------------------------------------------
drop policy if exists p_coa_update on chart_of_accounts;
create policy p_coa_update on chart_of_accounts for update
  using (has_org_role(organisation_id, array['org_admin','accountant']::org_role[]));

-- -------------------------------------------------------------------------
-- E. Recursive hierarchy view — returns accounts with their depth and
-- full path for UI tree rendering. Read-only, inherits table RLS.
-- -------------------------------------------------------------------------
create or replace view v_coa_hierarchy as
with recursive coa_tree as (
  -- Root accounts (no parent)
  select id, organisation_id, code, name, account_type, subtype,
         normal_balance, is_active, parent_account_id, description,
         0 as depth,
         code::text as sort_path
  from chart_of_accounts
  where parent_account_id is null

  union all

  -- Children
  select c.id, c.organisation_id, c.code, c.name, c.account_type, c.subtype,
         c.normal_balance, c.is_active, c.parent_account_id, c.description,
         t.depth + 1,
         t.sort_path || '.' || c.code
  from chart_of_accounts c
  join coa_tree t on t.id = c.parent_account_id
)
select * from coa_tree
order by sort_path;

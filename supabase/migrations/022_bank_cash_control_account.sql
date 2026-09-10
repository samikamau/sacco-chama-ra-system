-- =========================================================================
-- MIGRATION 022: "Bank and Cash" as a control (parent) account.
--
-- Structure:
--   1000 Assets                        (group)
--     1050 Current Assets              (group)
--       1060 Bank and Cash Accounts    (CONTROL — parent of all payment accounts)
--         1000 Cash on Hand            (leaf — receipts/payments)
--         1010 Bank Account            (leaf — receipts/payments)
--         1020 M-Pesa Account          (leaf — receipts/payments)
--       1100 Member Loans Receivable   (leaf)
--
-- Every payment and receipt must be posted to a LEAF account under 1060.
-- The control account itself is never posted to directly.
--
-- Run after 001-021. Safe to re-run.
-- =========================================================================

-- -------------------------------------------------------------------------
-- A. Add an is_control flag so the UI knows which accounts cannot be posted to
-- -------------------------------------------------------------------------
alter table chart_of_accounts
  add column if not exists is_control boolean not null default false,
  add column if not exists is_payment_account boolean not null default false;

comment on column chart_of_accounts.is_control is
  'True for group/header accounts that must never receive direct postings.';
comment on column chart_of_accounts.is_payment_account is
  'True for leaf cash/bank/M-Pesa accounts that payments and receipts post to.';

-- -------------------------------------------------------------------------
-- B. Build the hierarchy for Finlens Ledgers
-- -------------------------------------------------------------------------
do $$
declare
  v_org        uuid := '1f452f1c-b441-47c1-ac85-d22087519b5e';
  v_assets     uuid;
  v_curr       uuid;
  v_bankcash   uuid;
begin
  -- Ensure the group accounts exist
  select id into v_assets from chart_of_accounts where organisation_id=v_org and code='1000' and subtype='group';
  if v_assets is null then
    insert into chart_of_accounts(organisation_id,code,name,account_type,subtype,normal_balance,is_control,is_active)
      values(v_org,'1000','Assets','asset','group','debit',true,true)
      on conflict(organisation_id,code) do update set subtype='group', is_control=true
      returning id into v_assets;
  end if;

  select id into v_curr from chart_of_accounts where organisation_id=v_org and code='1050';
  if v_curr is null then
    insert into chart_of_accounts(organisation_id,code,name,account_type,subtype,normal_balance,parent_account_id,is_control,is_active)
      values(v_org,'1050','Current Assets','asset','current_asset','debit',v_assets,true,true)
      returning id into v_curr;
  else
    update chart_of_accounts set is_control=true, parent_account_id=v_assets where id=v_curr;
  end if;

  -- ── THE CONTROL ACCOUNT: 1060 Bank and Cash Accounts ────────────────
  insert into chart_of_accounts(organisation_id,code,name,account_type,subtype,
      normal_balance,parent_account_id,is_control,is_active,description)
    values(v_org,'1060','Bank and Cash Accounts','asset','bank_cash_control','debit',
      v_curr,true,true,'Control account. All payments and receipts post to its sub-accounts.')
    on conflict(organisation_id,code) do update
      set name='Bank and Cash Accounts', is_control=true,
          parent_account_id=excluded.parent_account_id,
          subtype='bank_cash_control';
  select id into v_bankcash from chart_of_accounts where organisation_id=v_org and code='1060';

  -- ── Re-parent the actual payment accounts under the control ─────────
  -- Cash on Hand: the original seed used code 1000, which is now the Assets
  -- group. If a separate cash account exists under another code, catch it too.
  update chart_of_accounts
     set parent_account_id = v_bankcash,
         is_payment_account = true,
         is_control = false,
         subtype = 'cash'
   where organisation_id = v_org
     and name ilike '%cash%'
     and account_type = 'asset'
     and subtype is distinct from 'group'
     and id <> v_bankcash;

  update chart_of_accounts
     set parent_account_id = v_bankcash,
         is_payment_account = true,
         is_control = false,
         subtype = 'bank'
   where organisation_id = v_org and code = '1010';

  update chart_of_accounts
     set parent_account_id = v_bankcash,
         is_payment_account = true,
         is_control = false,
         subtype = 'mpesa'
   where organisation_id = v_org and code = '1020';

  -- Loans receivable stays under Current Assets, NOT a payment account
  update chart_of_accounts
     set parent_account_id = v_curr, is_payment_account = false, is_control = false
   where organisation_id = v_org and code = '1100';

  -- Mark all group/header accounts as control accounts
  update chart_of_accounts set is_control = true
   where organisation_id = v_org and subtype = 'group';
end $$;

-- -------------------------------------------------------------------------
-- C. Guard: block direct postings to control accounts
-- -------------------------------------------------------------------------
create or replace function fn_block_control_account_posting()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_is_control boolean; v_name text; v_code text;
begin
  select is_control, name, code into v_is_control, v_name, v_code
    from chart_of_accounts where id = new.account_id;
  if coalesce(v_is_control,false) then
    raise exception 'Account % (%) is a control account and cannot receive direct postings. Post to one of its sub-accounts instead.', v_code, v_name;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_block_control_posting on journal_lines;
create trigger trg_block_control_posting
  before insert on journal_lines
  for each row execute function fn_block_control_account_posting();

-- -------------------------------------------------------------------------
-- D. Helper: list the payment accounts (used by payment/receipt forms)
-- -------------------------------------------------------------------------
create or replace function fn_payment_accounts(p_organisation_id uuid)
returns table (id uuid, code text, name text, subtype text)
language sql stable security definer set search_path = public as $$
  select id, code, name, subtype
  from chart_of_accounts
  where organisation_id = p_organisation_id
    and is_payment_account = true
    and is_active = true
    and is_org_member(p_organisation_id)
  order by code;
$$;

-- -------------------------------------------------------------------------
-- E. Bank and Cash control balance (sum of all its sub-accounts)
-- -------------------------------------------------------------------------
create or replace function fn_bank_cash_balance(
  p_organisation_id uuid,
  p_as_at date default null
) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce(sum(jl.debit - jl.credit), 0)
  from journal_lines jl
  join journal_entries je on je.id = jl.journal_entry_id
  join chart_of_accounts coa on coa.id = jl.account_id
  where coa.organisation_id = p_organisation_id
    and coa.is_payment_account = true
    and je.status = 'posted'
    and is_org_member(p_organisation_id)
    and (p_as_at is null or je.entry_date <= p_as_at);
$$;

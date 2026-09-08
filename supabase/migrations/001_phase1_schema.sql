-- =========================================================================
-- PHASE 1 MIGRATION
-- Financial Operating System for Small Member-Based Organisations
-- Scope: org setup, users/roles, members, contributions, payments,
--        bank/M-Pesa import + matching, reconciliation, core ledger,
--        member statements (via view/query), audit trail.
-- Excludes (later phases): loans, guarantors, fines, units/service
--        charges, assets, depreciation, period closing enforcement
--        beyond a basic flag.
--
-- SAFE TO RUN: this is a fresh migration (no existing tables assumed).
-- Run this in Supabase Studio -> SQL Editor -> New query -> paste -> Run.
-- Run top to bottom in ONE transaction where possible; if it fails partway,
-- fix the reported error and re-run from the top (all statements use
-- IF NOT EXISTS / CREATE OR REPLACE so re-running is not destructive).
-- =========================================================================

-- -------------------------------------------------------------------------
-- 0. EXTENSIONS
-- -------------------------------------------------------------------------
create extension if not exists pgcrypto;   -- gen_random_uuid()

-- -------------------------------------------------------------------------
-- 1. ENUM TYPES
-- -------------------------------------------------------------------------
do $$ begin
  create type org_type as enum ('sacco','chama','residents_association','other');
exception when duplicate_object then null; end $$;

do $$ begin
  create type org_role as enum ('org_admin','treasurer','accountant','secretary','viewer');
exception when duplicate_object then null; end $$;

do $$ begin
  create type member_status as enum ('active','dormant','suspended','exited');
exception when duplicate_object then null; end $$;

do $$ begin
  create type contribution_status as enum ('unpaid','partial','paid','overpaid');
exception when duplicate_object then null; end $$;

do $$ begin
  create type payment_channel as enum ('mpesa','bank','cash','cheque','other');
exception when duplicate_object then null; end $$;

do $$ begin
  create type match_status as enum ('unmatched','suggested','matched','duplicate','already_posted');
exception when duplicate_object then null; end $$;

do $$ begin
  create type journal_status as enum ('posted','reversed');
exception when duplicate_object then null; end $$;

-- -------------------------------------------------------------------------
-- 2. CORE TENANT TABLES
-- -------------------------------------------------------------------------
create table if not exists organisations (
  id                uuid primary key default gen_random_uuid(),
  name              text not null,
  org_type          org_type not null default 'sacco',
  currency          text not null default 'KES',
  status            text not null default 'active' check (status in ('active','suspended')),
  created_at        timestamptz not null default now(),
  created_by        uuid references auth.users(id)
);

create table if not exists organisation_settings (
  organisation_id           uuid primary key references organisations(id) on delete cascade,
  default_allocation_policy text not null default 'oldest_first'
                              check (default_allocation_policy in ('oldest_first','manual_only')),
  match_auto_threshold      numeric(5,2) not null default 0.90,  -- >= this score auto-matches
  match_suggest_threshold   numeric(5,2) not null default 0.60,  -- >= this score = "suggested"
  segregation_of_duties     boolean not null default true,       -- approver != requester
  updated_at                timestamptz not null default now()
);

create table if not exists organisation_users (
  id                uuid primary key default gen_random_uuid(),
  organisation_id   uuid not null references organisations(id) on delete cascade,
  user_id           uuid not null references auth.users(id) on delete cascade,
  role              org_role not null default 'viewer',
  status            text not null default 'active' check (status in ('active','disabled')),
  created_at        timestamptz not null default now(),
  unique (organisation_id, user_id)
);

create index if not exists idx_org_users_org on organisation_users(organisation_id);
create index if not exists idx_org_users_user on organisation_users(user_id);

-- -------------------------------------------------------------------------
-- 3. HELPER FUNCTIONS FOR RLS (kept simple and fast; used in every policy)
-- -------------------------------------------------------------------------
create or replace function is_org_member(p_org_id uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from organisation_users ou
    where ou.organisation_id = p_org_id
      and ou.user_id = auth.uid()
      and ou.status = 'active'
  );
$$;

create or replace function org_role_of(p_org_id uuid)
returns org_role
language sql stable security definer set search_path = public as $$
  select ou.role from organisation_users ou
  where ou.organisation_id = p_org_id
    and ou.user_id = auth.uid()
    and ou.status = 'active'
  limit 1;
$$;

create or replace function has_org_role(p_org_id uuid, p_roles org_role[])
returns boolean
language sql stable security definer set search_path = public as $$
  select org_role_of(p_org_id) = any(p_roles);
$$;

-- -------------------------------------------------------------------------
-- 4. MEMBERS
-- -------------------------------------------------------------------------
create table if not exists members (
  id                uuid primary key default gen_random_uuid(),
  organisation_id   uuid not null references organisations(id) on delete cascade,
  member_number     text not null,
  full_name         text not null,
  phone             text,
  email             text,
  id_number         text,
  date_joined       date not null default current_date,
  status            member_status not null default 'active',
  monthly_contribution numeric(14,2),
  next_of_kin       text,
  notes             text,
  created_at        timestamptz not null default now(),
  created_by        uuid references auth.users(id),
  unique (organisation_id, member_number)
);

create index if not exists idx_members_org on members(organisation_id);
create index if not exists idx_members_phone on members(organisation_id, phone);

-- -------------------------------------------------------------------------
-- 5. CONTRIBUTION RULES / PERIODS / CONTRIBUTIONS
-- -------------------------------------------------------------------------
create table if not exists contribution_rules (
  id                uuid primary key default gen_random_uuid(),
  organisation_id   uuid not null references organisations(id) on delete cascade,
  name              text not null default 'Standard monthly contribution',
  amount            numeric(14,2) not null check (amount >= 0),
  frequency         text not null default 'monthly' check (frequency in ('monthly','quarterly','annual')),
  due_day           int not null default 5 check (due_day between 1 and 28),
  grace_days        int not null default 5 check (grace_days >= 0),
  penalty_type      text not null default 'none' check (penalty_type in ('none','flat','percentage')),
  penalty_value     numeric(14,2) not null default 0,
  active            boolean not null default true,
  created_at        timestamptz not null default now()
);

create table if not exists contribution_periods (
  id                uuid primary key default gen_random_uuid(),
  organisation_id   uuid not null references organisations(id) on delete cascade,
  rule_id           uuid not null references contribution_rules(id),
  period_start      date not null,
  period_end        date not null,
  due_date          date not null,
  generated_at      timestamptz not null default now(),
  unique (rule_id, period_start)
);

create table if not exists contributions (
  id                uuid primary key default gen_random_uuid(),
  organisation_id   uuid not null references organisations(id) on delete cascade,
  member_id         uuid not null references members(id) on delete cascade,
  period_id         uuid not null references contribution_periods(id) on delete cascade,
  amount_expected   numeric(14,2) not null check (amount_expected >= 0),
  amount_paid       numeric(14,2) not null default 0 check (amount_paid >= 0),
  status            contribution_status not null default 'unpaid',
  created_at        timestamptz not null default now(),
  unique (member_id, period_id)
);

create index if not exists idx_contrib_org on contributions(organisation_id);
create index if not exists idx_contrib_member on contributions(member_id);
create index if not exists idx_contrib_period on contributions(period_id);

-- -------------------------------------------------------------------------
-- 6. CHART OF ACCOUNTS / JOURNAL / GENERAL LEDGER
-- -------------------------------------------------------------------------
create table if not exists chart_of_accounts (
  id                uuid primary key default gen_random_uuid(),
  organisation_id   uuid not null references organisations(id) on delete cascade,
  code              text not null,
  name              text not null,
  account_type      text not null check (account_type in ('asset','liability','equity','income','expense')),
  is_active         boolean not null default true,
  unique (organisation_id, code)
);

create table if not exists accounting_periods (
  id                uuid primary key default gen_random_uuid(),
  organisation_id   uuid not null references organisations(id) on delete cascade,
  period_start      date not null,
  period_end        date not null,
  status            text not null default 'open' check (status in ('open','closed')),
  closed_at         timestamptz,
  closed_by         uuid references auth.users(id),
  unique (organisation_id, period_start)
);

create table if not exists journal_entries (
  id                uuid primary key default gen_random_uuid(),
  organisation_id   uuid not null references organisations(id) on delete cascade,
  entry_date        date not null default current_date,
  description       text not null,
  source_type       text not null,      -- e.g. 'contribution','payment','manual'
  source_id         uuid,               -- id of the originating row, where applicable
  status            journal_status not null default 'posted',
  reversed_entry_id uuid references journal_entries(id),
  created_at        timestamptz not null default now(),
  created_by        uuid references auth.users(id)
);

create table if not exists journal_lines (
  id                uuid primary key default gen_random_uuid(),
  journal_entry_id  uuid not null references journal_entries(id) on delete cascade,
  account_id        uuid not null references chart_of_accounts(id),
  debit             numeric(14,2) not null default 0 check (debit >= 0),
  credit            numeric(14,2) not null default 0 check (credit >= 0),
  member_id         uuid references members(id),   -- optional, for member-level ledger queries
  check (not (debit > 0 and credit > 0))            -- a line is either a debit or a credit, not both
);

create index if not exists idx_jl_entry on journal_lines(journal_entry_id);
create index if not exists idx_jl_account on journal_lines(account_id);
create index if not exists idx_jl_member on journal_lines(member_id);

-- Enforce that every journal entry balances (sum debit = sum credit) the
-- moment its lines are committed. Deferred so all lines can be inserted
-- together inside one transaction before the check runs.
create or replace function fn_check_journal_balances(p_entry_id uuid)
returns void language plpgsql as $$
declare
  v_diff numeric(14,2);
begin
  select coalesce(sum(debit),0) - coalesce(sum(credit),0)
    into v_diff
    from journal_lines where journal_entry_id = p_entry_id;
  if v_diff <> 0 then
    raise exception 'Journal entry % does not balance (difference %)', p_entry_id, v_diff;
  end if;
end;
$$;

create or replace function trg_journal_lines_balance()
returns trigger language plpgsql as $$
begin
  perform fn_check_journal_balances(coalesce(new.journal_entry_id, old.journal_entry_id));
  return null;
end;
$$;

drop trigger if exists trg_journal_balance_check on journal_lines;
create constraint trigger trg_journal_balance_check
  after insert or update or delete on journal_lines
  deferrable initially deferred
  for each row execute function trg_journal_lines_balance();

-- Posted journal rows cannot be deleted (reverse instead).
create or replace function fn_prevent_journal_delete()
returns trigger language plpgsql as $$
begin
  raise exception 'Posted journal entries cannot be deleted. Use fn_reverse_journal_entry() instead.';
end;
$$;

drop trigger if exists trg_no_delete_journal_entries on journal_entries;
create trigger trg_no_delete_journal_entries
  before delete on journal_entries
  for each row execute function fn_prevent_journal_delete();

drop trigger if exists trg_no_delete_journal_lines on journal_lines;
create trigger trg_no_delete_journal_lines
  before delete on journal_lines
  for each row execute function fn_prevent_journal_delete();

-- -------------------------------------------------------------------------
-- 7. PAYMENTS
-- -------------------------------------------------------------------------
create table if not exists payments (
  id                uuid primary key default gen_random_uuid(),
  organisation_id   uuid not null references organisations(id) on delete cascade,
  member_id         uuid not null references members(id),
  transaction_date  date not null default current_date,
  amount            numeric(14,2) not null check (amount > 0),
  channel           payment_channel not null,
  reference         text,
  description       text,
  status            text not null default 'unallocated'
                       check (status in ('unallocated','allocated','posted','reversed')),
  journal_entry_id  uuid references journal_entries(id),
  created_at        timestamptz not null default now(),
  created_by        uuid references auth.users(id)
);

create index if not exists idx_payments_org on payments(organisation_id);
create index if not exists idx_payments_member on payments(member_id);
create index if not exists idx_payments_ref on payments(organisation_id, reference);

-- -------------------------------------------------------------------------
-- 8. BANK / M-PESA STATEMENT IMPORT + MATCHING
-- -------------------------------------------------------------------------
create table if not exists bank_accounts (
  id                uuid primary key default gen_random_uuid(),
  organisation_id   uuid not null references organisations(id) on delete cascade,
  account_name      text not null,
  account_number    text,
  bank_name         text,
  chart_account_id  uuid references chart_of_accounts(id)
);

create table if not exists mpesa_accounts (
  id                uuid primary key default gen_random_uuid(),
  organisation_id   uuid not null references organisations(id) on delete cascade,
  account_name      text not null,
  till_or_paybill   text,
  chart_account_id  uuid references chart_of_accounts(id)
);

create table if not exists bank_transactions (
  id                uuid primary key default gen_random_uuid(),
  organisation_id   uuid not null references organisations(id) on delete cascade,
  bank_account_id   uuid not null references bank_accounts(id),
  txn_date          date not null,
  reference         text,
  description       text,
  amount            numeric(14,2) not null,
  txn_type          text check (txn_type in ('credit','debit')),
  match_status      match_status not null default 'unmatched',
  matched_payment_id uuid references payments(id),
  match_score       numeric(5,2),
  imported_at       timestamptz not null default now(),
  imported_by       uuid references auth.users(id)
);

create table if not exists mpesa_transactions (
  id                uuid primary key default gen_random_uuid(),
  organisation_id   uuid not null references organisations(id) on delete cascade,
  mpesa_account_id  uuid not null references mpesa_accounts(id),
  txn_date          date not null,
  reference         text,          -- M-Pesa transaction code
  phone             text,
  payer_name        text,
  amount            numeric(14,2) not null,
  match_status      match_status not null default 'unmatched',
  matched_payment_id uuid references payments(id),
  match_score       numeric(5,2),
  imported_at       timestamptz not null default now(),
  imported_by       uuid references auth.users(id)
);

create index if not exists idx_bank_txn_org on bank_transactions(organisation_id, match_status);
create index if not exists idx_mpesa_txn_org on mpesa_transactions(organisation_id, match_status);

create table if not exists reconciliations (
  id                uuid primary key default gen_random_uuid(),
  organisation_id   uuid not null references organisations(id) on delete cascade,
  reconciliation_date date not null default current_date,
  bank_account_id   uuid references bank_accounts(id),
  mpesa_account_id  uuid references mpesa_accounts(id),
  statement_balance numeric(14,2) not null,
  ledger_balance    numeric(14,2) not null,
  difference        numeric(14,2) generated always as (statement_balance - ledger_balance) stored,
  notes             text,
  created_at        timestamptz not null default now(),
  created_by        uuid references auth.users(id)
);

-- -------------------------------------------------------------------------
-- 9. DOCUMENTS
-- -------------------------------------------------------------------------
create table if not exists documents (
  id                uuid primary key default gen_random_uuid(),
  organisation_id   uuid not null references organisations(id) on delete cascade,
  entity_type       text not null,   -- 'member' | 'payment' | 'bank_transaction' | etc.
  entity_id         uuid not null,
  storage_path      text not null,   -- path within a private Supabase Storage bucket
  file_name         text,
  uploaded_at       timestamptz not null default now(),
  uploaded_by       uuid references auth.users(id)
);

create index if not exists idx_documents_entity on documents(organisation_id, entity_type, entity_id);

-- -------------------------------------------------------------------------
-- 10. AUDIT LOG
-- -------------------------------------------------------------------------
create table if not exists audit_logs (
  id                uuid primary key default gen_random_uuid(),
  organisation_id   uuid,
  user_id           uuid references auth.users(id),
  action            text not null,          -- 'insert' | 'update' | 'delete'
  table_name        text not null,
  record_id         uuid,
  old_values        jsonb,
  new_values        jsonb,
  created_at        timestamptz not null default now()
);

create index if not exists idx_audit_org on audit_logs(organisation_id, created_at desc);

create or replace function fn_audit_trigger()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_org uuid;
begin
  begin
    v_org := coalesce(new.organisation_id, old.organisation_id);
  exception when undefined_column then
    v_org := null;
  end;

  insert into audit_logs(organisation_id, user_id, action, table_name, record_id, old_values, new_values)
  values (
    v_org,
    auth.uid(),
    lower(tg_op),
    tg_table_name,
    coalesce((new).id, (old).id),
    case when tg_op in ('update','delete') then to_jsonb(old) else null end,
    case when tg_op in ('insert','update') then to_jsonb(new) else null end
  );
  return coalesce(new, old);
end;
$$;

-- Attach the audit trigger to every financially-significant table.
do $$
declare t text;
begin
  foreach t in array array[
    'members','contributions','payments','journal_entries','journal_lines',
    'bank_transactions','mpesa_transactions','reconciliations','organisation_users'
  ]
  loop
    execute format('drop trigger if exists trg_audit_%1$s on %1$s;', t);
    execute format(
      'create trigger trg_audit_%1$s after insert or update or delete on %1$s
       for each row execute function fn_audit_trigger();', t);
  end loop;
end $$;

-- -------------------------------------------------------------------------
-- 11. CORE POSTING FUNCTIONS (only place allowed to write journal_lines
--     for these event types — frontend never inserts into journal_* directly)
-- -------------------------------------------------------------------------

-- Records a payment, allocates it to outstanding contributions oldest-first
-- (or per org setting), and posts the balanced journal entry.
create or replace function fn_record_and_post_payment(
  p_organisation_id uuid,
  p_member_id       uuid,
  p_amount          numeric,
  p_channel         payment_channel,
  p_reference       text,
  p_description     text,
  p_cash_account_id uuid,       -- chart_of_accounts row for Bank/M-Pesa/Cash
  p_contribution_income_account_id uuid
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_payment_id uuid;
  v_entry_id   uuid;
  v_remaining  numeric(14,2) := p_amount;
  v_contrib    record;
  v_apply      numeric(14,2);
begin
  if not is_org_member(p_organisation_id) then
    raise exception 'Not authorised for this organisation';
  end if;

  insert into payments(organisation_id, member_id, amount, channel, reference, description, created_by)
  values (p_organisation_id, p_member_id, p_amount, p_channel, p_reference, p_description, auth.uid())
  returning id into v_payment_id;

  -- Allocate oldest-first across unpaid/partial contributions
  for v_contrib in
    select c.id, c.amount_expected, c.amount_paid
    from contributions c
    join contribution_periods cp on cp.id = c.period_id
    where c.member_id = p_member_id
      and c.status in ('unpaid','partial')
    order by cp.period_start asc
  loop
    exit when v_remaining <= 0;
    v_apply := least(v_remaining, v_contrib.amount_expected - v_contrib.amount_paid);
    update contributions
      set amount_paid = amount_paid + v_apply,
          status = case
                      when amount_paid + v_apply >= amount_expected then 'paid'
                      else 'partial'
                   end
      where id = v_contrib.id;
    v_remaining := v_remaining - v_apply;
  end loop;

  update payments set status = 'allocated' where id = v_payment_id;

  -- Post the journal entry: Dr Cash/Bank/M-Pesa, Cr Contribution Income
  insert into journal_entries(organisation_id, description, source_type, source_id, created_by)
  values (p_organisation_id, 'Payment received - ' || coalesce(p_reference,''), 'payment', v_payment_id, auth.uid())
  returning id into v_entry_id;

  insert into journal_lines(journal_entry_id, account_id, debit, credit, member_id)
  values (v_entry_id, p_cash_account_id, p_amount, 0, p_member_id);

  insert into journal_lines(journal_entry_id, account_id, debit, credit, member_id)
  values (v_entry_id, p_contribution_income_account_id, 0, p_amount, p_member_id);

  update payments set status = 'posted', journal_entry_id = v_entry_id where id = v_payment_id;

  return v_payment_id;
end;
$$;

-- Reverses a posted journal entry with a mirrored correcting entry
-- (never deletes the original).
create or replace function fn_reverse_journal_entry(p_entry_id uuid, p_reason text)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_org uuid;
  v_new_entry uuid;
  v_line record;
begin
  select organisation_id into v_org from journal_entries where id = p_entry_id;
  if not is_org_member(v_org) then
    raise exception 'Not authorised for this organisation';
  end if;

  insert into journal_entries(organisation_id, description, source_type, source_id, created_by)
  values (v_org, 'Reversal: ' || coalesce(p_reason,''), 'reversal', p_entry_id, auth.uid())
  returning id into v_new_entry;

  for v_line in select * from journal_lines where journal_entry_id = p_entry_id loop
    insert into journal_lines(journal_entry_id, account_id, debit, credit, member_id)
    values (v_new_entry, v_line.account_id, v_line.credit, v_line.debit, v_line.member_id); -- swapped
  end loop;

  update journal_entries set status = 'reversed', reversed_entry_id = v_new_entry where id = p_entry_id;

  return v_new_entry;
end;
$$;

-- -------------------------------------------------------------------------
-- 12. MEMBER STATEMENT VIEW (derived from the ledger — not a stored balance)
-- -------------------------------------------------------------------------
create or replace view v_member_ledger as
select
  jl.member_id,
  je.organisation_id,
  je.entry_date,
  je.description,
  coa.name as account_name,
  jl.debit,
  jl.credit,
  je.id as journal_entry_id
from journal_lines jl
join journal_entries je on je.id = jl.journal_entry_id
join chart_of_accounts coa on coa.id = jl.account_id
where jl.member_id is not null
  and je.status = 'posted';

-- -------------------------------------------------------------------------
-- 13. ROW LEVEL SECURITY
-- -------------------------------------------------------------------------
alter table organisations           enable row level security;
alter table organisation_settings   enable row level security;
alter table organisation_users      enable row level security;
alter table members                 enable row level security;
alter table contribution_rules      enable row level security;
alter table contribution_periods    enable row level security;
alter table contributions           enable row level security;
alter table payments                enable row level security;
alter table bank_accounts           enable row level security;
alter table mpesa_accounts          enable row level security;
alter table bank_transactions       enable row level security;
alter table mpesa_transactions      enable row level security;
alter table reconciliations         enable row level security;
alter table chart_of_accounts       enable row level security;
alter table accounting_periods      enable row level security;
alter table journal_entries         enable row level security;
alter table journal_lines           enable row level security;
alter table documents               enable row level security;
alter table audit_logs              enable row level security;

-- Generic pattern: members of an org can SELECT; only org_admin/treasurer/
-- accountant can INSERT/UPDATE (per table, refined below); nobody can
-- DELETE financial rows via the API (only the reversal functions, which
-- run as security definer and bypass RLS deliberately).

create policy p_org_select on organisations for select
  using (is_org_member(id));

create policy p_org_settings_select on organisation_settings for select
  using (is_org_member(organisation_id));
create policy p_org_settings_update on organisation_settings for update
  using (has_org_role(organisation_id, array['org_admin']::org_role[]));

create policy p_org_users_select on organisation_users for select
  using (is_org_member(organisation_id));
create policy p_org_users_write on organisation_users for insert
  with check (has_org_role(organisation_id, array['org_admin']::org_role[]));
create policy p_org_users_update on organisation_users for update
  using (has_org_role(organisation_id, array['org_admin']::org_role[]));

create policy p_members_select on members for select
  using (is_org_member(organisation_id));
create policy p_members_write on members for insert
  with check (has_org_role(organisation_id, array['org_admin','secretary']::org_role[]));
create policy p_members_update on members for update
  using (has_org_role(organisation_id, array['org_admin','secretary']::org_role[]));

create policy p_contrib_rules_select on contribution_rules for select
  using (is_org_member(organisation_id));
create policy p_contrib_rules_write on contribution_rules for insert
  with check (has_org_role(organisation_id, array['org_admin']::org_role[]));

create policy p_contrib_periods_select on contribution_periods for select
  using (is_org_member(organisation_id));

create policy p_contributions_select on contributions for select
  using (is_org_member(organisation_id));
create policy p_contributions_update on contributions for update
  using (has_org_role(organisation_id, array['org_admin','treasurer','accountant']::org_role[]));

create policy p_payments_select on payments for select
  using (is_org_member(organisation_id));
create policy p_payments_write on payments for insert
  with check (has_org_role(organisation_id, array['org_admin','treasurer']::org_role[]));

create policy p_bank_accounts_select on bank_accounts for select
  using (is_org_member(organisation_id));
create policy p_mpesa_accounts_select on mpesa_accounts for select
  using (is_org_member(organisation_id));

create policy p_bank_txn_select on bank_transactions for select
  using (is_org_member(organisation_id));
create policy p_bank_txn_write on bank_transactions for insert
  with check (has_org_role(organisation_id, array['org_admin','treasurer','accountant']::org_role[]));
create policy p_bank_txn_update on bank_transactions for update
  using (has_org_role(organisation_id, array['org_admin','treasurer','accountant']::org_role[]));

create policy p_mpesa_txn_select on mpesa_transactions for select
  using (is_org_member(organisation_id));
create policy p_mpesa_txn_write on mpesa_transactions for insert
  with check (has_org_role(organisation_id, array['org_admin','treasurer','accountant']::org_role[]));
create policy p_mpesa_txn_update on mpesa_transactions for update
  using (has_org_role(organisation_id, array['org_admin','treasurer','accountant']::org_role[]));

create policy p_reconciliations_select on reconciliations for select
  using (is_org_member(organisation_id));
create policy p_reconciliations_write on reconciliations for insert
  with check (has_org_role(organisation_id, array['org_admin','accountant']::org_role[]));

create policy p_coa_select on chart_of_accounts for select
  using (is_org_member(organisation_id));
create policy p_coa_write on chart_of_accounts for insert
  with check (has_org_role(organisation_id, array['org_admin','accountant']::org_role[]));

create policy p_periods_select on accounting_periods for select
  using (is_org_member(organisation_id));

create policy p_journal_entries_select on journal_entries for select
  using (is_org_member(organisation_id));
-- No direct insert policy for journal_entries/journal_lines: they are only
-- ever written by the SECURITY DEFINER posting functions above, which run
-- with elevated privilege and bypass RLS for the insert itself while still
-- checking is_org_member() in application logic.

create policy p_journal_lines_select on journal_lines for select
  using (exists (
    select 1 from journal_entries je
    where je.id = journal_lines.journal_entry_id
      and is_org_member(je.organisation_id)
  ));

create policy p_documents_select on documents for select
  using (is_org_member(organisation_id));
create policy p_documents_write on documents for insert
  with check (is_org_member(organisation_id));

create policy p_audit_select on audit_logs for select
  using (organisation_id is not null and has_org_role(organisation_id, array['org_admin','accountant']::org_role[]));

-- Revoke DELETE entirely on financial tables for all client roles;
-- only reversal functions (security definer) may logically "undo" a posting.
revoke delete on journal_entries, journal_lines, payments, contributions, members from authenticated;

-- =========================================================================
-- END OF PHASE 1 MIGRATION
-- =========================================================================

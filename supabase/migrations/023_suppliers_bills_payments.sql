-- =========================================================================
-- MIGRATION 023: Suppliers, Bills (accounts payable) and Bill Payments.
--
-- Accounting treatment:
--   Bill raised:     Dr Expense (or Asset)      Cr Accounts Payable
--   Bill paid:       Dr Accounts Payable        Cr Bank/Cash/M-Pesa
--
-- This keeps expenditure on an accruals basis and gives you a real
-- creditors ledger, rather than only recognising expenses when cash moves.
--
-- Run after 001-022. Safe to re-run.
-- =========================================================================

do $$ begin
  create type bill_status as enum ('draft','approved','partially_paid','paid','void');
exception when duplicate_object then null; end $$;

-- -------------------------------------------------------------------------
-- A. SUPPLIERS
-- -------------------------------------------------------------------------
create table if not exists suppliers (
  id               uuid primary key default gen_random_uuid(),
  organisation_id  uuid not null references organisations(id) on delete cascade,
  supplier_code    text,
  name             text not null,
  contact_person   text,
  phone            text,
  email            text,
  address          text,
  kra_pin          text,
  payment_terms_days int not null default 30,
  bank_name        text,
  bank_account     text,
  mpesa_number     text,
  notes            text,
  is_active        boolean not null default true,
  created_by       uuid references auth.users(id),
  created_at       timestamptz not null default now(),
  unique (organisation_id, name)
);

create index if not exists idx_suppliers_org on suppliers(organisation_id, is_active);

alter table suppliers enable row level security;
drop policy if exists p_suppliers_select on suppliers;
create policy p_suppliers_select on suppliers for select using (is_org_member(organisation_id));
drop policy if exists p_suppliers_insert on suppliers;
create policy p_suppliers_insert on suppliers for insert
  with check (has_org_role(organisation_id, array['org_admin','accountant','treasurer']::org_role[]));
drop policy if exists p_suppliers_update on suppliers;
create policy p_suppliers_update on suppliers for update
  using (has_org_role(organisation_id, array['org_admin','accountant']::org_role[]));

drop trigger if exists trg_audit_suppliers on suppliers;
create trigger trg_audit_suppliers after insert or update or delete on suppliers
  for each row execute function fn_audit_trigger();

-- -------------------------------------------------------------------------
-- B. BILLS (supplier invoices)
-- -------------------------------------------------------------------------
create table if not exists bills (
  id                uuid primary key default gen_random_uuid(),
  organisation_id   uuid not null references organisations(id) on delete cascade,
  supplier_id       uuid not null references suppliers(id),
  bill_number       text not null,            -- our internal number, e.g. BILL-2026-000001
  supplier_invoice_no text,                   -- the supplier's own invoice number
  bill_date         date not null default current_date,
  due_date          date not null,
  description       text,
  total_amount      numeric(14,2) not null check (total_amount > 0),
  amount_paid       numeric(14,2) not null default 0 check (amount_paid >= 0),
  status            bill_status not null default 'draft',
  journal_entry_id  uuid references journal_entries(id),
  approved_by       uuid references auth.users(id),
  approved_at       timestamptz,
  created_by        uuid references auth.users(id),
  created_at        timestamptz not null default now(),
  unique (organisation_id, bill_number)
);

create index if not exists idx_bills_org on bills(organisation_id, status);
create index if not exists idx_bills_supplier on bills(supplier_id);
create index if not exists idx_bills_due on bills(organisation_id, due_date) where status in ('approved','partially_paid');

alter table bills enable row level security;
drop policy if exists p_bills_select on bills;
create policy p_bills_select on bills for select using (is_org_member(organisation_id));
-- Bills are created/approved through RPCs so the accounting posts correctly.

drop trigger if exists trg_audit_bills on bills;
create trigger trg_audit_bills after insert or update or delete on bills
  for each row execute function fn_audit_trigger();

-- -------------------------------------------------------------------------
-- C. BILL LINES (each line hits a different expense/asset account)
-- -------------------------------------------------------------------------
create table if not exists bill_lines (
  id           uuid primary key default gen_random_uuid(),
  bill_id      uuid not null references bills(id) on delete cascade,
  organisation_id uuid not null references organisations(id) on delete cascade,
  account_id   uuid not null references chart_of_accounts(id),
  description  text,
  amount       numeric(14,2) not null check (amount > 0)
);

create index if not exists idx_bill_lines on bill_lines(bill_id);

alter table bill_lines enable row level security;
drop policy if exists p_bill_lines_select on bill_lines;
create policy p_bill_lines_select on bill_lines for select using (is_org_member(organisation_id));

-- -------------------------------------------------------------------------
-- D. BILL PAYMENTS
-- -------------------------------------------------------------------------
create table if not exists bill_payments (
  id               uuid primary key default gen_random_uuid(),
  bill_id          uuid not null references bills(id) on delete cascade,
  organisation_id  uuid not null references organisations(id) on delete cascade,
  payment_date     date not null default current_date,
  amount           numeric(14,2) not null check (amount > 0),
  payment_account_id uuid not null references chart_of_accounts(id),
  channel          payment_channel not null,
  reference        text,
  journal_entry_id uuid references journal_entries(id),
  created_by       uuid references auth.users(id),
  created_at       timestamptz not null default now()
);

create index if not exists idx_bill_payments on bill_payments(bill_id);

alter table bill_payments enable row level security;
drop policy if exists p_bill_payments_select on bill_payments;
create policy p_bill_payments_select on bill_payments for select using (is_org_member(organisation_id));

drop trigger if exists trg_audit_bill_payments on bill_payments;
create trigger trg_audit_bill_payments after insert or update or delete on bill_payments
  for each row execute function fn_audit_trigger();

-- -------------------------------------------------------------------------
-- E. Ensure an Accounts Payable account exists
-- -------------------------------------------------------------------------
do $$
declare
  v_org      uuid := '1f452f1c-b441-47c1-ac85-d22087519b5e';
  v_curr_liab uuid;
begin
  select id into v_curr_liab from chart_of_accounts
    where organisation_id = v_org and code = '2050';

  insert into chart_of_accounts(organisation_id, code, name, account_type,
      subtype, normal_balance, parent_account_id, is_active, description)
    values(v_org,'2030','Accounts Payable','liability','current_liability','credit',
      v_curr_liab, true,'Amounts owed to suppliers for bills received but not yet paid.')
    on conflict(organisation_id, code) do nothing;

  -- A couple of common expense accounts if they don't exist yet
  insert into chart_of_accounts(organisation_id, code, name, account_type, subtype, normal_balance, is_active)
    values
      (v_org,'5200','Office and Administration','expense','operating','debit',true),
      (v_org,'5300','Professional Fees','expense','operating','debit',true),
      (v_org,'5400','Rent and Utilities','expense','operating','debit',true)
    on conflict(organisation_id, code) do nothing;
end $$;

-- -------------------------------------------------------------------------
-- F. Bill numbering
-- -------------------------------------------------------------------------
create or replace function fn_next_bill_number(p_organisation_id uuid)
returns text language plpgsql security definer set search_path = public as $$
declare v_year text := to_char(current_date,'YYYY'); v_seq int;
begin
  select coalesce(max((regexp_replace(bill_number,'^BILL-\d{4}-',''))::int),0)+1
    into v_seq from bills
    where organisation_id = p_organisation_id and bill_number like 'BILL-'||v_year||'-%';
  return 'BILL-'||v_year||'-'||lpad(v_seq::text,6,'0');
end;
$$;

-- -------------------------------------------------------------------------
-- G. CREATE A BILL (with lines) — posts Dr Expense / Cr Accounts Payable
-- p_lines: [{"account_id":"...","description":"...","amount":1000}, ...]
-- -------------------------------------------------------------------------
create or replace function fn_create_bill(
  p_organisation_id uuid,
  p_supplier_id     uuid,
  p_bill_date       date,
  p_due_date        date,
  p_supplier_invoice_no text,
  p_description     text,
  p_lines           jsonb
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_bill_id  uuid;
  v_number   text;
  v_total    numeric(14,2);
  v_line     jsonb;
  v_ap_acct  uuid;
  v_entry_id uuid;
  v_acct     uuid;
  v_amt      numeric(14,2);
  v_is_ctrl  boolean;
begin
  if not has_org_role(p_organisation_id, array['org_admin','accountant','treasurer']::org_role[]) then
    raise exception 'Not authorised to create bills';
  end if;

  select coalesce(sum((e->>'amount')::numeric),0) into v_total
    from jsonb_array_elements(p_lines) e;
  if v_total <= 0 then raise exception 'Bill total must be greater than zero'; end if;

  select id into v_ap_acct from chart_of_accounts
    where organisation_id = p_organisation_id and code = '2030' and is_active;
  if v_ap_acct is null then
    raise exception 'No Accounts Payable account (code 2030) found. Run migration 023 first.';
  end if;

  v_number := fn_next_bill_number(p_organisation_id);

  insert into bills(organisation_id, supplier_id, bill_number, supplier_invoice_no,
    bill_date, due_date, description, total_amount, status, created_by)
  values (p_organisation_id, p_supplier_id, v_number, p_supplier_invoice_no,
    p_bill_date, p_due_date, p_description, v_total, 'draft', auth.uid())
  returning id into v_bill_id;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_acct := (v_line->>'account_id')::uuid;
    v_amt  := (v_line->>'amount')::numeric;

    select is_control into v_is_ctrl from chart_of_accounts where id = v_acct;
    if coalesce(v_is_ctrl,false) then
      raise exception 'Cannot post a bill line to a control account. Choose a postable sub-account.';
    end if;

    insert into bill_lines(bill_id, organisation_id, account_id, description, amount)
    values (v_bill_id, p_organisation_id, v_acct, v_line->>'description', v_amt);
  end loop;

  return jsonb_build_object('id', v_bill_id, 'bill_number', v_number, 'total', v_total);
end;
$$;

-- -------------------------------------------------------------------------
-- H. APPROVE A BILL — posts the accrual entry
-- -------------------------------------------------------------------------
create or replace function fn_approve_bill(p_bill_id uuid)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_bill    record;
  v_ap_acct uuid;
  v_entry   uuid;
  v_line    record;
  v_jnum    text;
begin
  select * into v_bill from bills where id = p_bill_id;
  if v_bill is null then raise exception 'Bill not found'; end if;
  if not has_org_role(v_bill.organisation_id, array['org_admin','accountant']::org_role[]) then
    raise exception 'Not authorised to approve bills';
  end if;
  if v_bill.status <> 'draft' then
    raise exception 'Only a draft bill can be approved (current status: %)', v_bill.status;
  end if;

  select id into v_ap_acct from chart_of_accounts
    where organisation_id = v_bill.organisation_id and code = '2030';

  v_jnum := fn_next_journal_number(v_bill.organisation_id);

  insert into journal_entries(organisation_id, entry_date, description,
    source_type, source_id, status, journal_number, created_by)
  values (v_bill.organisation_id, v_bill.bill_date,
    'Bill ' || v_bill.bill_number, 'bill', p_bill_id, 'posted', v_jnum, auth.uid())
  returning id into v_entry;

  -- Dr each expense/asset line
  for v_line in select * from bill_lines where bill_id = p_bill_id loop
    insert into journal_lines(journal_entry_id, account_id, debit, credit)
    values (v_entry, v_line.account_id, v_line.amount, 0);
  end loop;

  -- Cr Accounts Payable for the total
  insert into journal_lines(journal_entry_id, account_id, debit, credit)
  values (v_entry, v_ap_acct, 0, v_bill.total_amount);

  update bills set status = 'approved', approved_by = auth.uid(),
    approved_at = now(), journal_entry_id = v_entry
  where id = p_bill_id;

  return v_entry;
end;
$$;

-- -------------------------------------------------------------------------
-- I. PAY A BILL — Dr Accounts Payable / Cr Bank or Cash
-- -------------------------------------------------------------------------
create or replace function fn_pay_bill(
  p_bill_id            uuid,
  p_amount             numeric,
  p_payment_account_id uuid,
  p_channel            payment_channel,
  p_reference          text,
  p_payment_date       date default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_bill     record;
  v_ap_acct  uuid;
  v_entry    uuid;
  v_jnum     text;
  v_pay_id   uuid;
  v_new_paid numeric(14,2);
  v_is_pay   boolean;
begin
  select * into v_bill from bills where id = p_bill_id;
  if v_bill is null then raise exception 'Bill not found'; end if;
  if not has_org_role(v_bill.organisation_id, array['org_admin','accountant','treasurer']::org_role[]) then
    raise exception 'Not authorised to pay bills';
  end if;
  if v_bill.status not in ('approved','partially_paid') then
    raise exception 'Only an approved bill can be paid (current status: %)', v_bill.status;
  end if;
  if p_amount <= 0 then raise exception 'Payment amount must be greater than zero'; end if;
  if p_amount > (v_bill.total_amount - v_bill.amount_paid) then
    raise exception 'Payment of % exceeds the outstanding balance of %',
      p_amount, v_bill.total_amount - v_bill.amount_paid;
  end if;

  -- Must pay from a real payment account, never a control account
  select is_payment_account into v_is_pay from chart_of_accounts where id = p_payment_account_id;
  if not coalesce(v_is_pay, false) then
    raise exception 'Bills must be paid from a bank, cash or M-Pesa account.';
  end if;

  select id into v_ap_acct from chart_of_accounts
    where organisation_id = v_bill.organisation_id and code = '2030';

  v_jnum := fn_next_journal_number(v_bill.organisation_id);

  insert into journal_entries(organisation_id, entry_date, description,
    source_type, source_id, status, journal_number, created_by)
  values (v_bill.organisation_id, coalesce(p_payment_date, current_date),
    'Payment for bill ' || v_bill.bill_number, 'bill_payment', p_bill_id,
    'posted', v_jnum, auth.uid())
  returning id into v_entry;

  insert into journal_lines(journal_entry_id, account_id, debit, credit)
  values (v_entry, v_ap_acct, p_amount, 0);
  insert into journal_lines(journal_entry_id, account_id, debit, credit)
  values (v_entry, p_payment_account_id, 0, p_amount);

  insert into bill_payments(bill_id, organisation_id, payment_date, amount,
    payment_account_id, channel, reference, journal_entry_id, created_by)
  values (p_bill_id, v_bill.organisation_id, coalesce(p_payment_date, current_date),
    p_amount, p_payment_account_id, p_channel, p_reference, v_entry, auth.uid())
  returning id into v_pay_id;

  v_new_paid := v_bill.amount_paid + p_amount;
  update bills
     set amount_paid = v_new_paid,
         status = case when v_new_paid >= total_amount then 'paid'::bill_status
                       else 'partially_paid'::bill_status end
   where id = p_bill_id;

  return v_pay_id;
end;
$$;

-- -------------------------------------------------------------------------
-- J. SUPPLIER / CREDITORS AGEING
-- -------------------------------------------------------------------------
create or replace function fn_creditors_ageing(p_organisation_id uuid)
returns table (
  supplier_name  text,
  bill_number    text,
  bill_date      date,
  due_date       date,
  total_amount   numeric,
  amount_paid    numeric,
  outstanding    numeric,
  days_overdue   int,
  status         text
)
language sql stable security definer set search_path = public as $$
  select
    s.name, b.bill_number, b.bill_date, b.due_date,
    b.total_amount, b.amount_paid,
    b.total_amount - b.amount_paid as outstanding,
    greatest(current_date - b.due_date, 0)::int as days_overdue,
    b.status::text
  from bills b
  join suppliers s on s.id = b.supplier_id
  where b.organisation_id = p_organisation_id
    and b.status in ('approved','partially_paid')
    and is_org_member(p_organisation_id)
  order by b.due_date;
$$;

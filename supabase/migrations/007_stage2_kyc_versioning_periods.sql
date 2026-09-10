-- =========================================================================
-- MIGRATION 007 (STAGE 2): Member KYC + Next of Kin, contribution rule
-- versioning, and accounting period-close enforcement.
-- Run after 001-006. Safe to re-run (idempotent).
-- =========================================================================

-- -------------------------------------------------------------------------
-- PART A: EXTEND MEMBERS (additive columns only — no data loss)
-- -------------------------------------------------------------------------
alter table members add column if not exists date_of_birth date;
alter table members add column if not exists gender text check (gender in ('male','female','other'));
alter table members add column if not exists physical_address text;
alter table members add column if not exists occupation text;
alter table members add column if not exists employer text;
alter table members add column if not exists membership_category text;
alter table members add column if not exists preferred_payment_method payment_channel;
alter table members add column if not exists mpesa_number text;
alter table members add column if not exists bank_name text;
alter table members add column if not exists bank_account_number text;

-- -------------------------------------------------------------------------
-- PART B: KYC (one row per member)
-- -------------------------------------------------------------------------
create table if not exists member_kyc (
  member_id         uuid primary key references members(id) on delete cascade,
  organisation_id   uuid not null references organisations(id) on delete cascade,
  id_type           text check (id_type in ('national_id','passport','alien_id','other')),
  id_number         text,
  kyc_status        text not null default 'pending' check (kyc_status in ('pending','verified','rejected')),
  verification_date date,
  kyc_notes         text,
  updated_at        timestamptz not null default now()
);

alter table member_kyc enable row level security;
drop policy if exists p_member_kyc_select on member_kyc;
create policy p_member_kyc_select on member_kyc for select
  using (is_org_member(organisation_id));
drop policy if exists p_member_kyc_write on member_kyc;
create policy p_member_kyc_write on member_kyc for insert
  with check (has_org_role(organisation_id, array['org_admin','secretary','accountant']::org_role[]));
drop policy if exists p_member_kyc_update on member_kyc;
create policy p_member_kyc_update on member_kyc for update
  using (has_org_role(organisation_id, array['org_admin','secretary','accountant']::org_role[]));

-- -------------------------------------------------------------------------
-- PART C: NEXT OF KIN (a member can have several)
-- -------------------------------------------------------------------------
create table if not exists next_of_kin (
  id                uuid primary key default gen_random_uuid(),
  member_id         uuid not null references members(id) on delete cascade,
  organisation_id   uuid not null references organisations(id) on delete cascade,
  full_name         text not null,
  relationship      text,
  phone             text,
  created_at        timestamptz not null default now()
);

create index if not exists idx_nok_member on next_of_kin(member_id);

alter table next_of_kin enable row level security;
drop policy if exists p_nok_select on next_of_kin;
create policy p_nok_select on next_of_kin for select
  using (is_org_member(organisation_id));
drop policy if exists p_nok_write on next_of_kin;
create policy p_nok_write on next_of_kin for insert
  with check (has_org_role(organisation_id, array['org_admin','secretary']::org_role[]));
drop policy if exists p_nok_delete on next_of_kin;
create policy p_nok_delete on next_of_kin for delete
  using (has_org_role(organisation_id, array['org_admin','secretary']::org_role[]));

-- -------------------------------------------------------------------------
-- PART D: CONTRIBUTION RULE VERSIONING
-- Instead of a single amount on contribution_rules, each rule now has one
-- or more VERSIONS with an effective window. Period generation picks the
-- version whose window contains the period start, so changing a rule today
-- never rewrites historical expected amounts.
--
-- We keep contribution_rules.amount for backward compatibility with rows
-- created before this migration, but new logic reads from versions first.
-- -------------------------------------------------------------------------
create table if not exists contribution_rule_versions (
  id                uuid primary key default gen_random_uuid(),
  rule_id           uuid not null references contribution_rules(id) on delete cascade,
  organisation_id   uuid not null references organisations(id) on delete cascade,
  version_no        int not null,
  calc_method       text not null default 'fixed'
                       check (calc_method in ('fixed','percentage','category','salary')),
  -- For 'fixed': fixed_amount is used.
  -- For 'percentage': percentage_rate applied to a member's base (salary
  --   or a configured base) — Stage 2 supports fixed + category; percentage
  --   and salary are stored and validated but member salary/base capture is
  --   a later stage, so they fall back to fixed_amount if no base exists.
  fixed_amount      numeric(14,2) default 0,
  percentage_rate   numeric(7,4) default 0,
  category_amounts  jsonb,   -- e.g. {"A": 1000, "B": 2000}
  frequency         text not null default 'monthly'
                       check (frequency in ('weekly','monthly','quarterly','annual')),
  due_day           int not null default 5 check (due_day between 1 and 28),
  grace_days        int not null default 5 check (grace_days >= 0),
  effective_from    date not null,
  effective_to      date,        -- null = still in force
  status            text not null default 'active' check (status in ('active','superseded')),
  created_by        uuid references auth.users(id),
  created_at        timestamptz not null default now(),
  unique (rule_id, version_no)
);

create index if not exists idx_crv_rule on contribution_rule_versions(rule_id, effective_from);

alter table contribution_rule_versions enable row level security;
drop policy if exists p_crv_select on contribution_rule_versions;
create policy p_crv_select on contribution_rule_versions for select
  using (is_org_member(organisation_id));
-- Written only via fn_add_rule_version (security definer), so no client insert policy.

drop trigger if exists trg_audit_crv on contribution_rule_versions;
create trigger trg_audit_crv after insert or update or delete on contribution_rule_versions
  for each row execute function fn_audit_trigger();

-- Add a new version of a rule. Automatically closes the previous open
-- version's effective_to to the day before this one starts, and bumps
-- version_no. This is the ONLY way versions are created — guarantees no
-- overlapping active windows.
create or replace function fn_add_rule_version(
  p_rule_id        uuid,
  p_calc_method    text,
  p_fixed_amount   numeric,
  p_percentage_rate numeric,
  p_category_amounts jsonb,
  p_frequency      text,
  p_due_day        int,
  p_grace_days     int,
  p_effective_from date
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_org_id   uuid;
  v_next_no  int;
  v_new_id   uuid;
begin
  select organisation_id into v_org_id from contribution_rules where id = p_rule_id;
  if v_org_id is null then raise exception 'Rule not found'; end if;
  if not has_org_role(v_org_id, array['org_admin']::org_role[]) then
    raise exception 'Only an administrator can change contribution rules';
  end if;

  -- Basic formula validation (Section 11): reject nonsensical config.
  if p_calc_method = 'fixed' and coalesce(p_fixed_amount,0) <= 0 then
    raise exception 'Fixed method requires a positive amount';
  end if;
  if p_calc_method = 'percentage' and coalesce(p_percentage_rate,0) <= 0 then
    raise exception 'Percentage method requires a positive rate';
  end if;
  if p_calc_method = 'category' and (p_category_amounts is null or p_category_amounts = '{}'::jsonb) then
    raise exception 'Category method requires at least one category amount';
  end if;

  -- Close the current open version.
  update contribution_rule_versions
     set effective_to = (p_effective_from - interval '1 day')::date,
         status = 'superseded'
   where rule_id = p_rule_id and effective_to is null;

  select coalesce(max(version_no),0) + 1 into v_next_no
    from contribution_rule_versions where rule_id = p_rule_id;

  insert into contribution_rule_versions(
    rule_id, organisation_id, version_no, calc_method, fixed_amount,
    percentage_rate, category_amounts, frequency, due_day, grace_days,
    effective_from, created_by)
  values (
    p_rule_id, v_org_id, v_next_no, p_calc_method, coalesce(p_fixed_amount,0),
    coalesce(p_percentage_rate,0), p_category_amounts, p_frequency, p_due_day,
    coalesce(p_grace_days,0), p_effective_from, auth.uid())
  returning id into v_new_id;

  return v_new_id;
end;
$$;

-- Resolve the per-member expected amount for a rule version, honouring
-- calc_method and (for category) the member's membership_category.
create or replace function fn_expected_for_member(
  p_member_id uuid,
  p_version_id uuid
) returns numeric
language plpgsql stable security definer set search_path = public as $$
declare
  v_v    record;
  v_cat  text;
  v_amt  numeric(14,2);
begin
  select * into v_v from contribution_rule_versions where id = p_version_id;
  if not found then return 0; end if;

  if v_v.calc_method = 'category' then
    select membership_category into v_cat from members where id = p_member_id;
    v_amt := coalesce((v_v.category_amounts ->> v_cat)::numeric, 0);
    return v_amt;
  elsif v_v.calc_method = 'fixed' then
    return v_v.fixed_amount;
  else
    -- percentage / salary: no member base captured yet in Stage 2, so fall
    -- back to fixed_amount as a safe default rather than guessing.
    return v_v.fixed_amount;
  end if;
end;
$$;

-- -------------------------------------------------------------------------
-- PART E: VERSION-AWARE PERIOD GENERATION
-- Replaces the flat fn_generate_contribution_period. Picks the rule version
-- whose effective window contains the period start, and computes each
-- member's expected amount from that version.
-- -------------------------------------------------------------------------
create or replace function fn_generate_contribution_period(
  p_organisation_id uuid,
  p_rule_id         uuid,
  p_period_start    date,
  p_period_end      date,
  p_due_date        date
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_period_id uuid;
  v_version   record;
  v_member    record;
  v_expected  numeric(14,2);
begin
  if not has_org_role(p_organisation_id, array['org_admin','treasurer']::org_role[]) then
    raise exception 'Not authorised to generate contribution periods';
  end if;

  -- Find the rule version in force at the period start.
  select * into v_version from contribution_rule_versions
   where rule_id = p_rule_id
     and effective_from <= p_period_start
     and (effective_to is null or effective_to >= p_period_start)
   order by effective_from desc
   limit 1;

  if v_version is null then
    raise exception 'No contribution rule version is effective for %', p_period_start;
  end if;

  insert into contribution_periods(organisation_id, rule_id, period_start, period_end, due_date)
  values (p_organisation_id, p_rule_id, p_period_start, p_period_end, p_due_date)
  returning id into v_period_id;

  for v_member in
    select id, date_joined from members
    where organisation_id = p_organisation_id and status = 'active'
  loop
    -- Members who joined after this period ends are not yet obligated.
    if v_member.date_joined is not null and v_member.date_joined > p_period_end then
      continue;
    end if;

    v_expected := fn_expected_for_member(v_member.id, v_version.id);

    -- Skip members with a zero expectation (e.g. category not set) so the
    -- period isn't padded with meaningless zero rows.
    if v_expected > 0 then
      insert into contributions(organisation_id, member_id, period_id, amount_expected)
      values (p_organisation_id, v_member.id, v_period_id, v_expected);
    end if;
  end loop;

  return v_period_id;
end;
$$;

-- -------------------------------------------------------------------------
-- PART F: ACCOUNTING PERIOD-CLOSE ENFORCEMENT
-- Blocks any journal entry dated within a CLOSED accounting period.
-- Corrections to a closed period must go through a reversal dated in an
-- open period, exactly like the existing reversal flow.
-- -------------------------------------------------------------------------
create or replace function fn_block_closed_period()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_closed boolean;
begin
  select exists (
    select 1 from accounting_periods ap
    where ap.organisation_id = new.organisation_id
      and ap.status = 'closed'
      and new.entry_date between ap.period_start and ap.period_end
  ) into v_closed;

  if v_closed then
    raise exception 'Cannot post into a closed accounting period (entry date %). Use a reversal in an open period.', new.entry_date;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_block_closed_period on journal_entries;
create trigger trg_block_closed_period
  before insert on journal_entries
  for each row execute function fn_block_closed_period();

-- Close a period (org_admin/accountant only), recording who and when.
create or replace function fn_close_accounting_period(p_period_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_org uuid;
begin
  select organisation_id into v_org from accounting_periods where id = p_period_id;
  if v_org is null then raise exception 'Period not found'; end if;
  if not has_org_role(v_org, array['org_admin','accountant']::org_role[]) then
    raise exception 'Not authorised to close periods';
  end if;
  update accounting_periods
     set status = 'closed', closed_at = now(), closed_by = auth.uid()
   where id = p_period_id;
end;
$$;

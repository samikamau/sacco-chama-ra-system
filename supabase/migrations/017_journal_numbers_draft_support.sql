-- =========================================================================
-- MIGRATION 017: Human-readable journal numbers + draft journal support.
--
-- Two changes:
-- 1. Add journal_number column to journal_entries (JE-2026-000001 format,
--    unique per organisation).
-- 2. Fix the balance trigger so it only enforces balance on POSTED entries,
--    not on draft entries where lines are still being added.
--
-- Run after 001-016. Safe to re-run.
-- =========================================================================

-- -------------------------------------------------------------------------
-- A. Journal number column + sequence function
-- -------------------------------------------------------------------------
alter table journal_entries
  add column if not exists journal_number text,
  add column if not exists status_before_reverse journal_status;

-- Unique per organisation (not globally)
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'uq_journal_number_org'
  ) then
    alter table journal_entries
      add constraint uq_journal_number_org unique (organisation_id, journal_number);
  end if;
end $$;

-- Generate the next journal number for an org in the current year.
create or replace function fn_next_journal_number(p_organisation_id uuid)
returns text
language plpgsql security definer set search_path = public as $$
declare
  v_year text := to_char(current_date, 'YYYY');
  v_seq  int;
begin
  select coalesce(max(
    (regexp_replace(journal_number, '^JE-\d{4}-', ''))::int
  ), 0) + 1
  into v_seq
  from journal_entries
  where organisation_id = p_organisation_id
    and journal_number like 'JE-' || v_year || '-%';

  return 'JE-' || v_year || '-' || lpad(v_seq::text, 6, '0');
end;
$$;

-- Backfill journal numbers for existing entries that don't have one yet.
do $$
declare r record; v_num text;
begin
  for r in
    select id, organisation_id, created_at
    from journal_entries where journal_number is null
    order by organisation_id, created_at
  loop
    v_num := fn_next_journal_number(r.organisation_id);
    update journal_entries set journal_number = v_num where id = r.id;
  end loop;
end $$;

-- -------------------------------------------------------------------------
-- B. Fix balance trigger: only enforce on POSTED status, not DRAFT.
--    Draft journals may have incomplete lines while being built.
-- -------------------------------------------------------------------------
create or replace function fn_check_journal_balances(p_entry_id uuid)
returns void language plpgsql as $$
declare
  v_diff   numeric(14,2);
  v_status journal_status;
begin
  select status into v_status from journal_entries where id = p_entry_id;
  -- Only enforce balance on posted entries.
  if v_status <> 'posted' then return; end if;

  select coalesce(sum(debit),0) - coalesce(sum(credit),0)
    into v_diff
    from journal_lines where journal_entry_id = p_entry_id;
  if v_diff <> 0 then
    raise exception 'Journal entry % does not balance (difference %)', p_entry_id, v_diff;
  end if;
end;
$$;

-- -------------------------------------------------------------------------
-- C. General journal posting/reversal RPCs
-- -------------------------------------------------------------------------

-- Create a draft journal entry (returns the new id + number).
create or replace function fn_create_draft_journal(
  p_organisation_id uuid,
  p_entry_date      date,
  p_description     text,
  p_reference       text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_id  uuid;
  v_num text;
begin
  if not has_org_role(p_organisation_id, array['org_admin','treasurer','accountant']::org_role[]) then
    raise exception 'Not authorised to create journal entries';
  end if;
  v_num := fn_next_journal_number(p_organisation_id);
  insert into journal_entries(organisation_id, entry_date, description,
    source_type, status, journal_number, created_by)
  values (p_organisation_id, p_entry_date, p_description,
    'manual', 'posted', v_num, auth.uid())
  returning id into v_id;
  -- We default to 'posted' so that when lines are added, the balance
  -- trigger runs. Caller adds lines then calls fn_post_journal.
  -- For true draft support: insert with status='draft', add lines,
  -- then call fn_post_journal which validates balance and flips to 'posted'.
  update journal_entries set status = 'draft' where id = v_id;
  return jsonb_build_object('id', v_id, 'journal_number', v_num);
end;
$$;

-- Post a draft journal: validates balance, then marks posted.
create or replace function fn_post_journal(p_entry_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_org  uuid;
  v_diff numeric(14,2);
begin
  select organisation_id into v_org from journal_entries where id = p_entry_id;
  if not has_org_role(v_org, array['org_admin','accountant']::org_role[]) then
    raise exception 'Not authorised to post journal entries';
  end if;

  -- Enforce balance now.
  select coalesce(sum(debit),0) - coalesce(sum(credit),0)
    into v_diff from journal_lines where journal_entry_id = p_entry_id;
  if abs(v_diff) > 0.005 then
    raise exception 'Journal does not balance — total debits differ from credits by %', v_diff;
  end if;
  if not exists (select 1 from journal_lines where journal_entry_id = p_entry_id) then
    raise exception 'Journal has no lines — add at least one debit and one credit line';
  end if;

  update journal_entries set status = 'posted' where id = p_entry_id;
end;
$$;

-- Add a line to a DRAFT journal (blocks modification of posted journals).
create or replace function fn_add_journal_line(
  p_entry_id  uuid,
  p_account_id uuid,
  p_debit     numeric,
  p_credit    numeric,
  p_member_id uuid default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_org  uuid;
  v_stat journal_status;
  v_id   uuid;
begin
  select organisation_id, status into v_org, v_stat
    from journal_entries where id = p_entry_id;
  if v_stat = 'posted' then
    raise exception 'Cannot add lines to a posted journal. Use reversal/correction instead.';
  end if;
  if not has_org_role(v_org, array['org_admin','treasurer','accountant']::org_role[]) then
    raise exception 'Not authorised';
  end if;
  if coalesce(p_debit,0) > 0 and coalesce(p_credit,0) > 0 then
    raise exception 'A journal line cannot have both a debit and a credit value.';
  end if;
  if coalesce(p_debit,0) = 0 and coalesce(p_credit,0) = 0 then
    raise exception 'A journal line must have a non-zero debit or credit.';
  end if;
  insert into journal_lines(journal_entry_id, account_id, debit, credit, member_id)
  values (p_entry_id, p_account_id, coalesce(p_debit,0), coalesce(p_credit,0), p_member_id)
  returning id into v_id;
  return v_id;
end;
$$;

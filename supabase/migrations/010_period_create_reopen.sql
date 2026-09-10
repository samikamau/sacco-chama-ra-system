-- =========================================================================
-- MIGRATION 010: Accounting period creation + reopen, to support the
-- period-management UI. Close enforcement already exists (migration 007).
-- Run after 001-009. Safe to re-run.
-- =========================================================================

-- Create a period (org_admin/accountant only). Rejects overlaps.
create or replace function fn_create_accounting_period(
  p_organisation_id uuid,
  p_period_start    date,
  p_period_end      date
) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not has_org_role(p_organisation_id, array['org_admin','accountant']::org_role[]) then
    raise exception 'Not authorised to create periods';
  end if;
  if p_period_end < p_period_start then
    raise exception 'Period end cannot be before period start';
  end if;
  if exists (
    select 1 from accounting_periods
    where organisation_id = p_organisation_id
      and p_period_start <= period_end
      and p_period_end >= period_start
  ) then
    raise exception 'This period overlaps an existing accounting period';
  end if;

  insert into accounting_periods(organisation_id, period_start, period_end, status)
  values (p_organisation_id, p_period_start, p_period_end, 'open')
  returning id into v_id;
  return v_id;
end;
$$;

-- Reopen a closed period (org_admin only — deliberately stricter than
-- closing, since reopening a closed book is a significant control action).
create or replace function fn_reopen_accounting_period(p_period_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_org uuid;
begin
  select organisation_id into v_org from accounting_periods where id = p_period_id;
  if v_org is null then raise exception 'Period not found'; end if;
  if not has_org_role(v_org, array['org_admin']::org_role[]) then
    raise exception 'Only an administrator can reopen a closed period';
  end if;
  update accounting_periods
     set status = 'open', closed_at = null, closed_by = null
   where id = p_period_id;
end;
$$;

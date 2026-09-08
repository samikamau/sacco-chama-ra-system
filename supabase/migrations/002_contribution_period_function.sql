-- =========================================================================
-- ADDENDUM TO phase1_schema.sql
-- Run this after phase1_schema.sql. It adds the one function the frontend
-- needs to generate a contribution period, following the same pattern as
-- journal postings: contribution_periods and contributions have no direct
-- INSERT policy for client roles — this function (security definer) is the
-- only way rows get created, so every period is generated consistently
-- against the active contribution_rules and active members at the time.
-- =========================================================================

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
  v_rule record;
  v_member record;
begin
  if not has_org_role(p_organisation_id, array['org_admin','treasurer']::org_role[]) then
    raise exception 'Not authorised to generate contribution periods for this organisation';
  end if;

  select * into v_rule from contribution_rules
    where id = p_rule_id and organisation_id = p_organisation_id and active = true;
  if not found then
    raise exception 'Contribution rule not found or inactive';
  end if;

  insert into contribution_periods(organisation_id, rule_id, period_start, period_end, due_date)
  values (p_organisation_id, p_rule_id, p_period_start, p_period_end, p_due_date)
  returning id into v_period_id;

  for v_member in
    select id, monthly_contribution from members
    where organisation_id = p_organisation_id and status = 'active'
  loop
    insert into contributions(organisation_id, member_id, period_id, amount_expected)
    values (
      p_organisation_id,
      v_member.id,
      v_period_id,
      coalesce(v_member.monthly_contribution, v_rule.amount)
    );
  end loop;

  return v_period_id;
end;
$$;

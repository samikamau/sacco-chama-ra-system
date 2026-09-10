-- =========================================================================
-- MIGRATION 009 (STAGE: DASHBOARD): Configurable collection target and a
-- database-backed KPI function so dashboard figures come from posted data,
-- never from manual entry.
-- Run after 001-008. Safe to re-run.
-- =========================================================================

-- Configurable collection target (Section 5 / 26).
alter table organisation_settings
  add column if not exists collection_target numeric(5,2) not null default 95.00;

-- Missed-periods threshold for insights (e.g. flag members who missed N in a row).
alter table organisation_settings
  add column if not exists missed_periods_threshold int not null default 3;

-- -------------------------------------------------------------------------
-- KPI FUNCTION: returns one JSON object with every headline dashboard
-- figure, all derived from posted transactions and contribution obligations.
-- Fund totals are grouped by contribution_type category so Shares, Deposits
-- and Welfare are always separate and always reconcile to payment_allocations.
-- -------------------------------------------------------------------------
create or replace function fn_dashboard_kpis(p_organisation_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_active_members   int;
  v_inactive_members int;
  v_total_members    int;
  v_expected         numeric(14,2);
  v_received         numeric(14,2);
  v_shares           numeric(14,2);
  v_deposits         numeric(14,2);
  v_welfare          numeric(14,2);
begin
  if not is_org_member(p_organisation_id) then
    raise exception 'Not authorised for this organisation';
  end if;

  select count(*) filter (where status = 'active'),
         count(*) filter (where status <> 'active'),
         count(*)
    into v_active_members, v_inactive_members, v_total_members
    from members where organisation_id = p_organisation_id;

  -- Expected vs paid across ALL contribution periods (obligations).
  select coalesce(sum(amount_expected),0), coalesce(sum(amount_paid),0)
    into v_expected, v_received
    from contributions where organisation_id = p_organisation_id;

  -- Fund totals from posted payment allocations, grouped by fund category.
  -- Only posted payments count (Section 16 / 26).
  select
    coalesce(sum(pa.amount) filter (where ct.category = 'share_capital'), 0),
    coalesce(sum(pa.amount) filter (where ct.category = 'share_deposit'), 0),
    coalesce(sum(pa.amount) filter (where ct.category = 'welfare'), 0)
    into v_shares, v_deposits, v_welfare
    from payment_allocations pa
    join payments p on p.id = pa.payment_id
    join contribution_types ct on ct.id = pa.contribution_type_id
    where p.organisation_id = p_organisation_id
      and p.status = 'posted';

  return jsonb_build_object(
    'active_members', v_active_members,
    'inactive_members', v_inactive_members,
    'total_members', v_total_members,
    'expected', v_expected,
    'received', v_received,
    'outstanding', v_expected - v_received,
    'collection_pct', case when v_expected > 0 then round((v_received / v_expected) * 100, 1) else 0 end,
    'total_shares', v_shares,
    'total_deposits', v_deposits,
    'total_welfare', v_welfare
  );
end;
$$;

-- -------------------------------------------------------------------------
-- INSIGHTS FUNCTION: returns a JSON array of { category, severity, message }
-- objects, every one backed by a real query. No fabricated observations.
-- -------------------------------------------------------------------------
create or replace function fn_dashboard_insights(p_organisation_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_target       numeric(5,2);
  v_expected     numeric(14,2);
  v_received     numeric(14,2);
  v_pct          numeric(6,2);
  v_outstanding_members int;
  v_pending_kyc  int;
  v_insights     jsonb := '[]'::jsonb;
begin
  if not is_org_member(p_organisation_id) then
    raise exception 'Not authorised for this organisation';
  end if;

  select collection_target into v_target from organisation_settings where organisation_id = p_organisation_id;
  v_target := coalesce(v_target, 95);

  select coalesce(sum(amount_expected),0), coalesce(sum(amount_paid),0)
    into v_expected, v_received
    from contributions where organisation_id = p_organisation_id;

  v_pct := case when v_expected > 0 then round((v_received / v_expected) * 100, 1) else 0 end;

  if v_expected > 0 then
    if v_pct >= v_target then
      v_insights := v_insights || jsonb_build_object(
        'category','Collection','severity','good',
        'message', format('Collection is at %s%%, meeting the %s%% target.', v_pct, v_target));
    else
      v_insights := v_insights || jsonb_build_object(
        'category','Collection','severity','warning',
        'message', format('Collection is at %s%%, below the %s%% target.', v_pct, v_target));
    end if;
  end if;

  select count(distinct member_id) into v_outstanding_members
    from contributions
    where organisation_id = p_organisation_id and amount_paid < amount_expected;
  if v_outstanding_members > 0 then
    v_insights := v_insights || jsonb_build_object(
      'category','Contributions','severity','warning',
      'message', format('%s member(s) have outstanding contributions.', v_outstanding_members));
  end if;

  select count(*) into v_pending_kyc
    from member_kyc
    where organisation_id = p_organisation_id and kyc_status = 'pending';
  if v_pending_kyc > 0 then
    v_insights := v_insights || jsonb_build_object(
      'category','Compliance','severity','info',
      'message', format('%s member(s) have KYC still pending verification.', v_pending_kyc));
  end if;

  return v_insights;
end;
$$;

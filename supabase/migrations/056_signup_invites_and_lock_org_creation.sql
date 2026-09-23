-- =========================================================================
-- MIGRATION 056
-- 1. Signup trigger: invited users JOIN the inviting organisation
--    instead of getting a new organisation of their own.
-- 2. Lock down fn_create_organisation so no user can create an
--    organisation from inside the app (signup is the only path).
-- Safe to run whether or not 055 was run.
-- =========================================================================

create or replace function fn_auto_create_org()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_org_id     uuid;
  v_org_name   text;
  v_org_type   text;
  v_full_name  text;
  v_inv        record;
  v_invited    boolean := false;
begin
  v_full_name := coalesce(nullif(trim(new.raw_user_meta_data->>'full_name'), ''), new.email);

  -- ---------------------------------------------------------------
  -- A. INVITED USER: join every pending, unexpired invitation
  -- ---------------------------------------------------------------
  for v_inv in
    select * from organisation_invitations
     where lower(email) = lower(new.email)
       and status = 'pending'
       and expires_at >= now()
  loop
    insert into organisation_users(organisation_id, user_id, role, status)
    values (v_inv.organisation_id, new.id, v_inv.role, 'active')
    on conflict (organisation_id, user_id)
      do update set role = excluded.role, status = 'active';

    update organisation_invitations
       set status = 'accepted', accepted_at = now(), accepted_by = new.id
     where id = v_inv.id;

    v_invited := true;
    v_org_id  := v_inv.organisation_id;
  end loop;

  if v_invited then
    select name, org_type::text into v_org_name, v_org_type
      from organisations where id = v_org_id;

    insert into user_profiles(id, full_name, company, telephone, receive_comms, org_type_pref)
    values (new.id, v_full_name, v_org_name,
            new.raw_user_meta_data->>'telephone',
            coalesce((new.raw_user_meta_data->>'receive_comms')::boolean, false),
            v_org_type)
    on conflict (id) do nothing;

    return new;
  end if;

  -- ---------------------------------------------------------------
  -- B. NEW CUSTOMER: create their organisation (same as 055)
  -- ---------------------------------------------------------------
  v_org_name := coalesce(nullif(trim(new.raw_user_meta_data->>'company'), ''),
                         v_full_name || '''s Organisation');
  v_org_type := coalesce(nullif(new.raw_user_meta_data->>'org_type', ''), 'sacco');

  insert into organisations(name, org_type, status)
  values (v_org_name, v_org_type::org_type, 'active')
  returning id into v_org_id;

  insert into organisation_users(organisation_id, user_id, role, status)
  values (v_org_id, new.id, 'org_admin', 'active');

  insert into organisation_sectors(organisation_id, sector, is_primary, activated_by)
  values (v_org_id, v_org_type, true, new.id)
  on conflict do nothing;

  insert into org_settings(organisation_id, org_type, show_loans, show_investments,
    show_assets, member_id_label, member_id_prefix, contribution_label, fund_label)
  values (v_org_id, v_org_type,
    v_org_type <> 'residents_association',
    v_org_type in ('chama','investment_group'),
    false,
    case v_org_type when 'residents_association' then 'Unit No.' else 'Member No.' end,
    case v_org_type
      when 'chama'                 then 'CH'
      when 'residents_association' then 'RA'
      when 'investment_group'      then 'IG'
      when 'welfare_group'         then 'WG'
      else 'SC' end,
    case v_org_type when 'residents_association' then 'Levies' else 'Contributions' end,
    case v_org_type
      when 'residents_association' then 'Project Funds'
      when 'chama'                 then 'Pool Funds'
      when 'investment_group'      then 'Investment Pool'
      else 'Member Funds' end)
  on conflict (organisation_id) do nothing;

  insert into user_profiles(id, full_name, company, telephone, receive_comms, org_type_pref)
  values (new.id, v_full_name, v_org_name,
          new.raw_user_meta_data->>'telephone',
          coalesce((new.raw_user_meta_data->>'receive_comms')::boolean, false),
          v_org_type)
  on conflict (id) do nothing;

  return new;
end;
$$;

drop trigger if exists trg_auto_create_org on auth.users;
create trigger trg_auto_create_org
  after insert on auth.users
  for each row execute function fn_auto_create_org();

-- ---------------------------------------------------------------
-- C. Block in-app organisation creation (all overloads)
-- ---------------------------------------------------------------
do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as sig
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'fn_create_organisation'
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', r.sig);
  end loop;
end $$;

-- ---------------------------------------------------------------
-- D. Checks
-- ---------------------------------------------------------------
select 'trigger' as item, count(*)::text as result
  from pg_trigger where tgname = 'trg_auto_create_org'
union all
select 'fn_create_organisation callable by users',
       coalesce(bool_or(has_function_privilege('authenticated', p.oid, 'execute'))::text, 'function not found')
  from pg_proc p where p.proname = 'fn_create_organisation';

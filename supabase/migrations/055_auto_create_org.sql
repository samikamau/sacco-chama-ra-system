-- =========================================================================
-- MIGRATION 055: Auto-create organisation on user signup.
-- When a new user signs up, a trigger creates their organisation and
-- seeds the primary sector automatically.
-- No in-app org creation UI needed.
-- =========================================================================

-- Function triggered after user confirms email / signs up
create or replace function fn_auto_create_org()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_org_id     uuid;
  v_org_name   text;
  v_org_type   text;
  v_full_name  text;
begin
  -- Read values from auth.users raw_user_meta_data (set during signup)
  v_org_name  := coalesce(
    new.raw_user_meta_data->>'company',
    new.raw_user_meta_data->>'full_name' || '''s Organisation',
    'My Organisation'
  );
  v_org_type  := coalesce(new.raw_user_meta_data->>'org_type', 'sacco');
  v_full_name := coalesce(new.raw_user_meta_data->>'full_name', new.email);

  -- Create organisation
  insert into organisations(name, org_type, status)
  values (v_org_name, v_org_type::org_type, 'active')
  returning id into v_org_id;

  -- Add user as org_admin
  insert into organisation_users(organisation_id, user_id, role, status)
  values (v_org_id, new.id, 'org_admin', 'active');

  -- Seed primary sector
  insert into organisation_sectors(organisation_id, sector, is_primary, activated_by)
  values (v_org_id, v_org_type, true, new.id)
  on conflict do nothing;

  -- Seed default org_settings
  insert into org_settings(organisation_id, org_type, show_loans, show_investments,
    show_assets, member_id_label, member_id_prefix, contribution_label, fund_label)
  values (v_org_id, v_org_type,
    v_org_type not in ('residents_association'),  -- show loans unless RA
    v_org_type in ('chama','investment_group'),    -- show investments for chama/IG
    false,
    case v_org_type when 'residents_association' then 'Unit No.' else 'Member No.' end,
    case v_org_type
      when 'chama'                then 'CH'
      when 'residents_association' then 'RA'
      when 'investment_group'     then 'IG'
      when 'welfare_group'        then 'WG'
      else 'SC' end,
    case v_org_type when 'residents_association' then 'Levies' else 'Contributions' end,
    case v_org_type
      when 'residents_association' then 'Project Funds'
      when 'chama'                 then 'Pool Funds'
      when 'investment_group'      then 'Investment Pool'
      else 'Member Funds' end
  );

  -- Save user profile
  insert into user_profiles(id, full_name, company, telephone, receive_comms, org_type_pref)
  values (
    new.id,
    v_full_name,
    v_org_name,
    new.raw_user_meta_data->>'telephone',
    coalesce((new.raw_user_meta_data->>'receive_comms')::boolean, false),
    v_org_type
  ) on conflict(id) do nothing;

  return new;
end;
$$;

-- Attach trigger to auth.users — fires when email is confirmed
drop trigger if exists trg_auto_create_org on auth.users;
create trigger trg_auto_create_org
  after insert on auth.users
  for each row execute function fn_auto_create_org();

select 'Migration 055 complete — new signups will auto-create org' as status;

-- =========================================================================
-- MIGRATION 024: User management and invitations.
--
-- Approach: an invitation is a pending row keyed by EMAIL. When someone
-- signs up (or an existing auth user is matched), fn_accept_invitation
-- links their auth.users id to the organisation with the invited role.
--
-- This avoids needing the service-role key in the browser, which would be
-- required to create auth users directly.
--
-- Run after 001-023. Safe to re-run.
-- =========================================================================

do $$ begin
  create type invite_status as enum ('pending','accepted','revoked','expired');
exception when duplicate_object then null; end $$;

-- -------------------------------------------------------------------------
-- A. INVITATIONS
-- -------------------------------------------------------------------------
create table if not exists organisation_invitations (
  id               uuid primary key default gen_random_uuid(),
  organisation_id  uuid not null references organisations(id) on delete cascade,
  email            text not null,
  role             org_role not null default 'viewer',
  status           invite_status not null default 'pending',
  invited_by       uuid references auth.users(id),
  invited_at       timestamptz not null default now(),
  accepted_at      timestamptz,
  accepted_by      uuid references auth.users(id),
  expires_at       timestamptz not null default (now() + interval '14 days'),
  note             text
);

create index if not exists idx_invites_org on organisation_invitations(organisation_id, status);
create index if not exists idx_invites_email on organisation_invitations(lower(email), status);

-- Only one pending invite per email per organisation
create unique index if not exists uq_pending_invite
  on organisation_invitations(organisation_id, lower(email))
  where status = 'pending';

alter table organisation_invitations enable row level security;

-- Org members can see invitations for their own organisation
drop policy if exists p_invites_select on organisation_invitations;
create policy p_invites_select on organisation_invitations for select
  using (is_org_member(organisation_id));

-- Anyone signed in can see invitations addressed to their own email
-- (needed so a newly signed-up user can find and accept their invite).
drop policy if exists p_invites_select_own on organisation_invitations;
create policy p_invites_select_own on organisation_invitations for select
  using (lower(email) = lower(coalesce(auth.jwt() ->> 'email','')));

drop trigger if exists trg_audit_invites on organisation_invitations;
create trigger trg_audit_invites after insert or update or delete on organisation_invitations
  for each row execute function fn_audit_trigger();

-- -------------------------------------------------------------------------
-- B. CREATE AN INVITATION (org_admin only)
-- -------------------------------------------------------------------------
create or replace function fn_invite_user(
  p_organisation_id uuid,
  p_email           text,
  p_role            org_role,
  p_note            text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_id       uuid;
  v_existing uuid;
begin
  if not has_org_role(p_organisation_id, array['org_admin']::org_role[]) then
    raise exception 'Only an organisation administrator can invite users';
  end if;
  if p_email is null or trim(p_email) = '' then
    raise exception 'An email address is required';
  end if;
  if p_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'That does not look like a valid email address';
  end if;

  -- Already a member?
  select ou.user_id into v_existing
  from organisation_users ou
  join auth.users u on u.id = ou.user_id
  where ou.organisation_id = p_organisation_id
    and lower(u.email) = lower(p_email)
    and ou.status = 'active';

  if v_existing is not null then
    raise exception 'That person is already a member of this organisation';
  end if;

  -- Supersede any existing pending invite for this email
  update organisation_invitations
     set status = 'revoked'
   where organisation_id = p_organisation_id
     and lower(email) = lower(p_email)
     and status = 'pending';

  insert into organisation_invitations(organisation_id, email, role, invited_by, note)
  values (p_organisation_id, lower(trim(p_email)), p_role, auth.uid(), p_note)
  returning id into v_id;

  return jsonb_build_object('id', v_id, 'email', lower(trim(p_email)), 'role', p_role);
end;
$$;

-- -------------------------------------------------------------------------
-- C. ACCEPT AN INVITATION
-- Called by the invited user once they have signed up / signed in.
-- Matches on the email in their JWT, so a user cannot accept someone
-- else's invitation.
-- -------------------------------------------------------------------------
create or replace function fn_accept_invitation(p_invitation_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_inv    record;
  v_email  text := lower(coalesce(auth.jwt() ->> 'email',''));
begin
  select * into v_inv from organisation_invitations where id = p_invitation_id;
  if v_inv is null then raise exception 'Invitation not found'; end if;
  if v_inv.status <> 'pending' then
    raise exception 'This invitation is % and can no longer be accepted', v_inv.status;
  end if;
  if v_inv.expires_at < now() then
    update organisation_invitations set status='expired' where id = p_invitation_id;
    raise exception 'This invitation has expired. Ask an administrator to send a new one.';
  end if;
  if lower(v_inv.email) <> v_email then
    raise exception 'This invitation was sent to a different email address';
  end if;

  insert into organisation_users(organisation_id, user_id, role, status)
  values (v_inv.organisation_id, auth.uid(), v_inv.role, 'active')
  on conflict (organisation_id, user_id)
    do update set role = excluded.role, status = 'active';

  update organisation_invitations
     set status='accepted', accepted_at=now(), accepted_by=auth.uid()
   where id = p_invitation_id;

  return jsonb_build_object('organisation_id', v_inv.organisation_id, 'role', v_inv.role);
end;
$$;

-- -------------------------------------------------------------------------
-- D. LIST MY PENDING INVITATIONS (for the signed-in user's email)
-- -------------------------------------------------------------------------
create or replace function fn_my_invitations()
returns table (
  id uuid, organisation_id uuid, organisation_name text,
  role org_role, invited_at timestamptz, expires_at timestamptz
)
language sql stable security definer set search_path = public as $$
  select i.id, i.organisation_id, o.name, i.role, i.invited_at, i.expires_at
  from organisation_invitations i
  join organisations o on o.id = i.organisation_id
  where i.status = 'pending'
    and i.expires_at > now()
    and lower(i.email) = lower(coalesce(auth.jwt() ->> 'email',''))
  order by i.invited_at desc;
$$;

-- -------------------------------------------------------------------------
-- E. REVOKE AN INVITATION
-- -------------------------------------------------------------------------
create or replace function fn_revoke_invitation(p_invitation_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_org uuid;
begin
  select organisation_id into v_org from organisation_invitations where id = p_invitation_id;
  if v_org is null then raise exception 'Invitation not found'; end if;
  if not has_org_role(v_org, array['org_admin']::org_role[]) then
    raise exception 'Only an organisation administrator can revoke invitations';
  end if;
  update organisation_invitations set status='revoked' where id = p_invitation_id;
end;
$$;

-- -------------------------------------------------------------------------
-- F. USER MANAGEMENT: list members of the organisation with their roles
-- -------------------------------------------------------------------------
create or replace function fn_organisation_users(p_organisation_id uuid)
returns table (
  user_id uuid, email text, role org_role, status text, joined_at timestamptz, is_me boolean
)
language sql stable security definer set search_path = public as $$
  select ou.user_id, u.email::text, ou.role, ou.status, ou.created_at,
         (ou.user_id = auth.uid()) as is_me
  from organisation_users ou
  join auth.users u on u.id = ou.user_id
  where ou.organisation_id = p_organisation_id
    and is_org_member(p_organisation_id)
  order by ou.created_at;
$$;

-- -------------------------------------------------------------------------
-- G. CHANGE A USER'S ROLE (org_admin only; cannot demote the last admin)
-- -------------------------------------------------------------------------
create or replace function fn_change_user_role(
  p_organisation_id uuid,
  p_user_id         uuid,
  p_new_role        org_role
) returns void
language plpgsql security definer set search_path = public as $$
declare v_admin_count int;
begin
  if not has_org_role(p_organisation_id, array['org_admin']::org_role[]) then
    raise exception 'Only an organisation administrator can change roles';
  end if;

  -- Protect against removing the last administrator
  if p_new_role <> 'org_admin' then
    select count(*) into v_admin_count
      from organisation_users
     where organisation_id = p_organisation_id
       and role = 'org_admin' and status = 'active';
    if v_admin_count <= 1 then
      select count(*) into v_admin_count
        from organisation_users
       where organisation_id = p_organisation_id
         and role = 'org_admin' and status = 'active'
         and user_id = p_user_id;
      if v_admin_count = 1 then
        raise exception 'Cannot change this role — an organisation must always have at least one administrator';
      end if;
    end if;
  end if;

  update organisation_users
     set role = p_new_role
   where organisation_id = p_organisation_id and user_id = p_user_id;
end;
$$;

-- -------------------------------------------------------------------------
-- H. DISABLE / ENABLE A USER (never hard-delete; preserves audit trail)
-- -------------------------------------------------------------------------
create or replace function fn_set_user_status(
  p_organisation_id uuid,
  p_user_id         uuid,
  p_status          text
) returns void
language plpgsql security definer set search_path = public as $$
declare v_admin_count int;
begin
  if not has_org_role(p_organisation_id, array['org_admin']::org_role[]) then
    raise exception 'Only an organisation administrator can enable or disable users';
  end if;
  if p_status not in ('active','disabled') then
    raise exception 'Status must be active or disabled';
  end if;
  if p_user_id = auth.uid() and p_status = 'disabled' then
    raise exception 'You cannot disable your own account';
  end if;

  if p_status = 'disabled' then
    select count(*) into v_admin_count
      from organisation_users
     where organisation_id = p_organisation_id
       and role = 'org_admin' and status = 'active' and user_id <> p_user_id;
    if v_admin_count = 0 then
      raise exception 'Cannot disable the last active administrator';
    end if;
  end if;

  update organisation_users
     set status = p_status
   where organisation_id = p_organisation_id and user_id = p_user_id;
end;
$$;

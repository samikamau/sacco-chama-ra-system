-- =========================================================================
-- MIGRATION 045 v2: Fix guarantor capacity — security invoker, no auth check
-- that breaks in SQL Editor superuser context.
-- =========================================================================

-- 1. Release all guarantors on closed loans
update loan_guarantors lg
   set amount_released = amount_guaranteed
  from loans l
 where l.id = lg.loan_id
   and l.status = 'closed'
   and lg.amount_released < lg.amount_guaranteed;

-- 2. Fix fn_guarantor_capacity — security invoker, no is_org_member guard
drop function if exists fn_guarantor_capacity(uuid, uuid);

create or replace function fn_guarantor_capacity(
  p_member_id       uuid,
  p_exclude_loan_id uuid default null
) returns jsonb
language plpgsql stable security invoker set search_path = public as $$
declare
  v_deposits  numeric(14,2);
  v_committed numeric(14,2);
  v_available numeric(14,2);
begin
  -- Total share deposits
  select coalesce(sum(pa.amount), 0) into v_deposits
  from payment_allocations pa
  join payments p on p.id = pa.payment_id
  join contribution_types ct on ct.id = pa.contribution_type_id
  where p.member_id = p_member_id
    and p.status = 'posted'
    and ct.category = 'share_deposit';

  -- Net commitment on ACTIVE loans only
  select coalesce(sum(lg.amount_guaranteed - lg.amount_released), 0) into v_committed
  from loan_guarantors lg
  join loans l on l.id = lg.loan_id
  where lg.guarantor_member_id = p_member_id
    and l.status in ('active','disbursed','pending_approval','approved')
    and (p_exclude_loan_id is null or l.id <> p_exclude_loan_id);

  v_available := greatest(v_deposits - v_committed, 0);

  return jsonb_build_object(
    'total_deposits', v_deposits,
    'committed',      v_committed,
    'available',      v_available
  );
end;
$$;

-- 3. Verify
select
  m.full_name,
  (fn_guarantor_capacity(m.id))->>'total_deposits' as deposits,
  (fn_guarantor_capacity(m.id))->>'committed'      as committed,
  (fn_guarantor_capacity(m.id))->>'available'      as available
from members m
where m.organisation_id = '1f452f1c-b441-47c1-ac85-d22087519b5e'
  and m.status = 'active'
order by m.full_name;

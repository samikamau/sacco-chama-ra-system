-- =========================================================================
-- MIGRATION 046: Close all fully paid loans and release their guarantors.
-- Both active loans (1,000,000 and 1,425,000) are confirmed fully paid.
-- =========================================================================

-- Close all active loans for this organisation
-- (confirmed by user — all are fully paid)
update loans
   set status = 'closed'
 where organisation_id = '1f452f1c-b441-47c1-ac85-d22087519b5e'
   and status in ('active','disbursed','pending_approval','approved');

-- Release all guarantors on all closed loans
update loan_guarantors lg
   set amount_released = amount_guaranteed
  from loans l
 where l.id = lg.loan_id
   and l.organisation_id = '1f452f1c-b441-47c1-ac85-d22087519b5e'
   and l.status = 'closed'
   and lg.amount_released < lg.amount_guaranteed;

-- Verify: all members should now show 0 committed, full deposits available
select
  m.full_name,
  (fn_guarantor_capacity(m.id))->>'total_deposits' as deposits,
  (fn_guarantor_capacity(m.id))->>'committed'      as committed,
  (fn_guarantor_capacity(m.id))->>'available'      as available
from members m
where m.organisation_id = '1f452f1c-b441-47c1-ac85-d22087519b5e'
  and m.status = 'active'
order by m.full_name;

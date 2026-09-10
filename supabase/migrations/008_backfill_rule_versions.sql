-- =========================================================================
-- MIGRATION 008: Backfill a version-1 row for every existing contribution
-- rule, so the new version-aware period generator has something to resolve.
-- Uses each rule's current flat amount/due_day as the v1 fixed amount,
-- effective from the org's earliest data (or 2020-01-01 as a safe floor).
-- Safe to re-run — skips rules that already have a version.
-- =========================================================================
do $$
declare r record;
begin
  for r in
    select cr.id, cr.organisation_id, cr.amount, cr.due_day
    from contribution_rules cr
    where not exists (
      select 1 from contribution_rule_versions v where v.rule_id = cr.id
    )
  loop
    insert into contribution_rule_versions(
      rule_id, organisation_id, version_no, calc_method, fixed_amount,
      frequency, due_day, grace_days, effective_from, status)
    values (
      r.id, r.organisation_id, 1, 'fixed', coalesce(r.amount, 0),
      'monthly', coalesce(r.due_day, 5), 5, '2020-01-01', 'active');
  end loop;
end $$;

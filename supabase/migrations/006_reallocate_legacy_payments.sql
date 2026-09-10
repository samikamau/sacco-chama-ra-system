-- =========================================================================
-- MIGRATION 006: Reallocate a legacy (pre-fund-type) payment to a fund.
-- Posts a correcting journal entry (Dr old generic account, Cr the fund's
-- account) rather than editing the original entry, and creates the missing
-- payment_allocations row so the payment now applies against that fund's
-- outstanding contributions too.
-- =========================================================================

create or replace function fn_reallocate_legacy_payment(
  p_payment_id           uuid,
  p_contribution_type_id uuid
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_org_id          uuid;
  v_member_id       uuid;
  v_amount          numeric(14,2);
  v_old_entry_id    uuid;
  v_old_account_id  uuid;
  v_new_account_id  uuid;
  v_new_entry_id    uuid;
  v_remaining       numeric(14,2);
  v_contrib         record;
  v_apply           numeric(14,2);
begin
  select organisation_id, member_id, amount, journal_entry_id
    into v_org_id, v_member_id, v_amount, v_old_entry_id
    from payments where id = p_payment_id;

  if v_old_entry_id is null then
    raise exception 'Payment not found or was never posted';
  end if;

  if not is_org_member(v_org_id) then
    raise exception 'Not authorised for this organisation';
  end if;

  if exists (select 1 from payment_allocations where payment_id = p_payment_id) then
    raise exception 'This payment has already been allocated to a fund';
  end if;

  -- Find the account the payment was originally credited to (the old
  -- generic "Contribution Income" side of the entry, not the cash debit).
  select account_id into v_old_account_id
    from journal_lines where journal_entry_id = v_old_entry_id and credit > 0 limit 1;

  select chart_account_id into v_new_account_id
    from contribution_types where id = p_contribution_type_id and organisation_id = v_org_id;

  if v_new_account_id is null then
    raise exception 'Fund type not found for this organisation';
  end if;

  -- Correcting entry: move the value from the old account to the fund's account.
  insert into journal_entries(organisation_id, description, source_type, source_id, created_by)
  values (v_org_id, 'Reallocate payment to fund', 'reallocation', p_payment_id, auth.uid())
  returning id into v_new_entry_id;

  insert into journal_lines(journal_entry_id, account_id, debit, credit, member_id)
  values (v_new_entry_id, v_old_account_id, v_amount, 0, v_member_id);

  insert into journal_lines(journal_entry_id, account_id, debit, credit, member_id)
  values (v_new_entry_id, v_new_account_id, 0, v_amount, v_member_id);

  insert into payment_allocations(payment_id, contribution_type_id, amount)
  values (p_payment_id, p_contribution_type_id, v_amount);

  -- Apply against this fund's outstanding contributions, oldest period first.
  v_remaining := v_amount;
  for v_contrib in
    select c.id, c.amount_expected, c.amount_paid
    from contributions c
    join contribution_periods cp on cp.id = c.period_id
    join contribution_rules cr on cr.id = cp.rule_id
    where c.member_id = v_member_id
      and cr.contribution_type_id = p_contribution_type_id
      and c.status in ('unpaid','partial')
    order by cp.period_start asc
  loop
    exit when v_remaining <= 0;
    v_apply := least(v_remaining, v_contrib.amount_expected - v_contrib.amount_paid);
    update contributions
      set amount_paid = amount_paid + v_apply,
          status = (case
                      when amount_paid + v_apply >= amount_expected then 'paid'
                      else 'partial'
                   end)::contribution_status
      where id = v_contrib.id;
    v_remaining := v_remaining - v_apply;
  end loop;

  return v_new_entry_id;
end;
$$;

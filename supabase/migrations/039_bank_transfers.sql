-- =========================================================================
-- MIGRATION 039: Bank transfers between payment accounts.
-- Dr destination account / Cr source account.
-- Both must be is_payment_account = true (leaf accounts under Bank 1000).
-- =========================================================================

create or replace function fn_bank_transfer(
  p_organisation_id uuid,
  p_from_account_id uuid,   -- Cr this account (source)
  p_to_account_id   uuid,   -- Dr this account (destination)
  p_amount          numeric,
  p_transfer_date   date,
  p_reference       text default null,
  p_description     text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_entry_id uuid;
  v_num      text;
  v_from_pay boolean;
  v_to_pay   boolean;
  v_from_name text;
  v_to_name   text;
begin
  if not has_org_role(p_organisation_id, array['org_admin','treasurer','accountant']::org_role[]) then
    raise exception 'Not authorised to record bank transfers';
  end if;
  if p_amount <= 0 then raise exception 'Transfer amount must be greater than zero'; end if;
  if p_from_account_id = p_to_account_id then raise exception 'Cannot transfer to the same account'; end if;

  select is_payment_account, name into v_from_pay, v_from_name
    from chart_of_accounts where id = p_from_account_id and organisation_id = p_organisation_id;
  select is_payment_account, name into v_to_pay, v_to_name
    from chart_of_accounts where id = p_to_account_id and organisation_id = p_organisation_id;

  if not coalesce(v_from_pay, false) then
    raise exception 'Source account "%" is not a bank/cash/M-Pesa account', v_from_name;
  end if;
  if not coalesce(v_to_pay, false) then
    raise exception 'Destination account "%" is not a bank/cash/M-Pesa account', v_to_name;
  end if;

  v_num := fn_next_journal_number(p_organisation_id);

  insert into journal_entries(organisation_id, entry_date, description,
    source_type, status, journal_number, created_by)
  values (p_organisation_id, p_transfer_date,
    coalesce(p_description, 'Transfer: ' || v_from_name || ' → ' || v_to_name),
    'bank_transfer', 'posted', v_num, auth.uid())
  returning id into v_entry_id;

  -- Dr destination (money arrives)
  insert into journal_lines(journal_entry_id, account_id, debit, credit)
  values (v_entry_id, p_to_account_id, p_amount, 0);

  -- Cr source (money leaves)
  insert into journal_lines(journal_entry_id, account_id, debit, credit)
  values (v_entry_id, p_from_account_id, 0, p_amount);

  return v_entry_id;
end;
$$;

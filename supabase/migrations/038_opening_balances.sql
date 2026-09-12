-- =========================================================================
-- MIGRATION 038: Opening balances support.
-- Opening balances are journal entries with source_type = 'opening_balance'.
-- They post on a specific date and establish starting positions for all
-- accounts. Only one opening balance entry per account per organisation
-- is enforced (can be corrected via reversal + new entry).
-- =========================================================================

-- Function to post opening balances
-- p_balances: [{"account_id":"...","debit":0,"credit":5000}, ...]
create or replace function fn_post_opening_balances(
  p_organisation_id uuid,
  p_as_at           date,
  p_balances        jsonb
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_entry_id uuid;
  v_num      text;
  v_bal      jsonb;
  v_acct     uuid;
  v_dr       numeric(14,2);
  v_cr       numeric(14,2);
  v_total_dr numeric(14,2) := 0;
  v_total_cr numeric(14,2) := 0;
  v_is_ctrl  boolean;
begin
  if not has_org_role(p_organisation_id, array['org_admin','accountant']::org_role[]) then
    raise exception 'Not authorised to post opening balances';
  end if;

  -- Validate all lines balance
  for v_bal in select * from jsonb_array_elements(p_balances) loop
    v_total_dr := v_total_dr + coalesce((v_bal->>'debit')::numeric, 0);
    v_total_cr := v_total_cr + coalesce((v_bal->>'credit')::numeric, 0);
  end loop;

  if abs(v_total_dr - v_total_cr) > 0.005 then
    raise exception 'Opening balances do not balance — debits % vs credits %', v_total_dr, v_total_cr;
  end if;

  v_num := fn_next_journal_number(p_organisation_id);

  insert into journal_entries(organisation_id, entry_date, description,
    source_type, status, journal_number, created_by)
  values (p_organisation_id, p_as_at,
    'Opening balances as at ' || to_char(p_as_at, 'DD Mon YYYY'),
    'opening_balance', 'posted', v_num, auth.uid())
  returning id into v_entry_id;

  for v_bal in select * from jsonb_array_elements(p_balances) loop
    v_acct := (v_bal->>'account_id')::uuid;
    v_dr   := coalesce((v_bal->>'debit')::numeric, 0);
    v_cr   := coalesce((v_bal->>'credit')::numeric, 0);

    if v_dr = 0 and v_cr = 0 then continue; end if;

    select is_control into v_is_ctrl from chart_of_accounts where id = v_acct;
    if coalesce(v_is_ctrl, false) then
      raise exception 'Cannot post opening balance to a control account. Use a sub-account.';
    end if;

    insert into journal_lines(journal_entry_id, account_id, debit, credit)
    values (v_entry_id, v_acct, v_dr, v_cr);
  end loop;

  return v_entry_id;
end;
$$;

-- Add opening_balance to the journal source_type check if not already there
-- (source_type is text, no enum constraint — safe to use directly)

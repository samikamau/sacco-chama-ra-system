-- =========================================================================
-- MIGRATION 035 v2: Restructure Chart of Accounts — correct ordering.
-- Renames conflicting codes to temp values first, then applies final codes.
-- No UUIDs changed. All journal_lines references preserved.
-- =========================================================================

do $$
declare
  v_org uuid := '1f452f1c-b441-47c1-ac85-d22087519b5e';
  v_1000 uuid; v_1010 uuid; v_1020 uuid; v_1050 uuid; v_1060 uuid;
  v_1100 uuid; v_1250 uuid; v_2000 uuid; v_2010 uuid; v_2020 uuid;
  v_2030 uuid; v_2050 uuid; v_2100 uuid; v_3000 uuid; v_4000 uuid;
  v_4100 uuid; v_4200 uuid; v_5000 uuid; v_5100 uuid; v_5200 uuid;
  v_5300 uuid; v_5400 uuid;
  v_p1000 uuid; v_p1100 uuid; v_p1200 uuid; v_p1300 uuid;
  v_p2000 uuid; v_p3000 uuid; v_p4000 uuid; v_p5000 uuid; v_p6000 uuid;
begin
  -- 1. Fetch existing UUIDs by current code
  select id into v_1000 from chart_of_accounts where organisation_id=v_org and code='1000';
  select id into v_1010 from chart_of_accounts where organisation_id=v_org and code='1010';
  select id into v_1020 from chart_of_accounts where organisation_id=v_org and code='1020';
  select id into v_1050 from chart_of_accounts where organisation_id=v_org and code='1050';
  select id into v_1060 from chart_of_accounts where organisation_id=v_org and code='1060';
  select id into v_1100 from chart_of_accounts where organisation_id=v_org and code='1100';
  select id into v_1250 from chart_of_accounts where organisation_id=v_org and code='1250';
  select id into v_2000 from chart_of_accounts where organisation_id=v_org and code='2000';
  select id into v_2010 from chart_of_accounts where organisation_id=v_org and code='2010';
  select id into v_2020 from chart_of_accounts where organisation_id=v_org and code='2020';
  select id into v_2030 from chart_of_accounts where organisation_id=v_org and code='2030';
  select id into v_2050 from chart_of_accounts where organisation_id=v_org and code='2050';
  select id into v_2100 from chart_of_accounts where organisation_id=v_org and code='2100';
  select id into v_3000 from chart_of_accounts where organisation_id=v_org and code='3000';
  select id into v_4000 from chart_of_accounts where organisation_id=v_org and code='4000';
  select id into v_4100 from chart_of_accounts where organisation_id=v_org and code='4100';
  select id into v_4200 from chart_of_accounts where organisation_id=v_org and code='4200';
  select id into v_5000 from chart_of_accounts where organisation_id=v_org and code='5000';
  select id into v_5100 from chart_of_accounts where organisation_id=v_org and code='5100';
  select id into v_5200 from chart_of_accounts where organisation_id=v_org and code='5200';
  select id into v_5300 from chart_of_accounts where organisation_id=v_org and code='5300';
  select id into v_5400 from chart_of_accounts where organisation_id=v_org and code='5400';

  -- 2. Clear ALL parent references to avoid FK conflicts during recoding
  update chart_of_accounts set parent_account_id = null where organisation_id = v_org;

  -- 3. TEMP rename all codes that will collide during the restructure
  --    Using 9xxx prefix as safe temp namespace
  update chart_of_accounts set code='9001' where id=v_1000; -- Cash on Hand  → will become 1010
  update chart_of_accounts set code='9002' where id=v_1010; -- Bank Account  → will become 1020
  update chart_of_accounts set code='9003' where id=v_1020; -- M-Pesa        → will become 1040
  update chart_of_accounts set code='9004' where id=v_1050; -- Current Assets→ will become 1100 control
  update chart_of_accounts set code='9005' where id=v_1060; -- Bank&Cash ctrl → will become 1000 control
  update chart_of_accounts set code='9006' where id=v_1100; -- Loans Recv    → will become 1110
  update chart_of_accounts set code='9007' where id=v_1250; -- Fixed Assets  → will become 1300 control
  update chart_of_accounts set code='9008' where id=v_2010; -- Share Deposits→ will become 2020
  update chart_of_accounts set code='9009' where id=v_2020; -- Welfare Fund  → will become 2030
  update chart_of_accounts set code='9010' where id=v_2030; -- Accts Payable → will become 2010
  update chart_of_accounts set code='9011' where id=v_2050; -- (deactivate)
  update chart_of_accounts set code='9012' where id=v_2100; -- (deactivate)
  update chart_of_accounts set code='9013' where id=v_3000; -- Share Capital → split: ctrl 3000 + leaf 3010
  update chart_of_accounts set code='9014' where id=v_4000; -- Legacy income → will become 4000 contrib ctrl
  update chart_of_accounts set code='9015' where id=v_4100; -- Interest Inc  → will become 5010
  update chart_of_accounts set code='9016' where id=v_4200; -- Fine Income   → will become 5030
  update chart_of_accounts set code='9017' where id=v_5000; -- Admin Expense → will become 5000 income ctrl
  update chart_of_accounts set code='9018' where id=v_5100; -- Bank Charges  → will become 6050
  update chart_of_accounts set code='9019' where id=v_5200; -- Stationery    → will become 6070
  update chart_of_accounts set code='9020' where id=v_5300; -- Prof Fees     → will become 6060
  update chart_of_accounts set code='9021' where id=v_5400; -- Rent&Utils    → will become 6080

  -- 4. CONTROL ACCOUNTS (level 1) — all final codes now free
  -- 1000 Bank & Cash
  update chart_of_accounts set code='1000', name='Bank & Cash',
    account_type='asset', subtype='bank_cash_control', normal_balance='debit',
    is_control=true, is_payment_account=false, is_active=true
  where id=v_1060;
  v_p1000 := v_1060;

  -- 1100 Member Receivables
  update chart_of_accounts set code='1100', name='Member Receivables',
    account_type='asset', subtype='group', normal_balance='debit',
    is_control=true, is_payment_account=false, is_active=true
  where id=v_1050;
  v_p1100 := v_1050;

  -- 1200 Investments (new)
  insert into chart_of_accounts(organisation_id,code,name,account_type,subtype,
    normal_balance,is_control,is_payment_account,is_active)
  values(v_org,'1200','Investments','asset','group','debit',true,false,true)
  on conflict(organisation_id,code) do nothing;
  select id into v_p1200 from chart_of_accounts where organisation_id=v_org and code='1200';

  -- 1300 Fixed Assets
  update chart_of_accounts set code='1300', name='Fixed Assets',
    account_type='asset', subtype='group', normal_balance='debit',
    is_control=true, is_payment_account=false, is_active=true
  where id=v_1250;
  v_p1300 := v_1250;

  -- 2000 Liabilities (keep)
  update chart_of_accounts set name='Liabilities', subtype='group',
    is_control=true, is_active=true where id=v_2000;
  v_p2000 := v_2000;

  -- 3000 Member Funds (repurpose existing 3000 as control; journal lines moved to 3010)
  -- First create 3010 Member Share Capital leaf account
  insert into chart_of_accounts(organisation_id,code,name,account_type,subtype,
    normal_balance,is_control,is_payment_account,is_active)
  values(v_org,'3010','Member Share Capital','equity','retained_earnings','credit',false,false,true)
  on conflict(organisation_id,code) do nothing;

  -- Remap journal_lines from old 3000 → new 3010
  update journal_lines set account_id=(
    select id from chart_of_accounts where organisation_id=v_org and code='3010'
  ) where account_id=v_3000;

  -- Now make 3000 the control
  update chart_of_accounts set code='3000', name='Member Funds',
    account_type='equity', subtype='group', normal_balance='credit',
    is_control=true, is_payment_account=false, is_active=true
  where id=v_3000;
  v_p3000 := v_3000;

  -- 4000 Contributions
  update chart_of_accounts set code='4000', name='Contributions',
    account_type='income', subtype='group', normal_balance='credit',
    is_control=true, is_payment_account=false, is_active=true,
    description='Contribution types — sub-accounts track each contribution category.'
  where id=v_4000;
  v_p4000 := v_4000;

  -- 5000 Income
  update chart_of_accounts set code='5000', name='Income',
    account_type='income', subtype='group', normal_balance='credit',
    is_control=true, is_payment_account=false, is_active=true
  where id=v_5000;
  v_p5000 := v_5000;

  -- 6000 Expenses (new)
  insert into chart_of_accounts(organisation_id,code,name,account_type,subtype,
    normal_balance,is_control,is_payment_account,is_active)
  values(v_org,'6000','Expenses','expense','group','debit',true,false,true)
  on conflict(organisation_id,code) do nothing;
  select id into v_p6000 from chart_of_accounts where organisation_id=v_org and code='6000';

  -- 5. SUB-ACCOUNTS under 1000 Bank & Cash
  update chart_of_accounts set code='1010', name='Cash on Hand',
    account_type='asset', subtype='cash', normal_balance='debit',
    is_control=false, is_payment_account=true, is_active=true,
    parent_account_id=v_p1000
  where id=v_1000;

  update chart_of_accounts set code='1020', name='Main Bank Account',
    account_type='asset', subtype='bank', normal_balance='debit',
    is_control=false, is_payment_account=true, is_active=true,
    parent_account_id=v_p1000
  where id=v_1010;

  update chart_of_accounts set code='1040', name='M-Pesa / Paybill',
    account_type='asset', subtype='mpesa', normal_balance='debit',
    is_control=false, is_payment_account=true, is_active=true,
    parent_account_id=v_p1000
  where id=v_1020;

  insert into chart_of_accounts(organisation_id,code,name,account_type,subtype,
    normal_balance,is_control,is_payment_account,is_active,parent_account_id)
  values
    (v_org,'1030','Savings Bank Account','asset','bank','debit',false,true,false,v_p1000),
    (v_org,'1050','Other Bank Account','asset','bank','debit',false,true,false,v_p1000)
  on conflict(organisation_id,code) do update set
    name=excluded.name, parent_account_id=excluded.parent_account_id;

  -- Under 1100 Member Receivables
  update chart_of_accounts set code='1110', name='Member Loans',
    account_type='asset', subtype='loans_receivable', normal_balance='debit',
    is_control=false, is_payment_account=false, is_active=true,
    parent_account_id=v_p1100
  where id=v_1100;

  insert into chart_of_accounts(organisation_id,code,name,account_type,subtype,
    normal_balance,is_control,is_payment_account,is_active,parent_account_id)
  values
    (v_org,'1120','Loan Interest Receivable','asset','interest_receivable','debit',false,false,true,v_p1100),
    (v_org,'1130','Member Advances','asset','advances','debit',false,false,true,v_p1100)
  on conflict(organisation_id,code) do update set parent_account_id=excluded.parent_account_id;

  -- Under 1200 Investments
  insert into chart_of_accounts(organisation_id,code,name,account_type,subtype,
    normal_balance,is_control,is_payment_account,is_active,parent_account_id)
  values
    (v_org,'1210','Fixed Deposits','asset','investment','debit',false,false,true,v_p1200),
    (v_org,'1220','Treasury Bills & Bonds','asset','investment','debit',false,false,true,v_p1200),
    (v_org,'1230','Other Investments','asset','investment','debit',false,false,true,v_p1200)
  on conflict(organisation_id,code) do update set parent_account_id=excluded.parent_account_id;

  -- Under 1300 Fixed Assets
  insert into chart_of_accounts(organisation_id,code,name,account_type,subtype,
    normal_balance,is_control,is_payment_account,is_active,parent_account_id)
  values
    (v_org,'1310','Furniture & Fittings','asset','fixed_asset','debit',false,false,true,v_p1300),
    (v_org,'1320','Equipment','asset','fixed_asset','debit',false,false,true,v_p1300),
    (v_org,'1330','Computers','asset','fixed_asset','debit',false,false,true,v_p1300),
    (v_org,'1390','Accumulated Depreciation','asset','accum_depreciation','credit',false,false,true,v_p1300)
  on conflict(organisation_id,code) do update set parent_account_id=excluded.parent_account_id;

  -- Under 2000 Liabilities
  update chart_of_accounts set code='2010', name='Accounts Payable',
    subtype='current_liability', is_control=false, is_active=true,
    parent_account_id=v_p2000
  where id=v_2030;

  update chart_of_accounts set code='2020', name='Member Share Deposits',
    subtype='member_funds', is_control=false, is_active=true,
    parent_account_id=v_p2000
  where id=v_2010;

  update chart_of_accounts set code='2030', name='Member Welfare Fund',
    subtype='member_funds', is_control=false, is_active=true,
    parent_account_id=v_p2000
  where id=v_2020;

  update chart_of_accounts set is_active=false, parent_account_id=v_p2000
  where id in (v_2050, v_2100);

  insert into chart_of_accounts(organisation_id,code,name,account_type,subtype,
    normal_balance,is_control,is_payment_account,is_active,parent_account_id)
  values
    (v_org,'2040','External Loans','liability','long_term_liability','credit',false,false,true,v_p2000),
    (v_org,'2050','Accrued Expenses','liability','current_liability','credit',false,false,true,v_p2000),
    (v_org,'2060','Taxes Payable','liability','current_liability','credit',false,false,true,v_p2000),
    (v_org,'2070','Staff Payables','liability','current_liability','credit',false,false,true,v_p2000)
  on conflict(organisation_id,code) do update set parent_account_id=excluded.parent_account_id;

  -- Under 3000 Member Funds
  update chart_of_accounts set parent_account_id=v_p3000
  where organisation_id=v_org and code='3010';

  insert into chart_of_accounts(organisation_id,code,name,account_type,subtype,
    normal_balance,is_control,is_payment_account,is_active,parent_account_id)
  values
    (v_org,'3040','General Reserve','equity','reserve','credit',false,false,true,v_p3000),
    (v_org,'3050','Education & Training Fund','equity','reserve','credit',false,false,true,v_p3000)
  on conflict(organisation_id,code) do update set parent_account_id=excluded.parent_account_id;

  -- Under 4000 Contributions
  insert into chart_of_accounts(organisation_id,code,name,account_type,subtype,
    normal_balance,is_control,is_payment_account,is_active,parent_account_id)
  values
    (v_org,'4010','Monthly Contributions','income','contribution','credit',false,false,true,v_p4000),
    (v_org,'4020','Share Contributions','income','contribution','credit',false,false,true,v_p4000),
    (v_org,'4030','Welfare Contributions','income','contribution','credit',false,false,true,v_p4000),
    (v_org,'4040','Registration & Joining Fees','income','contribution','credit',false,false,true,v_p4000),
    (v_org,'4050','Special Contributions','income','contribution','credit',false,false,true,v_p4000)
  on conflict(organisation_id,code) do update set parent_account_id=excluded.parent_account_id;

  -- Under 5000 Income
  update chart_of_accounts set code='5010', name='Loan Interest Income',
    account_type='income', subtype='interest_income', normal_balance='credit',
    is_control=false, is_active=true, parent_account_id=v_p5000
  where id=v_4100;

  update chart_of_accounts set code='5030', name='Penalties & Fines',
    account_type='income', subtype='other_income', normal_balance='credit',
    is_control=false, is_active=true, parent_account_id=v_p5000
  where id=v_4200;

  insert into chart_of_accounts(organisation_id,code,name,account_type,subtype,
    normal_balance,is_control,is_payment_account,is_active,parent_account_id)
  values
    (v_org,'5020','Loan Processing Fees','income','fee_income','credit',false,false,true,v_p5000),
    (v_org,'5040','Bank Interest','income','interest_income','credit',false,false,true,v_p5000),
    (v_org,'5050','Investment Income','income','investment_income','credit',false,false,true,v_p5000),
    (v_org,'5060','Rental Income','income','other_income','credit',false,false,true,v_p5000),
    (v_org,'5070','Grants & Donations','income','other_income','credit',false,false,true,v_p5000),
    (v_org,'5080','Other Income','income','other_income','credit',false,false,true,v_p5000)
  on conflict(organisation_id,code) do update set parent_account_id=excluded.parent_account_id;

  -- Under 6000 Expenses
  update chart_of_accounts set code='6050', name='Bank Charges',
    account_type='expense', subtype='operating', normal_balance='debit',
    is_control=false, is_active=true, parent_account_id=v_p6000
  where id=v_5100;

  update chart_of_accounts set code='6060', name='Audit & Accounting Fees',
    account_type='expense', subtype='operating', normal_balance='debit',
    is_control=false, is_active=true, parent_account_id=v_p6000
  where id=v_5300;

  update chart_of_accounts set code='6070', name='Stationery',
    account_type='expense', subtype='operating', normal_balance='debit',
    is_control=false, is_active=true, parent_account_id=v_p6000
  where id=v_5200;

  update chart_of_accounts set code='6080', name='Rent & Utilities',
    account_type='expense', subtype='operating', normal_balance='debit',
    is_control=false, is_active=true, parent_account_id=v_p6000
  where id=v_5400;

  insert into chart_of_accounts(organisation_id,code,name,account_type,subtype,
    normal_balance,is_control,is_payment_account,is_active,parent_account_id)
  values
    (v_org,'6010','Salaries & Wages','expense','operating','debit',false,false,true,v_p6000),
    (v_org,'6020','Rent','expense','operating','debit',false,false,true,v_p6000),
    (v_org,'6030','Electricity & Water','expense','operating','debit',false,false,true,v_p6000),
    (v_org,'6040','Internet & Telephone','expense','operating','debit',false,false,true,v_p6000),
    (v_org,'6055','M-Pesa Charges','expense','operating','debit',false,false,true,v_p6000),
    (v_org,'6065','Legal Fees','expense','operating','debit',false,false,true,v_p6000),
    (v_org,'6075','Insurance','expense','operating','debit',false,false,true,v_p6000),
    (v_org,'6085','Transport','expense','operating','debit',false,false,true,v_p6000),
    (v_org,'6090','Repairs & Maintenance','expense','operating','debit',false,false,true,v_p6000),
    (v_org,'6095','Software Subscriptions','expense','operating','debit',false,false,true,v_p6000),
    (v_org,'6100','Meetings & Events','expense','operating','debit',false,false,true,v_p6000),
    (v_org,'6110','Depreciation','expense','operating','debit',false,false,true,v_p6000),
    (v_org,'6120','Security','expense','operating','debit',false,false,true,v_p6000),
    (v_org,'6130','Other Expenses','expense','operating','debit',false,false,true,v_p6000)
  on conflict(organisation_id,code) do update set parent_account_id=excluded.parent_account_id;

  -- 6. Update loan product account references
  update loan_products set
    loan_receivable_account_id=(select id from chart_of_accounts where organisation_id=v_org and code='1110')
  where organisation_id=v_org and loan_receivable_account_id=v_1100;

  update loan_products set
    interest_income_account_id=(select id from chart_of_accounts where organisation_id=v_org and code='5010')
  where organisation_id=v_org and interest_income_account_id=v_4100;

  -- 7. Update bank/mpesa account chart references
  update bank_accounts set
    chart_account_id=(select id from chart_of_accounts where organisation_id=v_org and code='1020')
  where organisation_id=v_org and chart_account_id=v_1010;

  update mpesa_accounts set
    chart_account_id=(select id from chart_of_accounts where organisation_id=v_org and code='1040')
  where organisation_id=v_org and chart_account_id=v_1020;

  raise notice 'COA restructure complete';
end $$;

-- Verify final structure
select code, name, account_type, subtype,
  coalesce(is_control,false) as ctrl,
  coalesce(is_active,true) as active,
  (select code from chart_of_accounts p where p.id=coa.parent_account_id) as parent
from chart_of_accounts coa
where organisation_id='1f452f1c-b441-47c1-ac85-d22087519b5e'
order by code;

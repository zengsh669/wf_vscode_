SET ThousandSep=',';
SET DecimalSep='.';
SET MoneyThousandSep=',';
SET MoneyDecimalSep='.';
SET MoneyFormat='$#,##0.00;-$#,##0.00';
SET TimeFormat='h:mm:ss TT';
SET DateFormat='D/M/YYYY';
SET TimestampFormat='D/M/YYYY h:mm:ss[.fff] TT';
SET FirstWeekDay=0;
SET BrokenWeeks=1;
SET ReferenceDay=0;
SET FirstMonthOfYear=1;
SET CollationLocale='en-AU';
SET CreateSearchIndexOnReload=1;
SET MonthNames='Jan;Feb;Mar;Apr;May;June;July;Aug;Sept;Oct;Nov;Dec';
SET LongMonthNames='January;February;March;April;May;June;July;August;September;October;November;December';
SET DayNames='Mon;Tue;Wed;Thu;Fri;Sat;Sun';
SET LongDayNames='Monday;Tuesday;Wednesday;Thursday;Friday;Saturday;Sunday';
SET NumericalAbbreviation='3:k;6:M;9:G;12:T;15:P;18:E;21:Z;24:Y;-3:m;-6:μ;-9:n;-12:p;-15:f;-18:a;-21:z;-24:y';

LIB CONNECT TO 'rpsqlrp01 - paragonreporting';

AccountDetailsMap:
Mapping
LOAD "membership_id",
    "account_type" 													as [Debit];
SQL SELECT *
FROM paragonreporting.dbo.account
where (account_type ='D' and status_flag = 'A');


LIB CONNECT TO 'rpsqlrp01 - paragonreporting';

Payments:
LOAD 
    membership_id & '|' & MonthStart(date(rundate-1)) as MbrMonthKey,
    membership_id,
    ApplyMap('AccountDetailsMap',membership_id,'No Details') 				as [Direct Debit Details],
    If(IsNull(group_id),'No Group', group_id) as [Group ID],
    cover,
    If(WildMatch(cover,'*Athlete*'), 'Athlete',
    If(WildMatch(cover,'*Ambulance*'), 'Ambulance', 'All other covers')) as [Cover Category],
    product_code,
    Date(date_paidto) as date_paidto,
    join_date,
    member_arrears,
    member_advance,
    member_cont,
    Date(rundate-1) as RUNDATE,
    MonthName(date(rundate-1)) as MonthYear,
    member_arrears_no_other,
    member_advance_no_other,
    member_arrears_unearned,
    member_arrears_hosp,
    member_advance_hosp,
    member_cont_hosp,
    member_arr_unearned_hosp,
    member_arrears_extras,
    member_advance_extras,
    member_cont_extras,
    member_arr_unearned_extras,
    cover_state,
    branch_group_id,
    branch_description,
    hosp_product_id,
    extras_product_id,
    ambuln_product_id,
    cover_type,
    billing_freq,
    billing_type,
    member_advance_days,

    If(member_advance_days >= 0 and member_advance_days <= 10, '0-10 Days',
    If(member_advance_days >= 11 and member_advance_days <= 20, '11-20 Days',
    If(member_advance_days >= 21 and member_advance_days <= 30, '21-30 Days',
    If(member_advance_days >= 31 and member_advance_days <= 60, '31-60 Days',
    If(member_advance_days >= 61 and member_advance_days <= 90, '61-90 Days',
    If(member_advance_days >= 91 and member_advance_days <= 181, '3-6 Months',
    If(member_advance_days >= 182 and member_advance_days <= 365, '6-12 Months',
    If(member_advance_days >= 366 and member_advance_days <= 548, '12-18 Months',
    If(member_advance_days >=549, '> 18 Months'))))))))) as [Advance Days Bracket],

    member_arrears_days,
	if(member_arrears_days<=0,'Not in Arrears',
    If(member_arrears_days >= 0 and member_arrears_days <= 10, '0-10',
    If(member_arrears_days >= 11 and member_arrears_days <= 20, '11-20',
    If(member_arrears_days >= 21 and member_arrears_days <= 30, '21-30',
    If(member_arrears_days >= 31 and member_arrears_days <= 60, '31-60',
    If(member_arrears_days >= 61 and member_arrears_days <= 90, '61-90',
    If(member_arrears_days >= 91, '91+'))))))) as [Arrears Days Bracket],

    sales_channel_description,
    billing_freq_description,
    hear_about_description,
    promotion_description,
    agent_description,
    billing_group_description,
    previous_fund_id,
    previous_fund_description,

    If(WildMatch(billing_group_description,'*Direct Debit*'),'Direct Debit',
    If(WildMatch(billing_group_description,'*Direct Pay*'),'Direct Payer',
    If(WildMatch(billing_group_description,'*Deceased*'),'Deceased Members','Payroll Group'))) as [Paying Type];

SQL SELECT *
FROM paragonreporting.dbo.group_key_full_by_branch
WHERE rundate > '01-01-2025';

INNER JOIN (Payments)
LOAD membership_id,
    memship_status,
    Date(Floor(effective_termination_date)) as TerminationDate,
    Date(Floor(entry_term_date)) as EntryTerminationDate;
SQL SELECT membership_id, memship_status, effective_termination_date, entry_term_date
FROM paragonreporting.dbo.memship;

OUTER JOIN (Payments)
LOAD group_id as [Group ID],
    tpt_period as [No Periods], 
    description as [Period Description];
SQL  SELECT group_id, bg.billing_freq, tpt_period, tpt_period_by_day, tpt_period_by_week, bf.description
FROM billing_group as bg join billing_freq as bf on bg.billing_freq = bf.billing_freq;

Period:
LOAD membership_id,
RUNDATE,
If(Match([Period Description],'Weekly'), date(date_paidto+7*[No Periods]),
If(Match([Period Description],'Fortnightly'), date(date_paidto+14*[No Periods]),
If(Match([Period Description],'Monthly'), AddMonths(date_paidto,[No Periods]),
date(date_paidto)))) as TPT_DATE
RESIDENT Payments;

LEFT JOIN (Payments)
LOAD * RESIDENT Period;

DROP TABLE Period;

Payments2:
LOAD *,
If(TPT_DATE >= RUNDATE, 'Advance','Arrears') as [Advance/Arrears Flag],
If(TPT_DATE < RUNDATE, 1, 0) as arrears_flag,
membership_id & '|' & MonthStart(RUNDATE) as MbrArrearsKey,
MonthStart(RUNDATE) as arrears_month
RESIDENT Payments;

DROP TABLE Payments;
RENAME TABLE Payments2 TO Payments;

Payments3:
LOAD
    membership_id&'|'&arrears_month 											as MbrArrearsKey,
    if(arrears_flag=1 and Previous(arrears_flag)=1 and Previous(membership_id)=membership_id,
       Peek('consec_months')+1, 
       if(arrears_flag=1,1,0)) 													as consec_months
Resident Payments
Order By membership_id, arrears_month;

Payments4:
LOAD *,
If(MonthName(TerminationDate) = arrears_month,'Termination Month Flag','Did not Term this month') as [Termination Month Flag],
if(EntryTerminationDate-TerminationDate>=60,'60 days backdated') as [60 days backdated]

RESIDENT Payments;

DROP TABLE Payments;
RENAME TABLE Payments4 TO Payments;

LEFT JOIN (Payments)
LOAD
    membership_id & '|' & MonthStart(RUNDATE) as MbrMonthKey,

    If(
        membership_id = Previous(membership_id)
        and [Paying Type] <> Previous([Paying Type]),

        If([Paying Type] = 'Direct Payer',
            'Changed From DD to DP',

        If([Paying Type] = 'Direct Debit',
            'Changed From DP to DD')),

    'Did not Change'
    ) as PaymentChange

RESIDENT Payments
ORDER BY membership_id, RUNDATE;


Dishonours:
LOAD 
    membership_id & '|' & MonthStart(create_datetime) as MbrMonthKey,
    Count(description) as CountofDishonours,
    'Dishonour Member' as [Dishonour Flag]
GROUP BY 
    membership_id, 
    MonthStart(create_datetime);

SQL SELECT r.membership_id,r.receipt_id,rmt.description,r.receipt_amount,r.create_datetime
FROM receipt AS r
JOIN receipt_method AS rm ON r.receipt_link_id = rm.receipt_link_id
LEFT JOIN receipt_method_type AS rmt ON rm.receipt_method_type = rmt.receipt_method_type
WHERE r.create_datetime >= '2025-01-01' AND rmt.description = 'Dishonour';

Dishonour2:
LOAD MbrMonthKey,
if(CountofDishonours = 1, 'Dishonour 1', 
	if(CountofDishonours > 1,'Dishonour >1','No Dishonour')) as [Dishonour Type]
Resident Dishonours;
Drop Table Dishonours;
Rename Table Dishonour2 to Dishonours;

CommsDetail:
load membership_id,
first_name,
surname,
detailM,
detailE,
no_contact;
SQL select m.membership_id, pc.first_name, pc.surname, pc.detailE, 
pc.detailM, ma.no_contact
from memship as m 
left outer join PersonContact as pc on m.membership_id = pc.membership_id
left outer join memship_app as ma on pc.membership_id = ma.membership_id
where pc.relationship = 1;

join (CommsDetail)
LOAD membership_id,
	postal_preference,
    email_address,
    "App Registered";
SQl SELECT 
    pm.membership_id,
    ws.main_ref_id AS person_id, 
    ws.postal_preference,
	ws.email_address, 
    ws.last_login_date, 
    ws.account_active,
    ws.login_times,
    CASE 
        WHEN ws.account_active IS NOT NULL THEN 'Yes' 
        ELSE 'No' 
    END AS 'App Registered'
FROM 
    web_security AS ws 
INNER JOIN 
    person_membership AS pm 
    ON ws.main_ref_id = pm.person_id
WHERE 
    ws.main_ref_type = 'P' 
    AND ws.create_datetime = (
        SELECT 
            MAX(w.create_datetime) 
        FROM 
            web_security AS w 
        WHERE 
            ws.main_ref_id = w.main_ref_id 
            AND w.main_ref_type = 'P'
    ) 
    AND pm.relationship = 1;
    
Flags:
load membership_id,
if(isnull([App Registered]),'No Not App Registered','App Registered')		as [App Reg Flag],
if(len(detailE )<3,'No Email','Email') 										as [Email Flag],
if(len(detailM )<3,'No Mobile','Mobile')									as [Mobile Flag],
if(postal_preference = 'E', 'Email',
if(no_contact = 'Y','Post',
if(len(detailE )<3,'Post','Email')))										as [POSTAL PREF]
Resident CommsDetail;

Notes:
load main_ref_id 		as membership_id,
	note_text 			as NoteText,
    create_datetime 	as [Note Create Date],
    srdesc 				as [SubRef Description],
    ssrdesc				as [SubSubRef Description];
SQL select n.main_ref_id, n.note_text, n.create_datetime, sr.description as srdesc, ssr.description as ssrdesc
	from note as n 
	join sub_ref_type as sr  on n.sub_ref_type_id = sr.sub_ref_type_id
	left join sub_sub_ref_type as ssr on n.sub_sub_ref_type_id = ssr.sub_sub_ref_type_id
	where sr.description in ('Phone Call','Arrears','Admin-NoContact')
	and n.main_ref_type = 'M';

MasterCalendar:
LOAD
    RUNDATE,
    Year(RUNDATE) as Year,
    Month(RUNDATE) as Month
RESIDENT Payments;

EXIT SCRIPT;

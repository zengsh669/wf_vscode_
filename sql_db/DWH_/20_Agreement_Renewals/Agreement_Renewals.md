# Agreement Renewals

Qlik load script for the "Agreement Renewals" app.

```qlik
SET ThousandSep=',';
SET DecimalSep='.';
SET MoneyThousandSep=',';
SET MoneyDecimalSep='.';
SET MoneyFormat='$#,##0.00;-$#,##0.00';
SET TimeFormat='h:mm:ss TT';
SET DateFormat='D/M/YYYY';
SET TimestampFormat='D/M/YYYY h:mm:ss[.fff] TT';
SET FirstWeekDay=6;
SET BrokenWeeks=1;
SET ReferenceDay=0;
SET FirstMonthOfYear=1;
SET CollationLocale='en-AU';
SET CreateSearchIndexOnReload=1;
SET MonthNames='Jan.;Feb.;Mar.;Apr.;May;Jun.;Jul.;Aug.;Sep.;Oct.;Nov.;Dec.';
SET LongMonthNames='January;February;March;April;May;June;July;August;September;October;November;December';
SET DayNames='Mon.;Tue.;Wed.;Thu.;Fri.;Sat.;Sun.';
SET LongDayNames='Monday;Tuesday;Wednesday;Thursday;Friday;Saturday;Sunday';
SET NumericalAbbreviation='3:k;6:M;9:G;12:T;15:P;18:E;21:Z;24:Y;-3:m;-6:μ;-9:n;-12:p;-15:f;-18:a;-21:z;-24:y';

Agent:
LOAD
    group_id								as [Agent ID],
    group_type,
    description								as [Agency],
    date(floor(commencement_date))          as [Commencement Date],
    date(floor(termination_date))			as [Expiry Date], 
    num(grp_discount_amount/100, '0%')						as [Discount Amount]
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_Grouping.qvd]
(qvd)
Where group_type = 'A';


ExpiringAgreement:
LOAD *,
if(Wildmatch([Agreement Status],'Expiring*','Check*'),'NPrint')	as [NPrint Flag];
LOAD *,
 if(isnull([Expiry Date]), 'Check Expiry Date',
	if(today() - [Expiry Date] < -182.64, 'Current', 
    if(today() - [Expiry Date] > 0, 'Expired', 
    if((today() + 30.44) -[Expiry Date] > 0, 'Expiring in 1 Month',
    if((today() + 45.66) - [Expiry Date] > 0, 'Expiring in 45 Days',
    if((today() + 60.88) - [Expiry Date] > 0, 'Expiring in 2 Months',
    if((today() + 91.32) - [Expiry Date] > 0, 'Expiring in 3 Months',
    if((today() + 121.76) - [Expiry Date] > 0, 'Expiring in 4 Months',
    if((today() + 152.20) - [Expiry Date] > 0, 'Expiring in 5 Months',
    if((today() + 182.64) - [Expiry Date] > 0, 'Expiring in 6 Months','Ok')))))))))) 			as [Agreement Status]
Resident Agent;
Drop Table Agent;
Rename Table ExpiringAgreement to Agent;

LEFT JOIN(Agent)
LOAD
    group_id as [Agent ID],
    description as [Agent Name],
    Date(floor(commencement_date)) as [Commencement Date],
    IF(ISNULL(termination_date), 'Active', Date(floor(termination_date))) as [Termination Date],
    create_operator,
    Date(floor(create_datetime)) as [Create Date],
    update_operator,
    Date(floor(update_datetime)) as [Update Date],
    MonthName(create_datetime) 	as [Create Monthyear]
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_Grouping.qvd]
(qvd)

WHERE
    (MonthStart(create_datetime) <= MonthEnd(Today()) AND MonthEnd(create_datetime) >= MonthStart(Today()))
    OR
    (MonthStart(update_datetime) <= MonthEnd(Today()) AND MonthEnd(update_datetime) >= MonthStart(Today()))
    AND group_type = 'A' AND description <> 'No Agency';

Left Join (Agent) 
LOAD
    group_id							as [Agent ID],
    membership_id,
    Date(floor(termination_date))		as [Member Agent Term Date],
    Date(floor(commencement_date)) 		as [Member Agent Commencement Date]
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_MemberAgent.qvd]
(qvd);

Left join (Agent) 
LOAD
    membership_id,
    memship_status,
    date(floor(date_paidto))			as [Current PTD]
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_Memberships.qvd]
(qvd);

LIB CONNECT TO 'rpsqlrp01 - paragonreporting';
Left join (Agent) 
LOAD "membership_id",
    "person_id",
	[person_id]&'-'&membership_id 					as [Ortto Key],    
    surname as [Main Member Surname];
SQL SELECT *
FROM paragonreporting.dbo.PersonContact
WHERE "relationship" = 1;

LIB CONNECT TO 'rpsqlrp01 - paragonreporting';
Left join (Agent) 
LOAD "membership_id",
    "form_id"											  as [Form ID],
    "create_datetime",
    If(Floor([create_datetime]) >= Today()-60,'Yes','No') as [Has Form Generated Last 60 Days];
SQL SELECT 
	"membership_id",
    "form_id",
    "create_datetime"
FROM paragonreporting.dbo.MemberCorrespondance
Where form_id in ('9114','9115');


LIB CONNECT TO 'rpsqlrp01 - paragonreporting';
Left join (Agent)
LOAD "membership_id",
    "receipt_amount"						as [LatestReceiptAmount],
    discount_amount							as [DiscountOnLatestReceipt],
    discount_percent_used					as [Discount%OnLatestReceipt];
SQL  SELECT r.membership_id,
    r.receipt_amount,
	r.discount_amount, 
	r.discount_percent_used
   from receipt  as r
				Where     (r.receipt_id = (Select MAX(receipt_id)
				From receipt       
					Where (membership_id = r.membership_id) and receipt_amount > '0.00'));
                    
Left join (Agent)
LOAD
    membership_id,
//    cover_type,
//    description																												as [Cover],
    Product_Description									as [Product Description]
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_MemberCover.qvd]
(qvd);   

Left join (Agent)
LOAD
    membership_id,
    description																												as [Billing Frequency]
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_MemberPaymentFrequencyLatest.qvd]
(qvd);

Left join (Agent)
LOAD
	membership_id,
    group_id																												as [Group ID],
    description																												as [Group Description],
	date(floor(commencement_date))																							as [Billing Group Commencement Date],
    membership_group_version
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_MemberGroup.qvd]
(qvd);


Left join (Agent)
LOAD
    "Agent ID",
    'Exclude' as [Exlude_FlagTmp]
FROM [lib://Manual Data (prdqs01_atobi)/Agreement_Renewals_App/agencies_to_exclude_(March_2026).xlsx]
(ooxml, embedded labels, table is Sheet1);

AgentSummary_ExcludeFlag:
LOAD *,
if(Wildmatch([Exlude_FlagTmp],'Exclude'),'Exclude', 'Include')	as [Exclude_Flag]
Resident Agent;
Drop Table Agent;
Rename Table AgentSummary_ExcludeFlag to Agent;

AgentFlagged:
LOAD*,
	IF([Agreement Status] = 'Expired'
    AND IsNull([Member Agent Term Date]), 'Flag', 'OK') AS [Expired Agreement Active Member Agent Flag]
Resident Agent;
Drop Table Agent;
Rename Table AgentFlagged to Agent;

DetrimentalComms:
LOAD*,
	IF([Agreement Status] = 'Expiring in 45 Days'
    AND [Has Form Generated Last 60 Days] = 'Yes', 'Flag', 'OK') AS [Detrimental Comms Flag]
Resident Agent;
Drop Table Agent;
Rename Table DetrimentalComms to Agent;

MembersAddedWithin60DaysOfTermination:
LOAD *,
    IF(memship_status = 'A'
        AND NOT IsNull([Expiry Date])
        AND NOT IsNull([Member Agent Commencement Date])
        AND [Member Agent Commencement Date] >= [Expiry Date] - 60
        AND [Member Agent Commencement Date] <= [Expiry Date],'Flag','OK') AS [Member Added Within 60 Days]
Resident Agent;
Drop Table Agent;
Rename Table MembersAddedWithin60DaysOfTermination to Agent;
```

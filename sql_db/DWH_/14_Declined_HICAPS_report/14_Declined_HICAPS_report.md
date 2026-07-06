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

LET vFinancialYearStart = Date(MonthStart(AddMonths(Today(), -24)),'YYYY-MM-DD');
LET vFinancialYearEnd = Date(MonthEnd(AddMonths(Today(), 24)),'YYYY-MM-DD');

// Section Access;
// Access:
// load * inline [
// ACCESS,         USERID,                             GROUP,					OMIT
// ADMIN,          WESTFUND\QLIKSENSE,					*,
// ADMIN,          INTERNAL\SA_SCHEDULER,				*,
// ADMIN,          PRDQS01\ATOBI,                      *,
// ADMIN,          WESTFUND\BLAKERS,                   *,
// ADMIN,          WESTFUND\HICKSONS,                  *,
// ADMIN,          WESTFUND\WHITEHOUSEK,       		*,
// ADMIN,          WESTFUND\RUSSELLM,                  *,
// ADMIN,          WESTFUND\STAINESA,                  *,
// USER, 			*,									SG_QLIK_EXECUTIVE,
// USER,			*,									SG_QLIK_HEALTHCARE,
// USER, 			*, 									SG_QLIK_COMPLIANCE,
// ];

// Section Application;

LIB CONNECT TO 'rpsqlrp01 - paragonreporting';
GroupingMap:
Mapping
Load
	group_id,
    description;
SQL SELECT *
FROM paragonreporting.dbo."grouping"
where group_type = 'C';

SubRefMap:
Mapping

LOAD description,
    "sub_ref_type_id";
SQL SELECT description,
    "sub_ref_type_id"
FROM paragonreporting.dbo."sub_ref_type";

Claim:
LOAD "claim_id"													as [Claim ID],
	"claim_line_id"												as [Claim line ID],
    "membership_id"												as [Membership ID],
    Date(Floor("status_date"))									as [Status Date],
    MonthName("status_date")									as [Status Date Month Year],
    "create_operator"											as [Create Operator];
SQL SELECT *
FROM paragonreporting.dbo."claim_line"
where "status_date"  >= '$(vFinancialYearStart)' AND "status_date" <= '$(vFinancialYearEnd)'
and ("create_operator"='HICAPS' OR "create_operator"='IBA'); 


LIB CONNECT TO 'rpsqlrp01 - paragonreporting';
Inner Join (Claim)
LOAD "claim_id"													as [Claim ID],
    "claim_line_id"												as [Claim line ID],
    "assessing_code_type"										as [Assessing Code type],
    "item_number"												as [Item Number],
//   not(wildmatch("item_number",'662', '611','612','631','632','651','652','661','671','672', 'coating', 'noncoating'))				as [Item excluding coating],
    "service_type"												as [Service type],
     "hicaps_assessing_code"									as [HICAPS assessing code],
    "receipt_message"											as [ReceiptMessage];
SQL SELECT cg.claim_id, cg.claim_line_id, cg.assessing_code_type, cg.item_number, cg.service_type, ha.receipt_message, ha.hicaps_assessing_code 
FROM claim_generalitem as cg left join hicaps_assessing_code as ha on cg.assessing_code_type = ha.assessing_code_type
where cg.assessing_code_type IS  NOT  NULL AND NOT (cg.item_number LIKE '6%' AND cg.service_type = 'OPTICAL');
                    

 let vStat = NoOfRows('Claim');
Load * Inline [
Stat, Rows, Comment
Claim1 Table, '$(vStat)', Claim1 Table];

// Left Join (Claim)
// LOAD "group_id"											as [Group ID],
//     description											as [Branch Description],
//     "membership_id"										as [Membership ID];
// SQL SELECT *
// FROM paragonreporting.dbo.MemberBranch;

Inner Join (Claim)
LOAD "claim_id"										as [Claim ID],
    "claim_line_id"									as [Claim line ID],
    Applymap('GroupingMap',"mem_branch_at_claim",'MISSING')				as [Branch];
SQL SELECT "claim_id",
    "claim_line_id",
    "mem_branch_at_claim"
FROM paragonreporting.dbo.ClaimDetailsAtService
Where "status_date"  >= '$(vFinancialYearStart)' AND "status_date" <= '$(vFinancialYearEnd)';

 let vStat = NoOfRows('Claim');
Load * Inline [
Stat, Rows, Comment
Claim2 Table, '$(vStat)', Claim2 Table];


join (Claim)
LOAD
// LOAD "note_id",
    "main_ref_type"							as [Main Reference Type],
    "sub_ref_type"							as [Reference Type],
    "main_ref_id"							as [Membership ID],
//     "sub_ref_id"							as [Sub Reference ID],
//     priority,
//     "priority_end_date",
//    Date(Floor( "note_end_date"))			as [Note end date],
//     "note_text",
   "create_operator" 						as [Reference Create Operator],
    Date(Floor("create_datetime"))			as [Reference Create Date],
//     "update_operator",
//     "update_datetime",
//     "timestamp",
//     delta,
//     recipient,
//     "note_received",
//     "sub_sub_ref_type",
//     "wakeup_time",
//     "privacy_flag",
    ApplyMap('SubRefMap', "sub_ref_type_id",'CheckNotes')		as [Reference description],
    "sub_sub_ref_type_id";
//     "receipient_1";
SQL SELECT *
FROM paragonreporting.dbo.note
where sub_ref_type = 'L' or sub_ref_type_id = 76;

 let vStat = NoOfRows('Claim');
Load * Inline [
Stat, Rows, Comment
Claim4 Table, '$(vStat)', Claim4 Table];

Inner Join (Claim) 
LOAD
    membership_id					as [Membership ID],
    cover_version,
    cover_type,
    status_flag,
    cover_state,
    cover_from_date,
    termination_date,
    description						as [Cover],
    FixCode,
    Product_Description
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_MemberCover.qvd]
(qvd);

 let vStat = NoOfRows('Claim');
Load * Inline [
Stat, Rows, Comment
Claim5 Table, '$(vStat)', Claim5 Table];

ReceiptMessage:
Load *,
if(isnull([ReceiptMessage]), 'No', [ReceiptMessage]) 	as [Receipt Message]
Resident Claim;
drop table Claim;
drop field [ReceiptMessage];
Rename table ReceiptMessage to Claim;
```

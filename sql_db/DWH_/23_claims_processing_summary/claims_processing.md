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
SET MonthNames='Jan.;Feb.;Mar.;Apr.;May;Jun.;Jul.;Aug.;Sep.;Oct.;Nov.;Dec.';
SET LongMonthNames='January;February;March;April;May;June;July;August;September;October;November;December';
SET DayNames='Mon.;Tue.;Wed.;Thu.;Fri.;Sat.;Sun.';
SET LongDayNames='Monday;Tuesday;Wednesday;Thursday;Friday;Saturday;Sunday';
SET NumericalAbbreviation='3:k;6:M;9:G;12:T;15:P;18:E;21:Z;24:Y;-3:m;-6:μ;-9:n;-12:p;-15:f;-18:a;-21:z;-24:y';

set CreateSearchIndexOnReload = 1;

Let vStartDate = Date(MonthStart(AddYears(today(), -1), -1));

Let vLastWeek =  WeekEnd(Today()-1);

trace $(vStartDate);

OperatorMap:
Mapping
LOAD
    oper_name,
    first_name&' '&surname
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_Operator.qvd]
(qvd);

ItemMap:
Mapping
LOAD
    item_number,
    description
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_item.qvd]
(qvd);

OperatorMapping:
Mapping
LOAD
    first_name&' '&surname 			as [Final Operator],
    branch_group_id
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_Operator.qvd]
(qvd);

//LIB CONNECT TO 'rpsqlrp01 - paragonreporting';
LIB CONNECT TO 'prdsql05.westfund.com.au-ods - paragon';

ClaimStatusTypeMap:
Mapping
LOAD
    claim_status_type,
    description;
SQL SELECT "claim_status_type",
    description
FROM paragon.dbo."claim_status_type";

PersonMap:
Mapping
LOAD
    person_id,
    first_name&' '&surname;
SQL SELECT 
	"person_id",
    "first_name",
    surname
FROM paragon.dbo."person";

ProviderMap:
Mapping
LOAD
    provider_id,
    provider_name;
SQL SELECT "provider_id",
    "provider_name"
FROM paragon.dbo."provider";

BucketMap:
Mapping
LOAD "claim_alloc_reason_id",
    description;
SQL SELECT "claim_alloc_reason_id",
    description
FROM paragon.dbo."claim_alloc_reason";

ProviderClaimStatusTypeMap:
Mapping
LOAD "provider_claim_status_type",
    description;
SQL SELECT "provider_claim_status_type",
    description
FROM paragon.dbo.provider_claim_status_type;

BucketTypeMap:
Mapping
LOAD "claim_id",
    claim_type_flag;
SQL SELECT "claim_id",
    "claim_type_flag"
FROM paragon.dbo."claim"
where create_datetime > '$(vStartDate)';

DepartmentMap:
Mapping
LOAD "department_id",
    description;
SQL SELECT "department_id",
    description
FROM paragon.dbo.department;

MembershipIDMap:
Mapping
LOAD distinct "claim_id",
    			membership_id;
SQL SELECT "claim_id",
    "membership_id"
FROM paragon.dbo."claim"
where create_datetime > '$(vStartDate)';

ClaimChannelMap:
Mapping
LOAD distinct claim_id,
	category;
SQL SELECT "claim_id",
   category
FROM paragon.dbo."ClaimsByChannel";

GroupingMap:
Mapping
LOAD
    group_id							as Branch,
    description
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_Grouping.qvd]
(qvd);

PersonNameMap:
MAPPING
LOAD person_id,
     first_name & ' ' & surname
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_Person.qvd] (qvd);

//LIB CONNECT TO 'rpsqlrp01 - paragonreporting';
LIB CONNECT TO 'prdsql05.westfund.com.au-ods - paragon';

TillMap:
Mapping
LOAD distinct "claim_id",
    			till_id;
SQL SELECT "claim_id",
    "till_id"
FROM paragon.dbo."claim"
where create_datetime > '$(vStartDate)';

TillNameMap:
Mapping
LOAD till_id,
    description;
SQL SELECT t.till_id,
    g.description
FROM paragon.dbo."till" as t 
left join grouping as g on g.group_id = t.group_id;

ClaimAttachment:
Mapping
LOAD ClaimKey,
    letter_subject;
SQL Select Replace( mc.ClaimKey1,' ', '') as ClaimKey, letter_subject
From 
(Select --SUBSTRING(letter_subject, LOCATE('#', letter_subject) + 1) AS claim_number, 
 SUBSTRING(letter_subject, CHARINDEX('# ', letter_subject) + 1, LEN(letter_subject)) as ClaimKey1,
* 
From MemberCorrespondance
Where form_category = '3') as mc;

//LIB CONNECT TO 'rpsqlrp01 - paragonreporting';
LIB CONNECT TO 'prdsql05.westfund.com.au-ods - paragon';

Claims:
LOAD*,
IF(Wildmatch([ClaimChannel], 'ECLAIMS', 'MOBILE'), 'Online', [ClaimChannel])												as [Claim Channel];
LOAD
    claim_id																												as [Claim ID],
        ApplyMap('TillNameMap', ApplyMap('TillMap', claim_id, 'No Till'), 'No Till')										as [Till Location],
        ApplyMap('ClaimAttachment', claim_id, 'No Attachment')															   	as [Attachment Subject],
    if(wildmatch(create_operator,'*-*'),'ECLAIMS', ApplyMap('ClaimChannelMap',claim_id,'Top Up Claims (System Generated)'))	as [ClaimChannel],
    ApplyMap('MembershipIDMap',claim_id,'no member')																		as [Membership ID],
    claim_status_version,
    applymap('ClaimStatusTypeMap',claim_status_type,'MISSING')																as Status,
    date(floor(status_date))																								as [Date],
    year(status_date)																										as [Year],
    hour(status_date)																										as [Hour],
    day(status_date)                                                                                                        as [Day],
    monthname(date(floor(status_date)))																						as [MonthYear],
    Weekend(status_date)																									as [Week End],
    Date(Floor(status_date))                                                                                                as [Status Date],
    if(wildmatch(create_operator,'*-*'),'ECLAIMS',create_operator)															as [Create Operator],
    if(isnum(if(applymap('ClaimStatusTypeMap',claim_status_type,'MISSING') = 'Verified' 
    	and len(update_operator>0),update_operator,
        	if(applymap('ClaimStatusTypeMap',claim_status_type,'MISSING') = 'Verified' 
    	and len(update_operator>0),update_operator,create_operator))),'Web/Mobile Claim',
        	if(applymap('ClaimStatusTypeMap',claim_status_type,'MISSING') = 'Verified' 
    	and len(update_operator>0),update_operator,
        	if(applymap('ClaimStatusTypeMap',claim_status_type,'MISSING') = 'Verified' 
    	and len(update_operator>0),update_operator,create_operator)))														as [Claim Operator],
        
//     if(applymap('ClaimStatusTypeMap',claim_status_type,'MISSING') = 'Verified' 
//     			and len(Applymap('OperatorMap',(update_operator)>0)),update_operator,create_operator)					as [Claim Operator2],
        
        
  	 if(applymap('ClaimStatusTypeMap',claim_status_type,'MISSING') = 'Received and Logged',date(floor(status_date))) 						as [Received Status Date],
     if(applymap('ClaimStatusTypeMap',claim_status_type,'MISSING') = 'Received and Logged',date(floor(status_date)))						as [Received Year],
	 if(applymap('ClaimStatusTypeMap',claim_status_type,'MISSING') = 'Paid',date(floor(status_date))) 										as [Paid Status Date],
 	 if(wildmatch(applymap('ClaimStatusTypeMap',claim_status_type,'MISSING'),'Manually Verified', 'Verified'),date(floor(status_date))) 	as [Verified Status Date],
     if(wildmatch(applymap('ClaimStatusTypeMap',claim_status_type,'MISSING'),'Manually Verified', 'Verified'),'Verified') 					as [Verified StatusCheck],
     create_datetime,
     IF(WildMatch(update_operator, '*-*'), 'ECLAIMS', update_operator) as update_operator,
     update_operator																										as [Update Operator],
     //ApplyMap('OperatorMapping',"update_operator",'MISSING')												as [Operator Branch],
     update_datetime;
     SQL SELECT *
FROM paragon.dbo."claim_status"
where status_date > '$(vStartDate)';

let vStat = NoOfRows('Claims');
Load * Inline [
Stat, Rows, Comment
Claims Table, '$(vStat)', Claims Table];

Concatenate (Claims)
LOAD "provider_claim_id"																									as [Claim ID],
    "claim_status_version",
    applymap('ProviderClaimStatusTypeMap',"provider_claim_status_type",'Missing')											as [Status],
    date(floor("status_date"))																								as [Date],
    "status_date",
    "create_operator",
//        	if(applymap('ProviderClaimStatusTypeMap',provider_claim_status_type,'MISSING') = 'Verified' 
//    	and len(update_operator>0),update_operator,create_operator),
        	if(applymap('ProviderClaimStatusTypeMap',provider_claim_status_type,'MISSING') = 'Verified' 
    	and len(update_operator>0),update_operator,create_operator)															as [Claim Operator],
	if(applymap('ProviderClaimStatusTypeMap',provider_claim_status_type,'MISSING') = 'Received',date(floor(status_date))) 	as [Received Status Date],
	if(applymap('ProviderClaimStatusTypeMap',provider_claim_status_type,'MISSING') = 'Paid',date(floor(status_date))) 		as [Paid Status Date],
 	if(wildmatch(applymap('ProviderClaimStatusTypeMap',provider_claim_status_type,'MISSING'),'*Sent to Medicare*'),date(floor(status_date))) as [Verified Status Date],
    "create_datetime",
    IF(WildMatch(update_operator, '*-*'), 'ECLAIMS', update_operator) as update_operator,
    "update_datetime";
SQL SELECT *
FROM paragon.dbo."provider_claim_status"
where status_date > '$(vStartDate)';

let vStat = NoOfRows('Claims');
Load * Inline [
Stat, Rows, Comment
Claims1 Table, '$(vStat)', Claims1 Table];

Left Join (Claims)
// Verified Claims
LOAD
    claim_id																												as [Claim ID],
    ApplyMap('MembershipIDMap',claim_id,'no member')																		as [Membership ID],
    applymap('ClaimStatusTypeMap',claim_status_type,'MISSING')																as VerifiedStatus,
    update_operator																											as [Verified Operator],
 	 if(wildmatch(applymap('ClaimStatusTypeMap',claim_status_type,'MISSING'),'Manually Verified', 'Verified'),date(floor(status_date))) 			as [VerifiedStatusDate], 
      if(wildmatch(applymap('ClaimStatusTypeMap',claim_status_type,'MISSING'),'Manually Verified', 'Verified'),date(floor(status_date))) 			as [Verified Status Date]
     ;
     SQL SELECT 
    CASE 
        WHEN COALESCE(update_operator, create_operator) LIKE '%-%' 
        THEN SUBSTRING(COALESCE(update_operator, create_operator), 0, CHARINDEX('-', COALESCE(update_operator, create_operator), 0)) 
        ELSE COALESCE(update_operator, create_operator) 
    END AS 'update_operator', 
claim_id,
claim_status_type,
status_date
FROM paragon.dbo."claim_status"
where status_date > '$(vStartDate)'
and claim_status_type in ('V');

Left Join (Claims)
// Received Claims
LOAD
    claim_id																												as [Claim ID],
    ApplyMap('MembershipIDMap',claim_id,'no member')																		as [Membership ID],
    applymap('ClaimStatusTypeMap',claim_status_type,'MISSING')																as AssessedStatus,
    update_operator																											as [Assessed Operator],
  	 if(applymap('ClaimStatusTypeMap',claim_status_type,'MISSING') = 'Assessed but not Verified',date(floor(status_date))) 	as [AssessedStatusDate];
     SQL SELECT 
case when update_operator like '%-%' then SUBSTRING(update_operator, 0, charindex('-', update_operator, 0)) else update_operator end as 'update_operator', 
claim_id,
claim_status_type,
status_date
FROM paragon.dbo."claim_status"
where status_date > '$(vStartDate)'
and claim_status_type in ('A');

Left Join (Claims)
// Paid Claims for Online
LOAD
    claim_id																												as [Claim ID],
    ApplyMap('MembershipIDMap',claim_id,'no member')																		as [Membership ID],
    applymap('ClaimStatusTypeMap',claim_status_type,'MISSING')																as PaidStatus,
    IF(ISNUM(update_operator), update_operator, 'Not Online')																as [Paid Operator],
 	 if(wildmatch(applymap('ClaimStatusTypeMap',claim_status_type,'MISSING'),'*Paid*'),date(floor(status_date))) 			as [PaidStatusDate],
     IF(ISNUM(create_operator), create_operator, 'Not Online') as [PaidCreateOperator];
     SQL SELECT 
case when update_operator like '%-%' then SUBSTRING(update_operator, 0, charindex('-', update_operator, 0)) else update_operator end as 'update_operator', 
case when create_operator like '%-%' then SUBSTRING(create_operator, 0, charindex('-', create_operator, 0)) else create_operator end as 'create_operator',
claim_id,
claim_status_type,
status_date
FROM paragon.dbo."claim_status"
where status_date > '$(vStartDate)'
and claim_status_type in ('P');

OperatorCheck:
LOAD*,
If([AssessedOperatorCheck] <> [VerifiedOperatorCheck] 
and [VerifiedOperatorCheck] <> 'No Operator'
and [AssessedOperatorCheck] <> 'No Operator', 'Verified By Operator') 																							as [Verified Check];
LOAD *,
if(match(Status,'Verified','Cancelled','Assessed but not Verified' ), applymap('OperatorMap',if(len(update_operator>0), update_operator,[ClaimOperator])))		as [Final Operator],
if(match(AssessedStatus, 'Assessed but not Verified'),applymap('OperatorMap',[AssessedOperator]),'No Operator')															as [AssessedOperatorCheck],
if(match(VerifiedStatus, 'Verified'), applymap('OperatorMap',[VerifiedOperator]), 'No Operator')													as [VerifiedOperatorCheck];
 //ApplyMap('OperatorMapping',"update_operator",'MISSING')												as [Operator Branch]
LOAD*,
IF(isnull([Verified Operator]), 'No Operator', [Verified Operator])																					as [VerifiedOperator],
IF(isnull([Assessed Operator]), 'No Operator', [Assessed Operator])																					as [AssessedOperator];
LOAD*,
IF(Wildmatch([Claim Operator], '*-*'), 'ECLAIMS', [Claim Operator]) 																				as [ClaimOperator],
IF([PaidCreateOperator]=[Paid Operator] and [PaidCreateOperator] <> 'Not Online' and [Paid Operator] <> 'Not Online', 'Untouched', 'Touched') 		as [Online Claim Touched/Untouched] 
Resident Claims;
Drop Table Claims;
Rename Table OperatorCheck to Claims;

Left Join (Claims)
LOAD distinct
	"provider_claim_id"																										as [Claim ID],
    description																												as [MaxClaimStatusProvider],
    create_operator																											as [MaxStatusProviderCreateOperator],
    status_date																												as [MaxStatusDateProvider] ;
SELECT mg.provider_claim_id, mg.provider_claim_status_type, mg.claim_status_version, mg.create_operator, mg.status_date, pt.description
FROM	dbo.provider_claim_status AS mg join
		dbo.provider_claim_status_type as pt on mg.provider_claim_status_type = pt.provider_claim_status_type
WHERE	mg.claim_status_version in 
					(	
						select MAX(claim_status_version) AS EXPR2 
						FROM dbo.provider_claim_status as mg2 
						WHERE (mg2.provider_claim_id = mg.provider_claim_id) and (mg2.status_date <= GETDATE())
					)
and mg.status_date > '$(vStartDate)'                    ;

let vStat = NoOfRows('Claims');
Load * Inline [
Stat, Rows, Comment
Claims2 Table, '$(vStat)', Claims2 Table];

Left Join (Claims)
LOAD distinct 
	"claim_id"																												as [Claim ID],
     description																											as [MaxClaimStatusOther],
     create_operator																										as [MaxStatusCreateOperatorOther],
     status_date																												as [MaxStatusDateOther];
SELECT mg.claim_id, mg.claim_status_type, mg.claim_status_version, mg.create_operator, mg.status_date, pt.description
FROM	dbo.claim_status AS mg join
		dbo.claim_status_type as pt on mg.claim_status_type = pt.claim_status_type
WHERE	mg.claim_status_version in 
					(	
						select MAX(claim_status_version) AS EXPR2 
						FROM dbo.claim_status as mg2 
						WHERE (mg2.claim_id = mg.claim_id) and (mg2.status_date <= GETDATE())
					)
        and mg.status_date > '$(vStartDate)'  ;

let vStat = NoOfRows('Claims');
Load * Inline [
Stat, Rows, Comment
Claims3 Table, '$(vStat)', Claims3 Table];
//**********************************************************************
left Join (Claims)
LOAD
    claim_id																												as [Claim ID],
    if(Applymap('BucketTypeMap',claim_id,'Missing') ='H','Hospital','General')												as [Gen/Hosp Bucket Type],
 	if(match(claim_alloc_reason_id, 1), 'Bucket claims','Allocated Claims') 												as [Gen/Hosp Bucket Claims],
    date(floor(create_datetime))																							as [Gen/Hosp Bucket Claims Lodge Date],
    //date(floor(create_datetime))																							as [Date],
   NetWorkDays(create_datetime,today())																						as [Gen/Hosp Claim Age in Bucket];
SQL SELECT *
FROM paragon.dbo."claim_alloc"
Where create_datetime > '$(vStartDate)';
//************************************************************************
let vStat = NoOfRows('Claims');
Load * Inline [
Stat, Rows, Comment
Claims4 Table, '$(vStat)', Claims4 Table];


Left Join (Claims)
LOAD "provider_claim_id"																									as [Claim ID],
//  "oper_name",
//    "claim_alloc_reason_id",
    'Medical'																												as [Provider Bucket Type],
  	if(match(claim_alloc_reason_id, 2), 'Bucket claims','Allocated Claims') 												as [Provider Bucket Claims],
//     "lodged_time",
//     "start_time",
//     "finish_time",
//     "resolved_flag",
//    "create_operator",
    date(floor(create_datetime))																							as [Provider Bucket Claims Lodge Date],
    NetWorkDays(create_datetime,today())																					as [Provider Claim Age in Bucket];
//    "update_operator",
//    "update_datetime",
//    delta;
SQL SELECT *
FROM paragon.dbo."provider_claim_alloc"
Where create_datetime > '$(vStartDate)';

let vStat = NoOfRows('Claims');
Load * Inline [
Stat, Rows, Comment
Claims Table, '$(vStat)', Claims5 Table];


BringTogether:
Load*, 
NetWorkDays([MaxStatusStatusDate],today())																					as [Held Days];
Load *,
	if(isnull([Gen/Hosp Bucket Type]),[Provider Bucket Type],[Gen/Hosp Bucket Type])										as [Bucket Type],	
	if(isnull([Gen/Hosp Bucket Claims]),[Provider Bucket Claims],[Gen/Hosp Bucket Claims])									as [Bucket Claims],
    if(isnull([Gen/Hosp Bucket Claims Lodge Date]),[Provider Bucket Claims Lodge Date],[Gen/Hosp Bucket Claims Lodge Date])	as [Bucket Claims Lodge Date],
    if(isnull([Gen/Hosp Claim Age in Bucket]),[Provider Claim Age in Bucket],[Gen/Hosp Claim Age in Bucket])				as [Claim Age in Bucket],
    if(isnull([MaxClaimStatusProvider]),[MaxClaimStatusOther],[MaxClaimStatusProvider])										as [MaxStatus],
    if(isnull([MaxStatusProviderCreateOperator]),[MaxStatusCreateOperatorOther],[MaxStatusProviderCreateOperator])			as [MaxStatusCreateOperator],
    if(isnull([MaxStatusDateProvider]),[MaxStatusDateOther],[MaxStatusDateProvider])										as [MaxStatusStatusDate]
Resident Claims;
Drop Table Claims;
Rename Table BringTogether to Claims;

AgeInBucketCohorts:
load * inline [
agemin, agemax, BucketAgeCohort
-10, 	2, 		0-2
3, 		5, 		3-5
6, 		10, 	6-10
11, 	14, 	11-14
15, 	27, 	14-28
28,		1000,	29+
];

left join IntervalMatch ([Claim Age in Bucket]) 
LOAD agemin, agemax
Resident AgeInBucketCohorts;


HeldAgeCohorts:
load * inline [
agemin2, agemax2, HeldAgeCohort
-10, 	2, 		0-2
3, 		5, 		3-5
6, 		10, 	6-10
11, 	14, 	11-14
15, 	28, 	15-28
29,		60,		29-60
61, 	1000, 	61+
];

left join IntervalMatch ([Held Days]) 
LOAD agemin2, agemax2
Resident HeldAgeCohorts;

DaysTilPaid:
Load *,
NetWorkDays([Bucket Claims Lodge Date],[Paid Status Date])																	as [Days to Pay Claim],
NetWorkDays([Bucket Claims Lodge Date],[Verified Status Date])																as [Days to Verify Claim],
if(num([Date]) = num(date(floor(today()))),'Today','Not Today')																as [Today Flag]
Resident Claims;
Drop Table Claims;
Rename Table DaysTilPaid to Claims;


//to get the adjustments
left join (Claims)
LOAD * WHERE [Adjusted Status Date]> '$(vStartDate)' ;
LOAD
    claim_id																												as [Claim ID],
    claim_line_id																											as [Claim Line],
    Applymap('OperatorMap',create_operator,create_operator)																	as [Adj Create Operator],
    create_datetime																											as [Adjustment Date],
    payee_method																											as [Payee Method],
    adjustment_flag,
    claim_type,
    line_status, 
    item_number, 
    status_date                                                                                                             as [Adjusted Status Date],
 //   ApplyMap('ItemMap', item_number, 'Missing')																				as [Item Description], 
 	description 																											as [Item Description],
    service_type																											as [Service Type], 
    fee, 
    benefit, 
    membership_id, 
    Date(floor(service_date))																								as [Service Date], 
    provider_number_id 																										as [Provider Number], 
    provider_name, 
   	Product_Description_at_claim																							as [Product Description], 
    person_id																												as [Person ID], 
    ApplyMap('PersonNameMap',person_id,'Unknown Name')																		as [Person Name], 
    Num_services 																											as [Number of Services],
    Applymap('OperatorMap', update_operator, update_operator)																as [Adjusted Update Operator],
    ;
SQL SELECT cd.claim_id,cd.claim_line_id,cd.provider_number_id,cd.person_id, cd.payee_method,
    cd.service_date,cd.status_date,cd.create_operator,cd.create_datetime,
    cd.line_status,cd.claim_type,cd.service_type,cd.item_number,cd.fee, cd.membership_id,
    cd.benefit,cd.adjustment_flag,p.provider_name,cs.Product_Description_at_claim, cs.person_id, cd.Num_services,
	i.description, cd.service_type, cd.update_operator 
    
FROM ClaimDetailGenAndHosp as cd 
		Left Join provider_number AS pn on cd.provider_number_id = pn.provider_number_id
        Left join provider as p on pn.provider_id = p.provider_id
        Inner Join ClaimDetailsAtService as cs on cd.claim_id = cs.claim_id and cd.claim_line_id = cs.claim_line_id
		Left join item as i on cd.service_type = i.service_type and cd.item_number = i.item_number
Where cd.status_date > '$(vStartDate)'
 ;

Left Join (Claims)
LOAD
	"claim_id"																								as [Claim ID],
     "claim_line_id"																						as [Claim Line ID],
    if(manual_flag = 1, 'Manual Claim','Not Manual Claim')													as [Manual Claim]
    //applymap('ManualBenefitReasonMap',manual_benefit_reason_id,'No Reason')									as [Manual Benefit Reason]
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_Claim_GeneralItem.qvd] (qvd)
Where create_datetime > '$(vStartDate)';

let vStat = NoOfRows('Claims');
Load * Inline [
Stat, Rows, Comment
Claims Table, '$(vStat)', Claims6 Table];

left join (Claims)
LOAD
    membership_id		as [Membership ID],
    Product_Description as [Current Product]
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_MemberCover.qvd]
(qvd);

left join (Claims)
LOAD
    description			as [Current Agent],
    membership_id 		as [Membership ID]
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_MemberAgent.qvd]
(qvd);





AdjustedOperator:
LOAD*,
IF(ISNULL([Adjusted Update Operator]),[Adj Create Operator], [Adjusted Update Operator]) 					as [Adjusted Operator]
Resident Claims;
Drop Table Claims;
Rename Table AdjustedOperator to Claims;

String:
LOAD *,
if(wildmatch(Status,'Verified','Assessed but not Verified','Till Verify','Batched for Medicare (Batch Created)'),'Nprint','Not Nprint')	as [For Daily Nprint],
[Claim ID]&[Claim Line]																										as [Claim ID/Line ID String],
if(match([Final Operator],'Sharp Verify',
'Rebecca Christie',
'Natalie Howard',
'Margaret Slaven',
'Kasandra Anthes',
'Jazmin Melnyk',
'Glenice Sharp',
'Glenda Winterbottom',
'Elizabeth Burnes',
'Dianne Garland',
'Leanne Hawley',
'Lynn Green',
'Ashley Drury',
'Jodie Blackley',
'Brain Groups',
'Amanda Pearce',
'Jaide Vanneste ',
'Mikayla Newcombe',
'Rachel Nelson',
'Jacqueline Page',
'Kallan Phillips',
'Madeline Spice',
'Amanda Robertson'),'Head Office','Care Centres')																				as [HO/Care Centre] 
//if(wildmatch([Final Operator],'*-*'),'ECLAIM', [Final Operator])															as [Final operator]
// ApplyMap('MembershipIDMap',[Claim ID],'No Membership')																		as [Membership ID]
Resident Claims;
Drop Table Claims;
Rename Table String to Claims;

// left join (Claims) 
// LOAD
//     oper_name			as,
//     oper_name,
//     status_flag,
//     branch_group_id
// FROM [lib://ExtractData (prdqs01_atobi)/Paragon_Operator.qvd]
// (qvd);



Branch:
LOAD*,
     ApplyMap('OperatorMapping',[Final Operator])		as [Branch]
Resident Claims;
Drop Table Claims;
Rename Table Branch to Claims;

OperatorBranch:
LOAD*,
    ApplyMap('GroupingMap', [Branch], 'No Assigned Branch') as [Operator Branch]
Resident Claims;
Drop Table Claims;
Rename Table OperatorBranch to Claims;

Audit:
LOAD*,
if(not(wildmatch(MaxStatus,'Verified','Assessed but not Verified','Till Verify','Batched for Medicare (Batch Created)')),'Not Records',
IF(wildmatch([MaxStatus], 'Cancelled'),'Not Records',
If(Wildmatch([Provider Number], 'SUNGLASS'), 'Not Records',
IF([claim_type] <> 'Hospital' and [Provider Number] <> 'TRAVEL', 'Not Records',
if(match([Final Operator], 'Amanda Pearce', 'Dianne Garland', 'Madeline Spice', 'Kallan Phillips'), 'Not Records',
IF(wildmatch([Final Operator], 'Kasandra Anthes', 'Rachel Nelson') and fee > '0.00', 'Not Records', 'Records'))))))	as [For Audit]
Resident Claims;
Drop Table Claims;
Rename Table Audit to Claims;

// Date:
// load Distinct [Date]						as [All Dates]
// Resident Claims;

// Concatenate (Date)
// load Distinct [Bucket Claims Lodge Date]    as [All Dates]
// Resident Claims;


Total:
LOAD distinct
	[Claim ID] 			as [ClaimID],
    [Claim ID/Line ID String] 			as [Claim&LineID],
    [Service Type] as [ServiceType], 
    [Final Operator] 	as [Op],
    'Claims Processed' 	as Type,
    Date 				as [Count Date],
    [Claim ID]&'-'&[Final Operator] as [ClaimKey]
Resident Claims
WHERE WildMatch(Status, 'Assessed but not Verified', 'Batched for Medicare (Batch Created)');// and Not(Wildmatch([Final Operator], 'ECLIPSE')) ;

Concatenate (Total)
LOAD distinct
	[Claim ID] 			as [ClaimID],
    [Claim ID/Line ID String] 			as [Claim&LineID],
        [Service Type] as [ServiceType], 
    [VerifiedOperatorCheck] 	as [Op],
    'Claims Verified' 	as Type,
    Date 				as [Count Date],
    [Claim ID]&'-'&[VerifiedOperatorCheck] as [ClaimKey]
Resident Claims
WHERE WildMatch([Verified StatusCheck], 'Verified');

Concatenate (Total)
LOAD distinct
	[Claim ID] 			as [ClaimID],
    [Claim ID/Line ID String] 			as [Claim&LineID],
        [Service Type] as [ServiceType], 
    [Adjusted Update Operator] 	as [Op],
    'Adjusted/Balanced Claims' 	as Type,
    Date 				as [Count Date],
    [Claim ID]&'-'&[Adjusted Update Operator] as [ClaimKey]
Resident Claims
WHERE WildMatch(adjustment_flag, 'New Line', 'Reversal Line', 'Original Line');

Concatenate (Total)
LOAD distinct
	[Claim ID] 			as [ClaimID],
    [Claim ID/Line ID String] 			as [Claim&LineID],
        [Service Type] as [ServiceType], 
    [Final Operator] 	as [Op],
    'Cancelled Claims' 	as Type,
    Date 				as [Count Date],
    [Claim ID]&'-'&[Final Operator] as [ClaimKey]
Resident Claims
WHERE WildMatch(MaxStatus, '*Cancelled*');

Concatenate (Total)
LOAD distinct
	[Claim ID] 			as [ClaimID],
    [Claim ID/Line ID String] 			as [Claim&LineID],
        [Service Type] as [ServiceType], 
    [Final Operator] 	as [Op],
    'Manual Claims' 	as Type,
    Date 				as [Count Date],
    [Claim ID]&'-'&[Final Operator] as [ClaimKey]
Resident Claims
WHERE WildMatch(Status, 'Verified', 'Assessed but not Verified', 'Till Verify') and [Manual Claim] = 'Manual Claim' ;

Left join (Total)
LOAD * WHERE [Verified Type] = 'Claims Verified' ;
LOAD
[ClaimID],
[Claim&LineID],
Op,
[Count Date],
[Count Date] as [VerifiedDATE],
[Op]		as [VerifiedOp],
[Type] as [Verified Type]
Resident Total;

Left join (Total)
LOAD * WHERE [Processed Type] = 'Claims Processed' ;
LOAD
[ClaimID],
[Claim&LineID],
Op,
[Count Date] as [ProcessedDATE],
[Op]		as [ProcessedOp],
[Type] as [Processed Type]
Resident Total;

Left join (Total)
LOAD * WHERE [Adjusted Type] = 'Adjusted/Balanced Claims' ;
LOAD Distinct
[ClaimID],
//[Claim&LineID],
Op,
[Count Date],
[Count Date] as [AdjustedDATE],
[Op]		as [AdjustedOp],
[Type] as [Adjusted Type]
Resident Total;

Left join (Total)
LOAD * WHERE [Processed Type1] = 'Claims Processed' ;
LOAD
[ClaimID],
//[Claim&LineID],
//[Count Date],
[Op]		as [ProcessedOpCheck2],
[Type] as [Processed Type1]
Resident Total;


AdditionalLogic:
Load*,
If(Type = 'Claims Processed' or [ProcessedCheck] = 'Processed' or [ProcessedCheck3] = 'Processed', 'Processed', 'Other') as [ProcessedCheck2];
load*, 
If([ProcessedCheck]= 'Verified' and Type = 'Claims Verified', 'Verified', 'Processed') as [VerifiedOnlyCheck];
Load*, 
If([VerifiedDATE] = [ProcessedDATE] and [VerifiedOp] = [ProcessedOp], 'Processed Only', 'Verified') as [ProcessedVerifiedCheck], 
If([Op] = [VerifiedOp] and ISNULL([ProcessedOp]) and ISNULL([ProcessedOpCheck2]), 'Processed', 'Verified') as [ProcessedCheck],
If([Op] = [VerifiedOp] and ISNULL([ProcessedOp]) and Wildmatch([ProcessedOpCheck2], 'HICAPS', 'ECLIPSE', 'IBA', 'System Account'), 'Processed', 'Verified') as [ProcessedCheck3],
If([AdjustedDATE] = [VerifiedDATE] and [VerifiedOp] = [AdjustedOp], 'Adjusted Only', 'Verified') as [AdjustedOnlyCheck]
// ;
//  Load*,
//  IF(Type = 'Claims Verified', [Count Date],'Not Verified') as [Verified Date],  
//  IF(Type = 'Claims Processed', [Count Date], 'Not Processed') as [Processed Date],
//   IF(Type = 'Claims Verified', [Op],'Not Verified') as [VerifiedOp],  
//  IF(Type = 'Claims Processed', [Op], 'Not Processed') as [ProcessedOp]
 Resident Total;
 Drop Table Total;
Rename Table AdditionalLogic to Total;


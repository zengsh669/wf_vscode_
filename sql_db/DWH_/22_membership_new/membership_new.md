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
SET MonthNames='Jan;Feb;Mar;Apr;May;Jun;Jul;Aug;Sep;Oct;Nov;Dec';
SET LongMonthNames='January;February;March;April;May;June;July;August;September;October;November;December';
SET DayNames='Mon;Tue;Wed;Thu;Fri;Sat;Sun';
SET LongDayNames='Monday;Tuesday;Wednesday;Thursday;Friday;Saturday;Sunday';
SET NumericalAbbreviation='3:k;6:M;9:B;12:T;15:P;18:E;21:Z;24:Y;-3:m;-6:μ;-9:n;-12:p;-15:f;-18:a;-21:z;-24:y';


//LIB CONNECT TO 'rpsqlrp01 - paragonreporting';
LIB CONNECT TO 'prdsql05.westfund.com.au-ods - paragon';
//*****************************************************************************************************
//*	Data Maps
//*
//*		Author:	Shayley
//*		Date:	01/01/2021
//*
//*	HISTORY:
//*
//*		Date		Person			Description
//*		01/01/2021	Shayley			Initial Version
//*		30/06/2023	Alex Graydon	Change AgentMap to point at qvd from June2023
//*
//***************************************************************************************************** 

SalesChannelMapping:
Mapping
LOAD Distinct
    "Sales Channel",
    "Group"
FROM [lib://Manual Data (prdqs01_atobi)/Product Profitability/Sales Channel Mapping.xlsx] (ooxml, embedded labels, table is [Sales Channel Groups]);

ProductTargetGroupingMap:
Mapping
LOAD
    "product_code",
    "Target_Grouping"
FROM [lib://Manual Data (prdqs01_atobi)/Membership App 2/Old Product Mapping.xlsx] (ooxml, embedded labels, table is Sheet1);


AgentMap:
MAPPING
LOAD Distinct membership_id,
    if(len(description)<1, 'No Agency', description)	as Agent
FROM [lib://ExtractData (prdqs01_atobi)/Agent_At_June2023/Paragon_MemberAgent.qvd] (qvd);

PromoMap:
MAPPING
LOAD Distinct membership_id,
    if(len(promotion_description)<1, 'No Promotion', promotion_description)	as Promotion
FROM [lib://ExtractData (prdqs01_atobi)/Agent_At_June2023/Paragon_MemberPromo.qvd] (qvd);


CoverTypeMapping:
Mapping
LOAD "cover_type",
    description;
SQL SELECT "cover_type",
    description
FROM paragon.dbo."cover_type";


HearAboutMap:
Mapping
LOAD "hear_about_id",
    description;
SQL SELECT "hear_about_id",
    description
FROM paragon.dbo."hear_about";

ProductStringMap:
Mapping
LOAD distinct product_code,
    ProductStringDesc;
SQL select distinct product_code,replace(replace(replace(replace(replace(replace(replace(replace(cover,'Family ',''),'Couple ',''),'Single ',''),'Parent ',''),'Sole ',''), 'Extended ',''),'&','with'),'  with',' with') as ProductStringDesc
from group_key_full_by_branch
where product_code is not null
order by product_code;

TerminationReasonMap:
Mapping
LOAD "termination_code",
    description;
SQL SELECT "termination_code",
    description
FROM paragon.dbo."termination_code";

GroupMapping:
Mapping
LOAD "group_id",
    "description";
SQL SELECT *
FROM paragon.dbo.grouping;

PromotionMapping:
Mapping
LOAD "promotion_id",
    "description";
SQL SELECT *
FROM paragon.dbo.promotion;

OperatorMapping:
Mapping
LOAD "oper_name",
    "first_name"&' '&surname;
SQL SELECT *
FROM paragon.dbo.operator;

SALevel4Map:
Mapping
LOAD
    text(num(Postcode,0000)),
    SA4_NAME_2016
FROM [lib://Manual Data (prdqs01_atobi)/ABS Data/SA Levels Mapped to Postcodes.xlsx]
(ooxml, embedded labels, table is Sheet1);

SALevel3Map:
Mapping
LOAD
    text(num(Postcode,0000)),
    SA3_NAME_2016
FROM [lib://Manual Data (prdqs01_atobi)/ABS Data/SA Levels Mapped to Postcodes.xlsx]
(ooxml, embedded labels, table is Sheet1);

TerminationDescriptionMap:
Mapping
LOAD
    "Termination Description",
    "Short Termination Description"
FROM [lib://Manual Data (prdqs01_atobi)/Membership App 2/Cancelled v Transferred Mapping.xlsx]
(ooxml, embedded labels, table is [Termination Grouping]);

ProductGroupingMap:
Mapping
LOAD
    description,
    "Product Group in Qliksense App"
FROM [lib://Manual Data (prdqs01_atobi)/Membership App 2/Old Product Mapping.xlsx]
(ooxml, embedded labels, table is Sheet1);

BranchGroupMapping:
Mapping
LOAD
    Branch,
    "Mapping"
FROM [lib://Manual Data (prdqs01_atobi)/Product Profitability/Branch Mapping.xlsx]
(ooxml, embedded labels, table is [Branch Types]);

FundMap:
Mapping
LOAD
    previous_fund_id,
    description
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_Previous_Fund.qvd]
(qvd);

ResponsiblePersonNST:
Mapping
LOAD
    description,
    "Responsible Person"
FROM [lib://Manual Data (prdqs01_atobi)/NST/Agents with BDMs Grouped.xlsx]
(ooxml, embedded labels, table is Sheet1);

ResponsiblePersonNSTPromo:
Mapping
LOAD
    description,
    "Responsible Person"
FROM [lib://Manual Data (prdqs01_atobi)/NST/Promotions with BDM Grouped.xlsx]
(ooxml, embedded labels, table is Sheet1);

VISAMapping:
Mapping
LOAD "visa_type",
    "description";
SQL SELECT *
FROM paragon.dbo.visa_type
Where active_flag = 'Y';

CountryMapping:
Mapping
LOAD "country_code",
    "country_name";
SQL SELECT *
FROM paragon.dbo.country_code;

AthleteMapping:
Mapping
LOAD
    description,
    "Athlete Agent"
FROM [lib://Manual Data (prdqs01_atobi)/NST/Agents with BDMs Grouped.xlsx]
(ooxml, embedded labels, table is Sheet1);
//-----------------------------------------------------
// MemberPersons:
// LOAD Distinct
//     person_id							as memberperson
// FROM [lib://ExtractData (prdqs01_atobi)/Paragon_PersonMembership.qvd]
// (qvd);

// LeadProspects:
// LOAD
//     1									as Leads,
//     'P'&person_id						as [Membership ID],
//     DayName(create_datetime)			as [Lead Created Date],
//     date(floor(create_datetime)) 		as LeadDate,
//     MonthName(create_datetime)			as MonthYear,
//     'Contact Centre Lead'				as Source
// //    gender,
// //    date_of_birth
// FROM [lib://ExtractData (prdqs01_atobi)/Paragon_Person.qvd]
// (qvd) where not Exists(memberperson, person_id);

// left join (LeadProspects)
// LOAD
//     'P'&person_id						as [Membership ID],
//     trim(first_name)&' '&trim(surname)	as Agent,
//     trim(first_name)&' '&trim(surname)	as Branch
// FROM [lib://ExtractData (prdqs01_atobi)/Paragon_LatestPromoSalesChannelOperator.qvd]
// (qvd);

// drop Table MemberPersons;

// MemberStatusHistory:
// LOAD Distinct
//     1									as Leads,
//     membership_id						as [Membership ID],
// //     memship_status_version,
// //     memship_status,
// //     termination_code,
// //     effective_join_date,
// //     effective_termination_date,
// //     create_operator,
//     DayName(create_datetime)			as [Lead Created Date],
//     date(floor(create_datetime))		as LeadDate,
//     MonthName(create_datetime)			as MonthYear,
//     'Care Centre Lead'					as Source
// //     update_operator,
// //     update_datetime,
// //     "timestamp",
// //     delta,
// //     rejoin_date,
// //     terminate_operator,
// //     terminate_datetime,
// //     ingore_cover_line
// FROM [lib://ExtractData (prdqs01_atobi)/Paragon_Memship_Status_History.qvd]
// (qvd)
// where match(memship_status, 'L', 'P')
// ;

// left join (MemberStatusHistory)
// LOAD
//     "Membership Number"					as "Membership ID",
//     Agent,
//     Branch
// FROM [lib://TransformData (prdqs01_atobi)/Membership_Transformed.qvd]
// (qvd);

// Concatenate (LeadProspects)
// load * Resident MemberStatusHistory;

// drop Table MemberStatusHistory;

//----------------------------------------------


// LeadProspects:
// LOAD
//     1																					as Leads,
//     alt("membership_id", 'P'&person_id)													as [Membership ID],
//     ApplyMap('OperatorMapping',"create_operator","create_operator")						as [Operator],
//     DayName(create_datetime)															as [Lead Created Date],
//     date(floor("create_datetime"))														as [LeadDate],
//     MonthName(date(floor("create_datetime")))											as MonthYear,
//     "person_id"																			as [Person ID],
//     ApplyMap('GroupMapping',"group_id",'No Group')										as Agent,
//     ApplyMap('GroupMapping',"group_id",'No Group')										as Branch,
//  	'Contact Centre Lead'																as Source,
//     "cover_state"																		as State
// //    "cover_type",
// //    "billing_group_id"
// FROM [lib://ExtractData (prdqs01_atobi)/Paragon_Quotation.qvd]
// (qvd);

// MemberStatusHistory:
// LOAD Distinct
//     1									as Leads,
//     membership_id						as [Membership ID],
// //     memship_status_version,
// //     memship_status,
// //     termination_code,
// //     effective_join_date,
// //     effective_termination_date,
// //     create_operator,
//     DayName(create_datetime)			as [Lead Created Date],
//     date(floor(create_datetime))		as LeadDate,
//     MonthName(create_datetime)			as MonthYear,
//     'Care Centre Lead'					as Source
// //     update_operator,
// //     update_datetime,
// //     "timestamp",
// //     delta,
// //     rejoin_date,
// //     terminate_operator,
// //     terminate_datetime,
// //     ingore_cover_line
// FROM [lib://ExtractData (prdqs01_atobi)/Paragon_Memship_Status_History.qvd]
// (qvd)
// where match(memship_status, 'L', 'P')
// ;

// left join (MemberStatusHistory)
// LOAD
//     "Membership Number"					as "Membership ID",
//     Agent,
//     Branch
// FROM [lib://TransformData (prdqs01_atobi)/Membership_Transformed.qvd]
// (qvd);

// Concatenate (LeadProspects)
// load * Resident MemberStatusHistory;

// drop Table MemberStatusHistory;


//----------------------------------

// LeadProspects:
// LOAD
//     1																					as Leads,
//     alt("membership_id", 'P'&person_id)													as [Membership ID],
//     ApplyMap('OperatorMapping',"create_operator","create_operator")						as [Operator],
//     DayName(create_datetime)															as [Lead Created Date],
//     date(floor("create_datetime"))														as [LeadDate],
//     MonthName(date(floor("create_datetime")))											as MonthYear,
//     "person_id"																			as [Person ID],
//     ApplyMap('GroupMapping',"group_id",'No Group')										as Agent,
//     ApplyMap('GroupMapping',"group_id",'No Group')										as Branch,
//  	'Contact Centre Lead'																as Source,
//     "cover_state"																		as State
// //    "cover_type",
// //    "billing_group_id"
// FROM [lib://ExtractData (prdqs01_atobi)/Paragon_Quotation.qvd]
// (qvd);

// MemberStatusHistory:
// LOAD Distinct
//     1									as Leads,
//     membership_id						as [Membership ID],
// //     memship_status_version,
// //     memship_status,
// //     termination_code,
// //     effective_join_date,
// //     effective_termination_date,
// //     create_operator,
//     DayName(create_datetime)			as [Lead Created Date],
//     date(floor(create_datetime))		as LeadDate,
//     MonthName(create_datetime)			as MonthYear,
//     'Care Centre Lead'					as Source
// //     update_operator,
// //     update_datetime,
// //     "timestamp",
// //     delta,
// //     rejoin_date,
// //     terminate_operator,
// //     terminate_datetime,
// //     ingore_cover_line
// FROM [lib://ExtractData (prdqs01_atobi)/Paragon_Memship_Status_History.qvd]
// (qvd)
// where match(memship_status, 'L', 'P')
// ;

// left join (MemberStatusHistory)
// LOAD
//     "Membership Number"					as "Membership ID",
//     Agent,
//     Branch
// FROM [lib://TransformData (prdqs01_atobi)/Membership_Transformed.qvd]
// (qvd);

// Concatenate (LeadProspects)
// load * Resident MemberStatusHistory;

// drop Table MemberStatusHistory;
//*****************************************************************************************************
//*	Load Member History
//*
//*		Author:	Shayley
//*		Date:	01/01/2021
//*
//*	HISTORY:
//*
//*		Date		Person			Description
//*		01/01/2021	Shayley			Initial Version
//*		08/03/2023	Alex Graydon	Changes for Target Link table
//*		30/06/2023	Alex Graydon	Lock Agent & Sales Channel Group Pre July 2023, New Logic Post July 2023
//*     20/11/2023	Monique Rust	Added promotion description to the memberhistory snaps
//*
//***************************************************************************************************** 


MemberHistory:
LOAD LOM																		as LOMTMP,
    "Age"																		as AgeTMP,
    "Membership ID",
//     Arrears,
//     Advance,
    MonthYear,
//     HospitalArrears,
//     HospitalAdvance,
//     ExtrasArrears,
//     ExtrasAdvance,
    SEU,
//     "Hospital %",
//     "Extras %",
//     "QuarterEnd",
    "Effective Join Date"														as EffectiveJoinDateTMP,
    "Effective Termination Date"												as EffectiveTerminationDateTMP,
    "Date of Birth",
    Gender,
    Cover																		as CoverTMP,
    "Product Code"																as ProductCodeTMP,
    "Hospital Product"															as HospProductIDTMP,				//shayley
    "Amb/Extras Product"														as AmbExtrasProductIDTMP,			//shayley
    hosp_product																as HospProductTMP,
    amb_extras_product															as AMBExtrasProductTMP,
    State																		as StateTMP,
    Branch																		as BranchTMP,
    "Cover Type"																as CoverTypeTMP,
    pick(match("Membership Status", 'A','T'), 'Active','Terminated')			as "Membership Status",
    pick(match("Membership Status", 'A','T'), 1,0)								as ActiveMember,
    Postcode																	as PostcodeTMP,
    "Sales Channel"																as SalesChannelTMP,
    "Billing Frequence"															as BillingFrequenceTMP,
    AgeCohort																	as AgeCohortTMP,
    LOMCohort																	as LOMCohortTMP,
    HospFee																		as HospFeeTMP,
    ExtrasFee																	as ExtrasFeeTMP,
    alt(HospFee, 0)+alt(ExtrasFee, 0)											as [Product Fee],
    COALESCE("Agent Description",'No Agency')									as AgentDescriptionTMP,
    COALESCE([Promotion Description], 'No Promotion')							as PromotionDescriptionTMP,
    'MemberHistory'																as Source
FROM [lib://ExtractData (prdqs01_atobi)/MemberHistory.qvd] (qvd)
WHERE Match("Product Code", 'AMBU')=0;


CurrentMonthSnapshot:
LOAD *,
	 Age(MonthYear,"Date of Birth")												as AgeTMP,
	 Age(Coalesce(EffectiveTerminationDateTMP,MonthYear),EffectiveJoinDateTMP)	as LOMTMP;
     
LOAD Distinct "Membership Number"												as "Membership ID",
    state																		as StateTMP,
    "Cover Type"																as CoverTypeTMP,
//    termination_code															as TerminationCodeTMP,	
//    fund_id,
    "Membership Status",
    if((match("Membership Status", 'Active') 
    		and date("Effective Join Date") <= date(Today()))
    	or (match("Membership Status", 'Terminated') 
        	and date("Effective Termination Date") > date(Today())),1,0)		as ActiveMember,
    "Effective Join Date"														as EffectiveJoinDateTMP,
    "Effective Termination Date"												as EffectiveTerminationDateTMP,
    MonthName("SnapShot Date")													as MonthYear,
    WeekEnd("SnapShot Date")													as Weekend,
    "Create Operator",
//    "Agent ID",
     COALESCE(Agent,'No Agency')												as AgentDescriptionTMP,
//    "Branch ID",
    Branch																		as BranchTMP,
    "Product Code"																as ProductCodeTMP,
    "Cover Description"															as CoverTMP,
    "Product Description",
//    "Cover Type Description"													as CoverTypeTMP,
//    "Person Count",
//     "Person ID",
//     "Max Person Version",
//     "Hear About",
    "Date of Birth",
    "Person Postcode"															as PostcodeTMP,
//    status_date,
    COALESCE(ApplyMap('PromotionMapping',"Promotion ID", 'No Promotion'), 'No Promotion')									as [PromotionDescriptionTMP],
    "Sales Channel"																as SalesChannelTMP,
     'MemberSnapshot'															as Source
//     "Weekly Total Premium",
//     "Annual Total Premium"
FROM [lib://TransformData (prdqs01_atobi)/Membership Snapshots/Membership_SnapShot_Latest.qvd] (qvd)
WHERE ((match("Membership Status", 'Active') AND date("Effective Join Date") <= date(Today())) 
OR (match("Membership Status", 'Terminated') AND date("Effective Termination Date") > date(Today())))
AND WildMatch("Product Description", '*Ambul*')=0;

WithinPastWeek:
Load*,
IF(date([EffectiveJoinDateTMP]) >= date(floor(today()))-7, 'Nprint')										as [New Members within Past Week],
IF(date([EffectiveJoinDateTMP]) >= date(floor(today()))-1, 'Nprint')										as [New Members Yesterday]
Resident CurrentMonthSnapshot;
Drop Table CurrentMonthSnapshot;
Rename Table WithinPastWeek to CurrentMonthSnapshot;

AgeCohorts:
LOAD * inline [
agemin, agemax, AgeCohortTMP
-10, 24, 0-24
25, 34, 25-34
35, 44, 35-44
45, 54, 45-54
55, 64, 55-64
65, 74, 65-74
75, 84, 75-84
85, 199, 85+
];


LEFT JOIN IntervalMatch (AgeTMP) 
LOAD agemin, 
	 agemax
RESIDENT AgeCohorts;


LEFT JOIN (CurrentMonthSnapshot)
LOAD AgeTMP,
	 AgeCohortTMP
RESIDENT AgeCohorts;


LOMCohorts:
LOAD * inline [
lommin, lommax, LOMCohortTMP
-10, 0.99, <1
1, 2, 1-2
3, 4, 3-4
5, 7, 5-7
8, 10, 8-10
11, 15, 11-15
16, 20, 16-20
21, 199, 21+
];


LEFT JOIN IntervalMatch (LOMTMP) 
LOAD lommin, 
	 lommax
RESIDENT LOMCohorts;


LEFT JOIN (CurrentMonthSnapshot)
LOAD [LOMTMP],
	 LOMCohortTMP
RESIDENT LOMCohorts;


Concatenate (MemberHistory)
LOAD * Resident CurrentMonthSnapshot;


LET vNoRows = NoOfRows('MemberHistory');
Trace MemberHistory Rows-$(vNoRows);


OUTER JOIN (MemberHistory)
LOAD [Membership ID],
	 MonthName(AddMonths(MonthYear, 1))											as MonthYear,
	 LOMTMP																		as [Old LOM],
     AgeTMP																		as [Old Age],
//     TerminationCodeTMP															as [Old TerminationCode],
     EffectiveJoinDateTMP														as [Old Effective Join Date],
     EffectiveTerminationDateTMP												as [Old Effective Termination Date],
     CoverTMP																	as [Old Cover],
     ProductCodeTMP																as [Old Product Code],
     ApplyMap('ProductStringMap',ProductCodeTMP,'Missing')						as [Old Product String Description],     
     HospProductIDTMP															as [Old HospProductID],
     AmbExtrasProductIDTMP														as [Old AmbExtras ProductID],
     StateTMP																	as [Old State],
     BranchTMP																	as [Old Branch],
     ApplyMap('CoverTypeMapping',"CoverTypeTMP", 'Missing')						as [Old Cover Type],
     PostcodeTMP																as [Old Postcode],
     SalesChannelTMP															as [Old Sales Channel],
     BillingFrequenceTMP														as [Old Billing Frequence],
     AgeCohortTMP																as [Old AgeCohort],
     LOMCohortTMP																as [Old LOMCohort],
     HospFeeTMP																	as [Old HospFee],
     ExtrasFeeTMP																as [Old ExtrasFee],
     [Product Fee]																as [Old Product Fee],
     AgentDescriptionTMP														as [Old Agent Description],
     PromotionDescriptionTMP 													as [Old Promotion Description],
	HospProductTMP																as HospProductOLD,
    AMBExtrasProductTMP															as AMBExtrasProductOLD
RESIDENT MemberHistory
WHERE Source = 'MemberHistory';
//FROM [lib://ExtractData (prdqs01_atobi)/MemberHistory.qvd] (qvd)
//WHERE Match("Product Code", 'AMBU')=0;


LET vNoRows = NoOfRows('MemberHistory');
Trace MemberHistory Rows-$(vNoRows);


// left join (MemberHistory)
// load 
// 	 "Membership ID",
//      [Lead Created Date]
// Resident LeadProspects;

// drop Field [Lead Created Date] from LeadProspects;


MemberStats:
NoConcatenate
LOAD *,
// 	if(Date([1 Month Anniversary]-7)>=today(),'1 Month Anniversary',
//     		if(Date([2 Years Anniversary]-7)>=today(),'2 Years Anniversary'       Taken out 2 year & 1 month anniversaries for Qs-2153
		if(Date([1 Year Anniversary]-7)>=today(),'1 Year Anniversary')																		as [Next Anniversary],
// 	if([1 Month Anniversary]>=today(),[1 Month Anniversary],
//     if([2 Years Anniversary]>=today(),[2 Years Anniversary],
		if([1 Year Anniversary]>=today(),[1 Year Anniversary])																		as [Next Anniversary Date],
// 	Weekend(if(Date([1 Month Anniversary]-7)>=today(),Date([1 Month Anniversary]-7),
// 	if(Date([2 Years Anniversary]-7)>=today(),Date([2 Years Anniversary]-7),
				Weekend(if(Date([1 Year Anniversary]-7)>=today(),Date([1 Year Anniversary]-7)))												as [Week of Next Anniversary Call],
if(Weekend(Date([1 Year Anniversary] - 7)) = Weekend(today()),'Anniversary NPrint') 														as [Anniversary NPRINTING FLAG],
    IF(Wildmatch(JoinSalesChannel,'Health Deal','Choosi','Compare the Market','Covad','Field Days','JCU Dental Cairns','John Small','No Channel','Other',
    	'Sept/Oct Upgrade Promo 2012','Sunshine Coast Regional Council','Union Shopper', 'Compare Health', 'Shopping Centre', 'Missing'),
        	'Other',
			IF(Wildmatch(JoinSalesChannel,'Phone','Corporate Group','Web Assist','Branch Direct Phone'),
            	'Phone',
				IF(Wildmatch(JoinSalesChannel,'WEB','Internet'),
                	'WEB',
					IF(Wildmatch(JoinSalesChannel,'F2F-External activity','F2F-Care Centre Walk-in','Face to Face','Corporate F2F','Paper'),
                    	'Face to Face',
                        JoinSalesChannel))))  																								as [Join Sales Channel];
    
//      If(Wildmatch([Termination Reason],'Deceased','Suspending to travel','Extend Suspension','Cancelled - Veterans Affairs Gold Card','Receiving health insurance from employer','Cancelled/Suspension period lapsed','Transfer to membership within Westfund','Student returning to parents cover'),
//         'Unavoidable',
//     	If(Wildmatch([Termination Reason],'Transfer to another health fund','Cooling Off period','Unknown','Cancelled/No longer requires health insurance','Cancelled - Financial Difficulty','Cancelled/Arrears','Retired/Retrenched','Entry Error','MISSING'),
//         	'Avoidable','To Be Classified')) 																								as [Terminations Avoidable/Unavoidable];

LOAD *,
	if(wildmatch([Product String Description],'*Overse*'),'Overseas',
		if(wildmatch([Product String Description],'*&*','*with*'),'Combined',
			if(WildMatch([Product String Description],'*Hospital*'),'Hospital Only',
    			if(WildMatch([Product String Description],'*Extra*'),'Extras Only',
        			if(WildMatch([Product String Description],'*Ambul*'),'Ambulance')))))													as [Product Type],
	if(wildmatch([Hosp Product ID],'*Gold*'),'Gold',
		if(wildmatch([Hosp Product ID],'*Silver*'),'Silver',
			if(wildmatch([Hosp Product ID],'*Bronze*'),'Bronze',
				if(wildmatch([Hosp Product ID],'*Basic*'),'Basic','Other'))))																as [Hospital Tier],   
	If(wildmatch([Hosp Product ID],'*250*'),'250',
		if(wildmatch([Hosp Product ID],'*500*'),'500',
			if(wildmatch([Hosp Product ID],'*750*'),'750',
				if(wildmatch([Hosp Product ID],'*Hospital*'),'Nil','Other'))))																as [Excess Level],
// 	addmonths([Effective Join Date],1)																										as [1 Month Anniversary],
	addyears([Effective Join Date],1)																										as [1 Year Anniversary],
// 	addyears([Effective Join Date],2)																										as [2 Years Anniversary],
	If(Wildmatch("Product Code",'J52*','J53*','J54*','J58*','NZ','ENZ','FC','EFC','FCE','NZE','SP','ESP','J62*'),'Top Cover',
    	If(Wildmatch("Product Code", 'NI','FI','VE','I*'), 'Extras Only',
        If(Wildmatch("Product Code", 'AMBU', 'AMBUU','PAM','BAM','AMB'), 'Ambulance', 'Exclusionary')))     								as [Product Classification],
    If(not(isnull(Agent)) and [Create Operator] = 'WEB', 'WEB', [Sales Channel])															as JoinSalesChannel,
	If(Wildmatch(Agent, 'CTM', 'Westfund Staff',  'Web Join', 'Westfund Staff', 'Compare Health', 'Choosi', 'Biloela Agency',
   						'Blackwater', 'Covad', 'Dysart Agency', 'Forbes Agency', 'John Small Brokerage', 'Kalgoorlie Agency', 
                        'Katoomba Agency', 'Moura Agency-First National', 'Rylstone Agency', 'Sarina Agency', 
                        'Telephone Sales', 'Union Shopper', 'Wellington Agency', 'No Agency'), 'Other', Agent) 								as [Join Agent],
  ApplyMap('ResponsiblePersonNST', Agent, 'Check')               																			as [Responsible Person],
    ApplyMap('ResponsiblePersonNSTPromo', Promotion, 'N/A')               																	as [Responsible Person for Promo],
      ApplyMap('AthleteMapping', Agent, 'Non Athlete')               																		as [Athlete Y/N]
                        ;
//      ApplyMap('TerminationReasonMap',termination_code,'MISSING')																			as [Termination Reason],
//      ApplyMap('TerminationReasonMap',termination_code,'MISSING')																			as [Termination Description],
//      ApplyMap('TerminationDescriptionMap',ApplyMap('TerminationReasonMap',termination_code,Null()),'Unknown')							as [Termination Description Group];

// AG 21/06/2023 Determine Agent/Sales Channel to use New after 1.7.23 and Old before
LOAD *,
	 If(MonthYear > MakeDate(2023,06,30),[Sales Channel Group New Logic],[Sales Channel Group Old Logic])									as [Sales Channel Group],
     If(MonthYear > MakeDate(2023,06,30),[Agent New Logic],[Agent Old Logic])																as Agent,
     If(MonthYear > MakeDate(2022,06,30),[Promotion New Logic],[Promotion Old Logic])														as Promotion;

LOAD *,
	 MonthYear & '|' & "Membership ID"																										as Membership_KEY,
	 if(IsNull(CoverTMP), [Old Cover], CoverTMP)																							as Cover,
	 if(IsNull(ProductCodeTMP), [Old Product Code], ProductCodeTMP)																			as [Product Code],
     ApplyMap('ProductTargetGroupingMap',if(IsNull(ProductCodeTMP), [Old Product Code], ProductCodeTMP),'Other')							as [Product Target Grouping],	
     ApplyMap('ProductStringMap',if(IsNull(ProductCodeTMP), [Old Product Code], ProductCodeTMP),'Missing')									as [Product String Description],
   	 if(IsNull(HospProductIDTMP), [Old HospProductID], HospProductIDTMP)																	as [Hosp Product ID],			//shayley
     ApplyMap('ProductGroupingMap',if(IsNull(HospProductTMP), HospProductOLD, HospProductTMP),'No Group')									as "Hospital Product Grouping",
     ApplyMap('ProductGroupingMap',if(IsNull(HospProductIDTMP), HospProductIDTMP, [Old HospProductID]),'No Group')							as [Previous Hospital Product Grouping],
     if(IsNull([AmbExtrasProductIDTMP]), [Old AmbExtras ProductID], [AmbExtrasProductIDTMP])												as [Amb/Extras Product ID],		//shayley
     ApplyMap('ProductGroupingMap',if(IsNull(AMBExtrasProductTMP), AMBExtrasProductOLD, AMBExtrasProductTMP),'No Group')					as "Amb/Extras Product Grouping",  
     ApplyMap('ProductGroupingMap',if(IsNull([AmbExtrasProductIDTMP]), [AmbExtrasProductIDTMP], [Old AmbExtras ProductID]),'No Group')		as [Previous Amb/Extras Product Grouping],
	 if(IsNull(EffectiveJoinDateTMP), [Old Effective Join Date], EffectiveJoinDateTMP)														as [Effective Join Date],
	 if(IsNull(EffectiveTerminationDateTMP), [Old Effective Termination Date], EffectiveTerminationDateTMP)									as [Effective Termination Date],
	 if(IsNull(StateTMP), [Old State], StateTMP)																							as State,
	 if(IsNull(BranchTMP), [Old Branch], BranchTMP)																							as Branch, 
     ApplyMap('BranchGroupMapping',if(IsNull(BranchTMP), [Old Branch], BranchTMP),'Unknown')												as [Branch Grouping],     
     Coalesce(AgentDescriptionTMP,[Old Agent Description])																					as [Agent New Logic], 				// AG from 1.7.23     
     Coalesce(PromotionDescriptionTMP,[Old Promotion Description])																			as [Promotion New Logic], 			// MR From 1.7.22
     If(WildMatch(Coalesce(AgentDescriptionTMP,[Old Agent Description]),'No Agency','No Agent','CTM','Web Join','Compare Health','Choosi',
     	'Biloela Agency','Blackwater Agency','Blackwater','Covad','Dysart Agency','Forbes Agency','John Small Brokerage','Kalgoorlie Agency','Katoomba Agency',
        'Moura Agency - First National', 'Rylstone Agency', 'Sarina Agency','Telephone Sales', 'Union Shopper', 
        'Wellington Agency', 'YourShare','HICA Agency','YourShare', '*Parkes Agency*'),
     	ApplyMap('SalesChannelMapping',Coalesce(SalesChannelTMP,[Old Sales Channel]),'No Channel Group'),'Corporate')						as [Sales Channel Group New Logic], // AG from 1.7.23                   
     ApplyMap('AgentMap',"Membership ID",'No Agency')																						as [Agent Old Logic], 	// AG Pre 1.7.23
     ApplyMap('PromoMap',"Membership ID",'No Promotion')																					as [Promotion Old Logic], 	// MR Pre 1.7.23
     IF(WildMatch(ApplyMap('AgentMap',"Membership ID",'No Agency'),'No Agency','No Agent'), 
     	ApplyMap('SalesChannelMapping',Coalesce(SalesChannelTMP,[Old Sales Channel]),'No Channel Group'),'Corporate') 						as [Sales Channel Group Old Logic],	// AG Pre 1.7.23
     if(IsNull(LOMTMP), [Old LOM], LOMTMP)																									as LOM,
     if(IsNull(AgeTMP), [Old Age], AgeTMP)																									as Age,
     if(IsNull(AgeCohortTMP), [Old AgeCohort], AgeCohortTMP)																				as AgeCohort,
     if(IsNull(LOMCohortTMP), [Old LOMCohort], LOMCohortTMP)																				as LOMCohort,
     if(IsNull(HospFeeTMP), [Old HospFee], HospFeeTMP)																						as [Hospital Fee],
     if(IsNull(ExtrasFeeTMP), [Old ExtrasFee], ExtrasFeeTMP)																				as [Amb/Extras Fee],
	 ApplyMap('CoverTypeMapping',if(IsNull(CoverTypeTMP), [Old Cover Type], CoverTypeTMP),[Old Cover Type])									as [Cover Type],
     if(isnull([Old Cover Type]), 'Missing', [Old Cover Type])																				as [Terminated Cover Type],
	 text(num(if(IsNull(PostcodeTMP), [Old Postcode], PostcodeTMP), 0000))																	as Postcode,
     ApplyMap('SALevel4Map',text(num(if(IsNull(PostcodeTMP), [Old Postcode], PostcodeTMP), 0000)),'No SA Level 4')							as [SA LEVEL 4],
     ApplyMap('SALevel3Map',text(num(if(IsNull(PostcodeTMP), [Old Postcode], PostcodeTMP), 0000)),'No SA Level 4')							as [SA LEVEL 3],
	 if(
     	isnull(if(IsNull(SalesChannelTMP), [Old Sales Channel], SalesChannelTMP)),'No Channel',
        if(IsNull(SalesChannelTMP), [Old Sales Channel], SalesChannelTMP))																	as [Sales Channel],
	 if(IsNull(BillingFrequenceTMP), [Old Billing Frequence], BillingFrequenceTMP)															as [Billing Frequency],
	 if(IsNull(CoverTMP), 1, 0)																												as Terminations,
	 if(IsNull([Old Cover]), 1, 0)																											as Joins,
     //if([Product Fee]>[Old Product Fee], 'Upgrade', if([Product Fee]<[Old Product Fee], 'Downgrade', 'No Change'))						as [Cover Change]
     if([Product Fee]>[Old Product Fee] and [Old Product Code] <> Coalesce(ProductCodeTMP,[Old Product Code]), 'Upgrade', 
     if([Product Fee]<[Old Product Fee] and [Old Product Code] <> Coalesce(ProductCodeTMP,[Old Product Code]), 'Downgrade', 'No Change'))	as [Cover Change],
//     Coalesce(TerminationCodeTMP,[Old TerminationCode])																					as termination_code
	 if([Product Fee]>[Old Product Fee] 
     	and [Old Product Code] <> Coalesce(ProductCodeTMP,[Old Product Code])
     	and [Old AmbExtras ProductID] <> [AmbExtrasProductIDTMP] , 'Upgrade', 
     if([Product Fee]<[Old Product Fee] 
     	and [Old Product Code] <> Coalesce(ProductCodeTMP,[Old Product Code])
     	and [Old AmbExtras ProductID] <> [AmbExtrasProductIDTMP] , 'Downgrade', 'No Change'))													as [Amb/Extras Cover Change],
     if([Product Fee]>[Old Product Fee] 
       and [Old Product Code] <> Coalesce(ProductCodeTMP,[Old Product Code])
     	and [Old HospProductID] <>  HospProductIDTMP , 'Upgrade', 
     if([Product Fee]<[Old Product Fee] 
     	and [Old Product Code] <> Coalesce(ProductCodeTMP,[Old Product Code])
     	and [Old HospProductID] <>  HospProductIDTMP , 'Downgrade', 'No Change'))																as [Hosp Cover Change]    
//     Coalesce(TerminationCodeTMP,[Old TerminationCode])																					as termination_code
     
RESIDENT MemberHistory;



MemberStats2:
load *,
if(wildmatch(Cover,'*100*','*250*','*400*','*500*','*750*','*Athlete*'),'Hospital Product with Excess') 						as [Downgrade to product with excess],
if(wildmatch([Old Cover],'*100*','*250*','*400*','*500*','*750*','*Athlete*'),'Hospital Product with Excess') 					as [Downgrade from product with excess],
if(not(wildmatch([Product Code],'*ENZ*','*NZ*','*NZE*','*NZX*','*EFC*','*FC*','*FCE*','*FCX*','*J52*','*J58*','*J62*')) , 
				'Hospital Product with Exclusions') 																			as [Downgrade to product with exclusions],
if(not(wildmatch([Old Product Code],'*ENZ*','*NZ*','*NZE*','*NZX*','*EFC*','*FC*','*FCE*','*FCX*','*J52*','*J58*','*J62*')) , 
				'Hospital Product with Exclusions') 																			as [Downgrade from product with exclusions],
if(wildmatch([Old Cover],'*Extras*','*Ancil*'),'Had Ancillary Cover','Didnt Have Ancillary Cover')								as [Old Cover contained ancil cover],
if(wildmatch([Cover],'*Extras*','*Ancil*'),'Has Ancillary Cover','No Ancillary Cover')											as [Cover contains ancil cover]
Resident MemberStats;
Drop Table MemberStats;
Rename Table MemberStats2 to MemberStats;

LET vNoRows = NoOfRows('MemberStats');
Trace MemberStats Rows-$(vNoRows);


LEFT JOIN (MemberStats)
LOAD Postcode,
     SA3_NAME_2016						as [SA Level 3],
     SA4_NAME_2016						as [SA Level 4]
FROM [lib://Manual Data (prdqs01_atobi)/ABS Data/SA Levels Mapped to Postcodes.xlsx] (ooxml, embedded labels, table is Sheet1);


LET vNoRows = NoOfRows('MemberStats');
Trace MemberStats Rows-$(vNoRows);


//DROP Tables AgeCohorts,LOMCohorts,CurrentMonthSnapshot,MemberHistory;
DROP Tables AgeCohorts,LOMCohorts,CurrentMonthSnapshot;

DROP Fields 
//	 CoverTMP, 
//     [Old Cover], 
	 ProductCodeTMP, 
//     [Old Product Code], 
	 HospProductIDTMP, 
//     [Old HospProductID],
//	 [AmbExtrasProductIDTMP], 
//     [Old AmbExtras ProductID],
	 EffectiveJoinDateTMP, 
//     [Old Effective Join Date],
	 EffectiveTerminationDateTMP, 
//     [Old Effective Termination Date],
// 	 TerminationCodeTMP,
//      [Old TerminationCode],
	 StateTMP, 
//     [Old State],	
	 BranchTMP, 
//     [Old Branch],
     AgeTMP, 
//     [Old Age],
     LOMTMP, 
//     [Old LOM],
     AgeCohortTMP, 
//     [Old AgeCohort],
     LOMCohortTMP,
//     [Old LOMCohort],
     HospFeeTMP,
//     [Old HospFee],
     ExtrasFeeTMP,
//     [Old ExtrasFee],
	 CoverTypeTMP,
//     [Old Cover Type],
	 PostcodeTMP, 
//     [Old Postcode],	 
     SalesChannelTMP,
//     [Old Sales Channel]
//	[Sales Channel GroupTMP],
     AgentDescriptionTMP
;
 
 
 
 
// OMFEligibility:
// Load *,
// if(len([Effective Termination Date] > 1),'Not Eligible',

// if(wildmatch(Promotion,'1FREE')
// 				and wildmatch([Member Cover Type],'Extras Only','Combined') 
// 				and [Sales Channel Group] <> 'Compare the Market'
//                 and [Sales Channel Group] <> 'Corporate'
//                 and (today()-[Effective Join Date]) > 59.99,'OMF Eligible',
                
// if(wildmatch(Promotion,'Sports Gold Coast','PPOMF60')
// 				and [Sales Channel Group] <> 'Compare the Market'
//                 and (today()-[Effective Join Date]) > 59.99,'OMF Eligible',
                
// if(wildmatch(Promotion,'GWS-OMF')
// 				and wildmatch([Member Cover Type],'Hospital Only','Combined') 
// 				and [Sales Channel Group] <> 'Compare the Market'
//                 and [Sales Channel Group] <> 'Corporate'
//                 and (today()-[Effective Join Date]) > 59.99,'OMF Eligible',
                
// if(wildmatch(Promotion,'Dependants Offer')
// 				and not(wildmatch([Cover],'*Ambu*')) 
// 				and [Sales Channel Group] <> 'Compare the Market'
//                 and [Sales Channel Group] <> 'Corporate'
//                 and (today()-[Effective Join Date]) > 29.99,'OMF Eligible',
                            
// if(wildmatch(Promotion,'DCOCGOLF', 'Dubbo Chamber Commerce Gold Da')
// 				and wildmatch([Member Cover Type],'Combined', 'Hospital Only') 
// 				and [Sales Channel Group] <> 'Compare the Market'
//                 and [Sales Channel Group] <> 'Corporate'
//                 and (today()-[Effective Join Date]) > 59.99,'OMF Eligible',

// if(wildmatch(Promotion,'CFMEU OMF')
// 				and wildmatch([Member Cover Type],'Extras Only','Combined', 'Hospital Only') 
// 				and [Sales Channel] <> 'Corporate Group'
//                 //and wildmatch([Sales Channel], 'Corporate F2F') 
//                 and (today()-[Effective Join Date]) > 29.99,'OMF Eligible',                    
                
// if(wildmatch(Promotion,'Corp partner OMF')
// 				and (today()-[Effective Join Date]) > 59.99,'OMF Eligible', 'Not Eligible'))))))))					 	as [OMF Eligibility],
                
// if(Promotion = 'DEPENDANTS' and wildmatch(method_reference_number,'*DEPENDANTS*','*DEPENDANT*','*Dep 25*','*dependant*','*Dependant*', '*CFMEU*'),'Complete',
//  	IF([receipt_amount]=0, 'Complete',
// 	if([Paid to Days Month Val] ='Yes','Complete','Not Complete'))) 							as [OMF Complete],
    
    
//     if(len([Effective Termination Date] > 1),'ORF Not Eligible',
// if(wildmatch(Promotion,'ORF2021')
// 				and wildmatch([Member Cover Type],'Combined') 
// 				and [Sales Channel Group] <> 'Compare the Market'
//                 and [Sales Channel Group] <> 'Corporate'
//                 and (today()-[Effective Join Date]) > 59.99,'ORF Eligible', 'ORF Not Eligible')) 				as [ORF Eligibility],
                
// if(wildmatch(Promotion,'ORF2021')
// 				and wildmatch(method_reference_number,'*ORF2021*'), 'Complete',
//                 IF([receipt_amount]=0,'Complete',
//                	IF([ORF Paid to Days Month Val]='Yes', 'Complete', 'Not Complete')))								as [ORF Complete] 
    


// Resident MemberStats;
// Drop Table MemberStats;
// Rename Table OMFEligibility to MemberStats;
//*****************************************************************************************************
//*	Add Monthly retention counts to the member history
//*
//*		Author:	Alex Graydon
//*		Date:	08/03/2023
//*
//*	HISTORY:
//*
//*		Date		Person			Description
//*		08/03/2023	Alex Graydon	Initial Version
//*		04/07/2023	Alex Graydon	Join Member Stats data on Membership_KEY
//*
//***************************************************************************************************** 


MonthlyRetentionRatesTmp:
LOAD Date([SnapShot Date],'MMM YYYY') & '|' & [Membership Number]				as Membership_KEY,
	 [Membership Number]														as [Membership ID],
     MonthName("SnapShot Date")													as MonthYear,
	 [Previous MemberCount],
     [Retained Count],
     [Product Code],
     ApplyMap('ProductTargetGroupingMap',[Product Code],'Other')				as [Product Target Grouping],
     If(Wildmatch([Product Code],'J52*','J53*','J54*','J58*','NZ','ENZ','FC','EFC','FCE','NZE','SP','ESP'),'Top Cover',
    	If(Wildmatch([Product Code], 'NI','FI','VE','I*'), 'Extras Only',
        	If(Wildmatch([Product Code], 'AMBU', 'AMBUU','PAM','BAM','AMB'), 
            	'Ambulance', 'Exclusionary')))									as [Product Classification],
     [Cover Type]
FROM [lib://TransformData (prdqs01_atobi)/Membership Snapshots/MonthlyRetentionRates.qvd] (qvd)
WHERE match([Product Code], 'AMBU', 'AMBUU','PAM','BAM','AMB')=0;  //  exclude Ambulance members.


LET vNoRows = Num(NoOfRows('MonthlyRetentionRates'),'#,##0');
Trace MonthlyRetentionRates Rows - $(vNoRows);


LEFT JOIN (MonthlyRetentionRatesTmp)
LOAD DISTINCT [Membership Number]												as [Membership ID],
     [Termination Reason],
//    If(Wildmatch("Termination Reason",'Cancelled/Arrears','Cancelled - Financial Difficulty'),'Cancelled - Financial',[Termination Reason])		as [Termination Reason Group],
 	 If(Wildmatch([Termination Reason],'Deceased','Cancelled - Deceased','Suspending to travel','Suspending - Travel','Extend Suspension','Cancelled - Veterans Affairs Gold Card','Receiving health insurance from employer',
     'Cancelled/Suspension period lapsed','Cancelled - Suspension period lapsed','Transfer to membership within Westfund','Cancelled - Transfer to membership within Westfund',
     'Cancelled - Moving overseas','Divorced from main member','Removed by Main Member','Student returning to parents cover','Cancelled - Separated from main member'),'Unavoidable',
    	If(Wildmatch([Termination Reason],'Transfer to another health fund','Cancelled - Transfer to another health fund','Cooling Off period','Cancelled - Cooling off period','Unknown',
        'Cancelled/No longer requires health insurance', 'Cancelled - No longer requires health insurance','Change to Medicare Levy','Financial Difficulty - COVID-19',
        'Cancelled - Financial Difficulty','Cancelled/Arrears','Cancelled - Arrears','Retired/Retrenched','Entry Error','Cancelled - Entry error','MISSING'),
        	'Avoidable','To Be Classified')) 									as [Terminations Avoidable/Unavoidable]
FROM [lib://TransformData (prdqs01_atobi)/Membership_Transformed.qvd] (qvd);


LET vNoRows = Num(NoOfRows('MonthlyRetentionRates'),'#,##0');
Trace MonthlyRetentionRates Rows - $(vNoRows);



LEFT JOIN (MonthlyRetentionRatesTmp)
LOAD DISTINCT Membership_KEY,
	 Branch,
	 LOMCohort,
     AgeCohort,
     [Sales Channel],
     [Sales Channel Group],
     State
RESIDENT MemberStats;

// LOAD [Membership ID],
//      FirstSortedValue(Branch,-MonthYear)										as Branch,
//      FirstSortedValue(LOMCohort,-MonthYear)										as LOMCohort,
//      FirstSortedValue(AgeCohort,-MonthYear)										as AgeCohort,
// 	 FirstSortedValue([Sales Channel],-MonthYear)								as [Sales Channel],
// 	 FirstSortedValue([Sales Channel Group],-MonthYear)							as [Sales Channel Group], 
//      FirstSortedValue(State,-MonthYear)											as State
// RESIDENT MemberStats
// GROUP BY [Membership ID];


LET vNoRows = Num(NoOfRows('MonthlyRetentionRates'),'#,##0');
Trace MonthlyRetentionRates Rows - $(vNoRows);

// Add last active data for terminated members
LEFT JOIN (MonthlyRetentionRatesTmp)
LOAD [Membership ID],
     FirstSortedValue(Branch,-MonthYear)										as LastBranch,
     FirstSortedValue(LOMCohort,-MonthYear)										as LastLOMCohort,
     FirstSortedValue(AgeCohort,-MonthYear)										as LastAgeCohort,
	 FirstSortedValue([Sales Channel],-MonthYear)								as LastSalesChannel,
	 FirstSortedValue([Sales Channel Group],-MonthYear)							as LastSalesChannelGroup, 
     FirstSortedValue(State,-MonthYear)											as LastState
RESIDENT MemberStats
GROUP BY [Membership ID];

LET vNoRows = Num(NoOfRows('MonthlyRetentionRatesTmp'),'#,##0');
Trace MonthlyRetentionRates Rows - $(vNoRows);

//If null use last active value
MonthlyRetentionRates:
NOCONCATENATE
LOAD Membership_KEY,
	 [Membership ID],
     MonthYear,
	 [Previous MemberCount],
     [Retained Count],
     [Product Code],
	 [Product Target Grouping],
	 [Product Classification],
     [Cover Type],
     [Termination Reason],
     [Terminations Avoidable/Unavoidable],
     Coalesce(Branch,LastBranch,'MISSING')										as Branch,
     Coalesce(LOMCohort,LastLOMCohort)											as LOMCohort,
     Coalesce(AgeCohort,LastAgeCohort)											as AgeCohort,
     Coalesce([Sales Channel],LastSalesChannel)									as [Sales Channel],
     Coalesce([Sales Channel Group],LastSalesChannelGroup)						as [Sales Channel Group],
     Coalesce(State,LastState)													as State

RESIDENT MonthlyRetentionRatesTmp;


CONCATENATE (MemberStats)
LOAD *
RESIDENT MonthlyRetentionRates;


DROP Tables MonthlyRetentionRatesTmp,MonthlyRetentionRates;
//*****************************************************************************************************
//*	Add Static member information
//*
//*		Author:	Alex Graydon
//*		Date:	08/03/2023
//*
//*	HISTORY:
//*
//*		Date		Person			Description
//*		08/03/2023	Alex Graydon	Initial Version
//*
//***************************************************************************************************** 


Membership:
LOAD membership_id																as [Membership ID],
	 person_id;
SQL SELECT "person_id",
    "membership_id",
    relationship,
    "status_flag"
FROM paragon.dbo."person_membership"
WHERE status_flag = 'A' and relationship = 1;


LET vNoRows = NoOfRows('Membership');
Trace Membership Rows-$(vNoRows);


LEFT JOIN (Membership)
LOAD "Membership Number"														as [Membership ID],
	"Annual Auxillary Amount",	
    Money(Round("Annual Auxillary Amount"/52.1429,0.01))							as [Weekly Total Extras Premium],
    "Annual Hospital Amount",
    Money(Round("Annual Hospital Amount"/52.1429,0.01))							as [Weekly Total Hospital Premium],
    "Annual Total Premium",
    Money(Round("Annual Total Premium"/52.1429,0.01))							as [Weekly Total Premium]
FROM [lib://TransformData (prdqs01_atobi)/ProductPremium_View_Transformed.qvd] (qvd);


LET vNoRows = NoOfRows('Membership');
Trace Membership Rows-$(vNoRows);


LEFT JOIN (Membership)
LOAD membership_id																as [Membership ID],
     trim(first_name)&' '&trim(surname)											as Operator;
SQL SELECT "membership_id",
	first_name,
    surname
FROM paragon.dbo."LatestPromoSalesChannelByPerson"
WHERE relationship = 1;


LET vNoRows = NoOfRows('Membership');
Trace Membership Rows-$(vNoRows);


LEFT JOIN (Membership)
LOAD person_id,
     description																as [Previous Fund];
SQL SELECT "person_id",
    description
FROM paragon.dbo.PreviousFund;


LET vNoRows = NoOfRows('Membership');
Trace Membership Rows-$(vNoRows);


LEFT JOIN (Membership)
LOAD Distinct person_id,
     ApplyMap('HearAboutMap',hear_about_id,'No Hear About')						as [Hear About],
     transfered_fund_id															as [Transfer Fund ID],
     ApplyMap('FundMap', transfered_fund_id, 'Not Specified')					as [Transfer Fund Description];
SQL SELECT *
From paragon.dbo.person;

LEFT JOIN (Membership)
LOAD membership_id																	as [Membership ID],
     create_operator 															as [Membership Create Operator];
SQL SELECT *
From paragon.dbo.memship;


LEFT JOIN (Membership)
LOAD 
	membership_id																	as [Membership ID],
	person_id,
	ApplyMap('CountryMapping',visa_country_code, 'Not Specified')				as [Country],
     ApplyMap('VISAMapping', visa_type, 'Not Specified')						as [Visa Type];
SQL SELECT *
From paragon.dbo.memship_app_dep
Where relationship = '1';


LET vNoRows = NoOfRows('Membership');
Trace Membership Rows-$(vNoRows);


LEFT JOIN (Membership)
LOAD [Membership ID],
	 if(isnull([Previous Fund]),
     	'New',
        if(wildmatch([Previous Fund],'*Westfund*'),
        	'Westfund to Westfund','Transferred'))								as "New v Transferred"
RESIDENT Membership;


LET vNoRows = NoOfRows('Membership');
Trace Membership Rows-$(vNoRows);


// LEFT JOIN (Membership)
// LOAD Distinct membership_id														as [Membership ID],
//     Coalesce(promotion_description,'No Promo')									as Promotion;
// SQL SELECT *
// FROM paragon.dbo.LatestPromoSalesChannelOperator;


// LET vNoRows = NoOfRows('Membership');
// Trace Membership Rows-$(vNoRows);




// LEFT JOIN (Membership)
// LOAD membership_id																as [Membership ID],
//      old_paid_to,
//      new_paid_to,
//      new_paid_to - old_paid_to													as Days,
//      if(new_paid_to-old_paid_to>=28 and new_paid_to-old_paid_to<=31,'Yes')		as [Paid to Days Month Val],
//      if(new_paid_to-old_paid_to>=42 and new_paid_to-old_paid_to<=46,'Yes')		as [ORF Paid to Days Month Val],
//      receipt_amount,
//      group_id,
//      create_datetime,
//      method_reference_number; 
//  //   receipt_status;
// SQL SELECT Distinct	r.membership_id, 
// 	r.old_paid_to,
//     r.new_paid_to,
//     r.group_id,
//     r.create_datetime,
//     rm.method_reference_number,
//     r.receipt_amount
// FROM receipt as r 
// JOIN receipt_method as rm on r.receipt_link_id = rm.receipt_link_id
// JOIN receipt_status as rs on r.receipt_id = rs.receipt_id
// WHERE r.receipt_amount = 0 
// AND r.group_id is null 
// AND r.contribution_due is not null;
//Order by r.new_paid_to desc;


// LET vNoRows = NoOfRows('Membership');
// Trace Membership Rows-$(vNoRows);


MembershipTerminations:
LOAD membership_id																as [Membership ID],
	 date(effective_termination_date)											as [Termination Date],
	 termination_code;
SQL SELECT "membership_id",
	"termination_code",
    "effective_termination_date"
FROM paragon.dbo.memship
WHERE memship_status in ('A','T') and termination_code is not null
UNION
SELECT "membership_id",
	"termination_code",
    "effective_termination_date"
FROM paragon.dbo.memship_status_history
WHERE memship_status in ('A','T') and termination_code is not null;


LET vNoRows = NoOfRows('MembershipTerminations');
Trace MembershipTerminations Rows-$(vNoRows);


LEFT JOIN (MembershipTerminations)
LOAD termination_code,
     description																as [Termination DescriptionCheck],
     ApplyMap('TerminationDescriptionMap',description,'Unknown')				as [Termination Description Group];
SQL SELECT "termination_code",
    description
FROM paragon.dbo."termination_code";

TermCheck: 
Load*, 
IF(ISNULL([Termination DescriptionCheck]), 'Downgrade to Ambulance', [Termination DescriptionCheck]) as [Termination Description]
 Resident MembershipTerminations;
 Drop Table MembershipTerminations;
 Rename Table TermCheck to MembershipTerminations;


LET vNoRows = NoOfRows('MembershipTerminations');
Trace MembershipTerminations Rows-$(vNoRows);


CoverChangeModel:
Load
MonthYear as [Cover Change MonthYear],
[Membership ID] as [Cover Change Membership ID],
'To' as Change,
[Hosp Product ID] as [Cover Change Hospital Product],
[Amb/Extras Product ID] as [Cover Change Extras Product],
[Cover Change] as [Cover Change Flag],
[Amb/Extras Cover Change] as [Extras Cover Change Flag],
[Hosp Cover Change] as [Hosp Cover Change Flag]
Resident MemberStats;

Concatenate (CoverChangeModel)
Load
MonthYear as [Cover Change MonthYear],
[Membership ID] as [Cover Change Membership ID],
'From' as Change,
[Old HospProductID] as [Cover Change Hospital Product],
[Old AmbExtras ProductID] as [Cover Change Extras Product],
[Cover Change] as [Cover Change Flag],
[Amb/Extras Cover Change] as [Extras Cover Change Flag],
[Hosp Cover Change] as [Hosp Cover Change Flag]
Resident MemberStats;

Left join (CoverChangeModel)
//NoConcatenate
Load
MonthYear as [Cover Change MonthYear],
[Membership ID] as [Cover Change Membership ID], 
[Membership Status] as [Cover Change Memship Status]
Resident MemberHistory;

Left join (CoverChangeModel)
//NoConcatenate
Load
MonthYear as [Cover Change MonthYear],
[Membership ID] as [Cover Change Membership ID], 
Terminations		as [Cover Change Terminations], 
Joins				as [Cover Change Join]
Resident MemberStats;


CoverChangeDateRange:
Load Distinct
	[Cover Change MonthYear]
Resident CoverChangeModel;

CoverChangeCalendar:
Load Distinct
	[Cover Change MonthYear],
    AutoNumber([Cover Change MonthYear], 'PeriodNo')															as CoverChangePeriodNo,
    Year([Cover Change MonthYear]) 																				as [Cover Change Year],
    if(Month([Cover Change MonthYear]) >= 7, Year([Cover Change MonthYear])+1,Year([Cover Change MonthYear])) 	as [Cover Change Fin Year]
Resident CoverChangeDateRange
order by [Cover Change MonthYear] asc;

DROP Tables MemberHistory;
//*****************************************************************************************************
//*	Rebuild of Targets Link to remove duplication issues, add keys to target tables
//*
//*		Author:	Alex Graydon
//*		Date:	19/01/2023
//*
//*	HISTORY:
//*
//*		Date		Person			Description
//*		19/01/2023	Alex Graydon	Initial Version
//*
//*****************************************************************************************************

RegionTargets:
LOAD MonthName("Date") & '|' & Region							as BranchTrg_KEY,
 	 Region														as Branch,
	 MonthName("Date")											as MonthYear,
     "Joins Target",
     "Terminations Target",
     "Join Avg Premium Target",
     "Term Avg Premium Target",
     "Cover Change Target"
FROM [lib://TransformData (prdqs01_atobi)/MembershipMovements_Targets_2020.qvd] (qvd);
// Where "Date" <= MonthEnd(Today()) ;

// 2021 targets added 28/07/2020 by Colin Hancox

Concatenate (RegionTargets)
LOAD MonthName("Date") & '|' & Region							as BranchTrg_KEY,
 	 Region														as Branch,
	 MonthName("Date")											as MonthYear,
     "Terminations Target"
FROM [lib://TransformData (prdqs01_atobi)/MembershipMovements_Targets.qvd] (qvd);


SalesChannelTargets:
LOAD MonthName("Date") & '|' & "Sales Channel"														as SCTrg_KEY,
 	 IF(WildMatch("Sales Channel", 'Corporate Group'), 'Corporate', "Sales Channel")				as [Sales Channel Group],
	 MonthName("Date")																				as MonthYear,     
     "SC Join Target",
     "SC Join Avg Premium Target",
     "SC Term Avg Premium Target"
FROM [lib://TransformData (prdqs01_atobi)/MembershipMovements_SCTargets_2020.qvd] (qvd);


Concatenate (SalesChannelTargets)
LOAD MonthName("Date") & '|' & "Sales Channel"					as SCTrg_KEY,
 	 IF(WildMatch("Sales Channel", 'Corporate Group'), 'Corporate', "Sales Channel")				as [Sales Channel Group],
	 MonthName("Date")											as MonthYear,
     "SC Join Target",
     "SC Terminations Target"
FROM [lib://TransformData (prdqs01_atobi)/MembershipMovements_SCTargets.qvd] (qvd);


FaceToFaceTargets:
LOAD MonthName("Date")	& '|' & "Sales Channel" & '|' & Branch	as F2FTrg_KEY,
 	 Branch,
	 IF(WildMatch("Sales Channel", 'Corporate Group'), 'Corporate', "Sales Channel")				as [Sales Channel Group],
	 MonthName("Date")											as MonthYear,
     "SCF2F Join Target"										as [F2F Join Target]
FROM [lib://TransformData (prdqs01_atobi)/MembershipMovements_F2FTargets_2020.qvd] (qvd);


Concatenate (FaceToFaceTargets)
LOAD MonthName("Date")	& '|' & "Sales Channel" & '|' & Branch	as F2FTrg_KEY,
 	 Branch,
	 "Sales Channel"											as [Sales Channel Group],
	 MonthName("Date")											as MonthYear,
     "SCF2F Join Target"										as [F2F Join Target]
FROM [lib://TransformData (prdqs01_atobi)/MembershipMovements_F2FTargets.qvd] (qvd);


ProductTargets:
LOAD MonthName("Date") & '|' & "Description Grouped"			as ProductTrg_KEY,
 	 "Description Grouped"										as [Product Target Grouping],
	 MonthName("Date")											as MonthYear,
     "Product Growth Target"
FROM [lib://TransformData (prdqs01_atobi)/MembershipMovements_ProductTargets.qvd] (qvd);


SummaryTargets:
LOAD MonthName("Date") & '|' & "Type"			as SummaryTrg_KEY,
 	 "Type"										as [Target Type],
	 MonthName("Date")											as MonthYear,
     "Overall Target"
FROM [lib://TransformData (prdqs01_atobi)/MembershipMovements_SUMMARYTargets.qvd] (qvd);
//*****************************************************************************************************
//*	Rebuild of Targets Link to remove duplication issues
//*
//*		Author:	Alex Graydon
//*		Date:	19/01/2023
//*
//*	HISTORY:
//*
//*		Date		Person			Description
//*		19/01/2023	Alex Graydon	Initial Version
//*
//*****************************************************************************************************

Link:
LOAD Distinct "Membership ID",
	 MonthYear,
     MonthYear														as LinkMonthYear,
     "Product Target Grouping",
//     "Target Type",
     "Sales Channel Group",
     Branch,
     MonthYear & '|' & "Membership ID"								as Membership_KEY,
     MonthYear & '|' & "Product Target Grouping"					as ProductTrg_KEY,
     MonthYear & '|' & "Product Target Grouping"					as ProductTrg_KEY_MS,
//     MonthYear & '|' & "Target Type"								as SummaryTrg_KEY,
//     MonthYear & '|' & "Target Type"								as SummaryTrg_KEY_MS,
     MonthYear & '|' & "Sales Channel Group"						as SCTrg_KEY,
     MonthYear & '|' & "Sales Channel Group"						as SCTrg_KEY_MS,
     MonthYear & '|' & Branch										as BranchTrg_KEY,
     MonthYear & '|' & Branch										as BranchTrg_KEY_MS,
     MonthYear & '|' & "Sales Channel Group" & '|' & Branch			as F2FTrg_KEY,
     MonthYear & '|' & "Sales Channel Group" & '|' & Branch			as F2FTrg_KEY_MS
RESIDENT MemberStats
WHERE MonthName(MonthYear)<=MonthName(Today());


//Add any missing Target/Months so that filtering on Month does not remove the target when there are no members

CONCATENATE (Link)
LOAD Distinct BranchTrg_KEY,
	 MonthYear,
	 Branch
RESIDENT RegionTargets
WHERE Not Exists(BranchTrg_KEY_MS,BranchTrg_KEY)
AND Exists(LinkMonthYear,MonthYear);

CONCATENATE (Link)
LOAD Distinct SCTrg_KEY,
	 MonthYear,
	 "Sales Channel Group"
RESIDENT SalesChannelTargets
WHERE Not Exists(SCTrg_KEY_MS,SCTrg_KEY)
AND Exists(LinkMonthYear,MonthYear);

CONCATENATE (Link)
LOAD Distinct F2FTrg_KEY,
	 MonthYear,
     Branch,
	 "Sales Channel Group"
RESIDENT FaceToFaceTargets
WHERE Not Exists(F2FTrg_KEY_MS,F2FTrg_KEY)
AND Exists(LinkMonthYear,MonthYear);

CONCATENATE (Link)
LOAD Distinct ProductTrg_KEY,
	 MonthYear,
	 "Product Target Grouping"
RESIDENT ProductTargets
WHERE Not Exists(ProductTrg_KEY_MS,ProductTrg_KEY)
AND Exists(LinkMonthYear,MonthYear);

// CONCATENATE (Link)
// LOAD Distinct SummaryTrg_KEY,
// 	 MonthYear,
// 	 "Target Type"
// RESIDENT SummaryTargets
// WHERE Not Exists(SummaryTrg_KEY_MS,SummaryTrg_KEY)
// AND Exists(LinkMonthYear,MonthYear);

DROP Fields BranchTrg_KEY_MS, SCTrg_KEY_MS, F2FTrg_KEY_MS, ProductTrg_KEY_MS, LinkMonthYear; 
DROP Fields MonthYear, "Membership ID", "Product Target Grouping", "Sales Channel Group", Branch FROM MemberStats;
DROP Fields MonthYear, Branch FROM RegionTargets;
DROP Fields MonthYear, "Sales Channel Group" FROM SalesChannelTargets;
DROP Fields MonthYear, Branch, "Sales Channel Group" FROM FaceToFaceTargets;
DROP Fields MonthYear, "Product Target Grouping" FROM ProductTargets;
//DROP Fields MonthYear, "Target Type" FROM SummaryTargets;

// MemberStats2:
// load *,
// 	 MonthYear&'|'&"Sales Channel GroupTMP"				as SCTrg_KEY,
//      MonthYear&'|'&Branch								as BranchTrg_KEY,
//      MonthYear&'|'&"Sales Channel"&'|'&Branch			as F2FTrg_KEY, 
//      MonthYear&'|'&"Product Target Grouping" 			as ProductTrg_KEY
// Resident MemberStats;

// drop Table MemberStats;

// rename Table MemberStats2 to MemberStats;

// RegionTargetsKey:
// load *,
//      MonthYear&'|'&Branch						as BranchTrg_KEY
// Resident RegionTargets;

// drop Table RegionTargets;
// rename Table RegionTargetsKey to RegionTargets;

// SalesChannelTargetsKey:
// load *,
//      MonthYear&'|'&"Sales Channel GroupTMP"		as SCTrg_KEY
// Resident SalesChannelTargets;

// drop Table SalesChannelTargets;
// rename Table SalesChannelTargetsKey to SalesChannelTargets;

// FaceToFaceTargetsKey:
// load *,
//      MonthYear&'|'&"Sales Channel GroupTMP"&'|'&Branch	as F2FTrg_KEY
// Resident FaceToFaceTargets;

// drop Table FaceToFaceTargets;
// rename Table FaceToFaceTargetsKey to FaceToFaceTargets;

// ProductTargetsKey:
// load*, 
//      MonthYear&'|'&"Product Target Grouping"						as ProductTrg_KEY
// Resident ProductTargets;
// drop Table ProductTargets;
// rename Table ProductTargetsKey to ProductTargets;

// Link:
// Load Distinct
// 	 MonthYear,
//      "Product Target Grouping",
//      "Sales Channel GroupTMP",
//      Branch,
//      ProductTrg_KEY,
//      SCTrg_KEY,
//      BranchTrg_KEY,
//      F2FTrg_KEY
// Resident MemberStats
// where MonthName(MonthYear)<=MonthName(Today());

// Concatenate (Link)
// Load Distinct
// //	'RegionTargets'								as LinkSource,
//     BranchTrg_KEY,
// 	Branch,
//     MonthYear
// Resident RegionTargets
// where MonthName(MonthYear)<=MonthName(Today());

// Concatenate(Link)
// LOAD Distinct
// //    'SalesChannelTargets'						as LinkSource,
//     SCTrg_KEY,
//     "Sales Channel GroupTMP",
//     MonthYear
// Resident SalesChannelTargets
// where MonthName(MonthYear)<=MonthName(Today());

// Concatenate(Link)
// LOAD Distinct
// //    'SalesChannelTargets'						as LinkSource,
//     ProductTrg_KEY,
//     "Product Target Grouping",
//     MonthYear
// Resident ProductTargets
// where MonthName(MonthYear)<=MonthName(Today());

// Concatenate(Link)
// LOAD Distinct
// //    'FaceToFaceTargets'							as LinkSource,
//     F2FTrg_KEY,
//     "Sales Channel GroupTMP",
//     Branch,
//     MonthYear
// Resident FaceToFaceTargets
// where MonthName(MonthYear)<=MonthName(Today());

// drop Fields MonthYear, "Product Target Grouping", "Sales Channel GroupTMP", Branch, ProductTrg_KEY, SCTrg_KEY, BranchTrg_KEY from MemberStats;

// drop Fields MonthYear, "Product Target Grouping", "Sales Channel GroupTMP", Branch from RegionTargets;
// drop Fields MonthYear, "Product Target Grouping", "Sales Channel GroupTMP", Branch from SalesChannelTargets;
// drop Fields MonthYear, "Product Target Grouping", "Sales Channel GroupTMP", Branch from FaceToFaceTargets;
// drop Fields MonthYear, "Product Target Grouping", "Sales Channel GroupTMP", Branch from ProductTargets;
DateRange:
Load Distinct
	MonthYear
Resident Link;

Calendar:
Load Distinct
	MonthYear,
    AutoNumber(MonthYear, 'PeriodNo')								as PeriodNo,
    Year(MonthYear) 												as Year,
    if(Month(MonthYear) >= 7, Year(MonthYear)+1,Year(MonthYear)) 	as [Fin Year],
    Month(MonthYear) 												as Month,
    'Q' & Ceil(Month(MonthYear)/3) 									as Quarter,
    Year(MonthYear)&'-Q' & Ceil(Month(MonthYear)/3) 				as YearQuarter,
    Year(MonthYear)&Num(Month(MonthYear), 00)						as Period,
    if(Month(MonthYear) >= 7, Year(MonthYear)+1,Year(MonthYear))
    &Num(Month(MonthYear), 00)										as FinPeriod
Resident DateRange
order by MonthYear asc;

MasterCalendar:
NoConcatenate
Load*,
    AutoNumber([Fin Year],'FinYearID')                              as [FinYearID],
    AutoNumber(MonthYear, 'PeriodID')                               as [PeriodID],
    if(MonthYear >= AddMonths(Today(), -36), 'Yes', 'N/A')          as [Last 3 Years],
    if(MonthYear >= AddMonths(Today(), -3), 'Yes', 'No')           										as [Last Quarter],
    If([Fin Year] >= Year(Today()) - 2, [Fin Year] & '-Q' & Ceil(Month(MonthYear)/3)) 					as [FinYearQuarter]
Resident Calendar
Order by MonthYear Asc;

// FinYearQuarter:
// LOAD *,
//     [Fin Year] & '-Q' & Ceil(Month([MonthYear])/3) 						as [FinYearQuarter]
// Resident Calendar
// Order by FinYearCalendar Asc;    
// Drop table DateRange;


// ======== Create a list of distinct Months ========
// tmpAsOfCalendar:
// Load distinct MonthYear
//   Resident [MasterCalendar] ;

// ======== Cartesian product with itself ========
Join (Calendar)
Load MonthYear as AsOfMonth
  Resident Calendar;

// ======== Reload, filter and calculate additional fields ========
[As-Of Calendar]:
Load MonthYear,
  MonthName(AsOfMonth)												as AsOfMonth,
  AutoNumber(AsOfMonth, 'AsOfMonthID')								as AsOfPeriodNo,
  Round((AsOfMonth-MonthYear)*12/365.2425) 							as MonthDiff,
  Year(AsOfMonth)-Year(MonthYear) 									as YearDiff
  Resident Calendar
      Where AsOfMonth >= MonthYear
      order by AsOfMonth;

Drop Table Calendar;

CalendarIsland:
LOAD Distinct [Fin Year]						as FinYearIsland,
	 PeriodID								as PeriodIDIsland
RESIDENT MasterCalendar;
// ProductCodeMap:
// mapping
// LOAD Distinct
//     product_id,
//     product_code
// FROM [lib://ExtractData (prdqs01_atobi)/Paragon_Product.qvd]
// (qvd);

// AllFees:
// LOAD
//     State,
//     "Cover Type",
//     "Product ID",
//     ApplyMap('ProductCodeMap', "Product ID")	as [Product Code],
//     "Weekly Fee Amount",
//     MonthYear
// FROM [lib://ExtractData (prdqs01_atobi)/Product_Weekly_Fees.qvd]
// (qvd);

// ProductFeeMap:
// //Mapping
// load Distinct
// 	 [Product Code]&'>'&[State]&'>'&[Cover Type]&'>'&MonthYear		as prodkey,
//      [Weekly Fee Amount]
// Resident AllFees;

// drop Table AllFees;


// Exit Script;
Leads: 
LOAD
    person_id										as [Person ID],
    create_operator									as [Lead Operator],
    Monthname(create_datetime)						as [Lead MonthYear],
    Weekend(create_datetime)						as [Lead Weekend],
    membership_id									as membership_id,
    grp_group_id									as [Agent ID];
SQL SELECT p.person_id, q.membership_id, q.create_operator, q.create_datetime, q.grp_group_id
From person as p 
left join 
(Select  q.person_id, q.create_datetime, q.create_operator, q.grp_group_id, q.membership_id
from quotation as q 
where q.perspective_memship in (Select Max(qu.perspective_memship) 
								from quotation as qu 
								where qu.person_id = q.person_id and qu.create_datetime>= '2020-01-31')) as q on p.person_id = q.person_id
                                
                                where q.membership_id is null;	


Left join (Leads)
LOAD
    group_id							as [Agent ID],
    group_type							as [Agent Type],
   If(Wildmatch(description, 'CTM', 'Westfund Staff', 'Web Join', 'Westfund Staff', 'Compare Health', 'Choosi', 'Biloela Agency',
   								'Blackwater', 'Covad', 'Dysart Agency', 'Forbes Agency', 'John Small Brokerage', 'Kalgoorlie Agency', 
                                'Katoomba Agency', 'Moura Agency-First National', 'Rylstone Agency', 'Sarina Agency', 
                                'Telephone Sales', 'Union Shopper', 'Wellington Agency'), 'Other', description)							as [Agent Description]
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_Grouping.qvd]
(qvd) where group_type = 'A' and not isnull(description);


Left Join (Leads) 
LOAD
person_id                            	as [Person ID],
sales_channel_id						as [lead Sales Channel ID], 
sales_channel_description				as [SalesChannel];
SQL SELECT 
    "person_id",
    "sales_channel_id",
    "sales_channel_description"
FROM paragon.dbo.LatestPromoSalesChannelByPerson;

SalesChannel:
Load*, 
If([Lead Operator] = 'WEB', 'WEB', [SalesChannel])  as  [LeadSalesChannel], 
If([Lead Operator] <> [SalesChannel], 'Flag', 'Okay')		as [State Flag]
Resident Leads;
Drop table Leads;
Rename table SalesChannel to Leads;

LeadSalesChannelCont:
Load*, 
IF(Wildmatch([LeadSalesChannel], 'Health Deal', 'Choosi', 'Compare the Market', 'Covad', 'Field Days', 'JCU Dental Cairns', 'John Small',
								'No Channel', 'Other', 'Sept/Oct Upgrade Promo 2012', 'Sunshine Coast Regional Council',
                                'Union Shopper', 'Compare Health','Shopping Centre'), 'Other',
IF(Wildmatch([LeadSalesChannel], 'Phone', 'Corporate Group', 'Web Assist', 'Branch Direct Phone'), 'Phone',

IF(Wildmatch([LeadSalesChannel], 'WEB', 'Internet'), 'WEB',

IF(Wildmatch([LeadSalesChannel], 'F2F-External activity', 'F2F-Care Centre Walk-in', 'Face to Face', 'Corporate F2F', 'Paper'), 'Face to Face', 
IF(ISNULL([LeadSalesChannel]), 'Other', [LeadSalesChannel])))))  as [Lead Sales Channel]
Resident Leads;
Drop Table Leads;
Rename Table LeadSalesChannelCont to Leads;





/*////////////////////////////////////////////////////////////////////////
//	Initial Version 
//		Created By:		Monique Rust
//		Details:	Ambulance Membership Movement
//
//
//
//		Change Log:
//		22.5.24 Copied & pasted existing membership logic. Altered data model to capture ambulance joins & terminations
////////////////////////////////////////////////////////////////////////*/



// Seperate data model to look at movement in Ambulance Memberships. This uses the existing logic (MemberHistory QVD is generated in the profitability qvd generator using the group key report)
AMBMemberHistory:
LOAD LOM																		as AMBLOMTMP,
    "Age"																		as AMBAgeTMP,
    "Membership ID"																as [AMB Membership ID],
//     Arrears,
//     Advance,
    MonthYear																	as AMBMonthYear,
//     HospitalArrears,
//     HospitalAdvance,
//     ExtrasArrears,
//     ExtrasAdvance,
    SEU																			as [AMBSEU],
//     "Hospital %",
//     "Extras %",
//     "QuarterEnd",
    "Effective Join Date"														as AMBEffectiveJoinDateTMP,
    "Effective Termination Date"												as AMBEffectiveTerminationDateTMP,
    "Date of Birth" as [AMB DOB],
    Gender			as [AMB Gender],
    Cover																		as AMBCoverTMP,
    "Product Code"																as AMBProductCodeTMP,
    "Hospital Product"															as AMBHospProductIDTMP,				//shayley
    "Amb/Extras Product"														as AMBAmbExtrasProductIDTMP,			//shayley
    hosp_product																as AMBHospProductTMP,
    amb_extras_product															as AMBAMBExtrasProductTMP,
    State																		as AMBStateTMP,
    Branch																		as AMBBranchTMP,
    "Cover Type"																as AMBCoverTypeTMP,
    pick(match("Membership Status", 'A','T'), 'Active','Terminated')			as "AMBMembership Status",
    pick(match("Membership Status", 'A','T'), 1,0)								as AMBActiveMember,
    Postcode																	as AMBPostcodeTMP,
    "Sales Channel"																as AMBSalesChannelTMP,
    "Billing Frequence"															as AMBBillingFrequenceTMP,
    AgeCohort																	as AMBAgeCohortTMP,
    LOMCohort																	as AMBLOMCohortTMP,
    HospFee																		as AMBHospFeeTMP,
    ExtrasFee																	as AMBExtrasFeeTMP,
    alt(HospFee, 0)+alt(ExtrasFee, 0)											as [AMBProduct Fee],
    COALESCE("Agent Description",'No Agency')									as AMBAgentDescriptionTMP,
    COALESCE([Promotion Description], 'No Promotion')							as AMBPromotionDescriptionTMP,
    'MemberHistory'																as AMBSource
FROM [lib://ExtractData (prdqs01_atobi)/MemberHistory.qvd] (qvd)
WHERE Match("Product Code", 'AMBU');

// To bring in month to date (MTD) joins/terms and relevant fields. Ambulance Only 
AMBCurrentMonthSnapshot:
LOAD *,
	 Age(AMBMonthYear,"AMB Date of Birth")												as AMBAgeTMP,
	 Age(Coalesce(AMBEffectiveTerminationDateTMP,AMBMonthYear),AMBEffectiveJoinDateTMP)	as AMBLOMTMP;
     
LOAD Distinct "Membership Number"												as "AMB Membership ID",
    state																		as AMBStateTMP,
    "Cover Type"																as AMBCoverTypeTMP,
//    termination_code															as TerminationCodeTMP,	
//    fund_id,
    "Membership Status" 														as [AMB Membership Status],
    if((match("Membership Status", 'Active') 
    		and date("Effective Join Date") <= date(Today()))
    	or (match("Membership Status", 'Terminated') 
        	and date("Effective Termination Date") > date(Today())),1,0)		as AMBActiveMember,
    "Effective Join Date"														as AMBEffectiveJoinDateTMP,
    "Effective Termination Date"												as AMBEffectiveTerminationDateTMP,
    MonthName("SnapShot Date")													as AMBMonthYear,
    "Create Operator"															as [AMB Create Operator],
//    "Agent ID",
     COALESCE(Agent,'No Agency')												as AMBAgentDescriptionTMP,
//    "Branch ID",
    Branch																		as AMBBranchTMP,
    "Product Code"																as AMBProductCodeTMP,
    "Cover Description"															as AMBCoverTMP,
    "Product Description"														as [AMB Product Description],
//    "Cover Type Description"													as CoverTypeTMP,
//    "Person Count",
//     "Person ID",
//     "Max Person Version",
//     "Hear About",
    "Date of Birth"																as [AMB Date of Birth],
    "Person Postcode"															as AMBPostcodeTMP,
//    status_date,
    COALESCE(ApplyMap('PromotionMapping',"Promotion ID", 'No Promotion'), 'No Promotion')									as [AMBPromotionDescriptionTMP],
    "Sales Channel"																as AMBSalesChannelTMP,
     'MemberSnapshot'															as AMBSource
//     "Weekly Total Premium",
//     "Annual Total Premium"
FROM [lib://TransformData (prdqs01_atobi)/Membership Snapshots/Membership_SnapShot_Latest.qvd] (qvd)
WHERE ((match("Membership Status", 'Active') AND date("Effective Join Date") <= date(Today())) 
OR (match("Membership Status", 'Terminated') AND date("Effective Termination Date") > date(Today())))
AND WildMatch("Product Description", '*Ambul*');


// Cohort tables are dropped later on to remove synthetic keys
AMBAgeCohorts:
LOAD * inline [
AMBagemin, AMBagemax, AMBAgeCohortTMP
-10, 24, 0-24
25, 34, 25-34
35, 44, 35-44
45, 54, 45-54
55, 64, 55-64
65, 74, 65-74
75, 84, 75-84
85, 199, 85+
];


LEFT JOIN IntervalMatch (AMBAgeTMP) 
LOAD AMBagemin, 
	 AMBagemax
RESIDENT AMBAgeCohorts;


LEFT JOIN (AMBCurrentMonthSnapshot)
LOAD AMBAgeTMP,
	 AMBAgeCohortTMP
RESIDENT AMBAgeCohorts;


AMBLOMCohorts:
LOAD * inline [
AMBlommin, AMBlommax, AMBLOMCohortTMP
-10, 0.99, <1
1, 2, 1-2
3, 4, 3-4
5, 7, 5-7
8, 10, 8-10
11, 15, 11-15
16, 20, 16-20
21, 199, 21+
];


LEFT JOIN IntervalMatch (AMBLOMTMP) 
LOAD AMBlommin, 
	 AMBlommax
RESIDENT AMBLOMCohorts;


LEFT JOIN (AMBCurrentMonthSnapshot)
LOAD [AMBLOMTMP],
	 AMBLOMCohortTMP
RESIDENT AMBLOMCohorts;


Concatenate (AMBMemberHistory)
LOAD * Resident AMBCurrentMonthSnapshot;

// The below section will be used to identify new joins & terminations. 
// A termination will have a null [AMBCoverTMP] (from first MemberHistory table) field after this table has been included (outer join with an addmonth of 1) 
// A new join will have a null [AMBOld Cover]
// If a member upgrades, this will be counted as a termination due to the "WHERE Match("Product Code", 'AMBU');" section in the resident table AMBMemberHistory

OUTER JOIN (AMBMemberHistory)
LOAD [AMB Membership ID],
	 MonthName(AddMonths(AMBMonthYear, 1))											as AMBMonthYear,
	 AMBLOMTMP																		as [AMBOld LOM],
     AMBAgeTMP																		as [AMBOld Age],
//     TerminationCodeTMP															as [Old TerminationCode],
     AMBEffectiveJoinDateTMP														as [AMBOld Effective Join Date],
     AMBEffectiveTerminationDateTMP												as [AMBOld Effective Termination Date],
     AMBCoverTMP																	as [AMBOld Cover],
     AMBProductCodeTMP																as [AMBOld Product Code],
     ApplyMap('ProductStringMap',AMBProductCodeTMP,'Missing')						as [AMBOld Product String Description],     
     AMBHospProductIDTMP															as [AMBOld HospProductID],
     AMBAmbExtrasProductIDTMP														as [AMBOld AmbExtras ProductID],
     AMBStateTMP																	as [AMBOld State],
     AMBBranchTMP																	as [AMBOld Branch],
     ApplyMap('CoverTypeMapping',"AMBCoverTypeTMP", 'Missing')						as [AMBOld Cover Type],
     AMBPostcodeTMP																as [AMBOld Postcode],
     AMBSalesChannelTMP															as [AMBOld Sales Channel],
     AMBBillingFrequenceTMP														as [AMBOld Billing Frequence],
     AMBAgeCohortTMP																as [AMBOld AgeCohort],
     AMBLOMCohortTMP																as [AMBOld LOMCohort],
     AMBHospFeeTMP																	as [AMBOld HospFee],
     AMBExtrasFeeTMP																as [AMBOld ExtrasFee],
     [AMBProduct Fee]																as [AMBOld Product Fee],
     AMBAgentDescriptionTMP														as [AMBOld Agent Description],
     AMBPromotionDescriptionTMP 													as [AMBOld Promotion Description],
	AMBHospProductTMP																as AMBHospProductOLD,
    AMBAMBExtrasProductTMP															as AMBAMBExtrasProductOLD
RESIDENT AMBMemberHistory
WHERE AMBSource = 'MemberHistory';
//FROM [lib://ExtractData (prdqs01_atobi)/MemberHistory.qvd] (qvd)
//WHERE Match("Product Code", 'AMBU')=0;


//MemberStats applies maps and additional logic
AMBMemberStats:
NoConcatenate
LOAD *,
	if(wildmatch([AMBProduct String Description],'*Overse*'),'Overseas',
		if(wildmatch([AMBProduct String Description],'*&*','*with*'),'Combined',
			if(WildMatch([AMBProduct String Description],'*Hospital*'),'Hospital Only',
    			if(WildMatch([AMBProduct String Description],'*Extra*'),'Extras Only',
        			if(WildMatch([AMBProduct String Description],'*Ambul*'),'Ambulance')))))													as [AMBProduct Type],
                        ;

// AG 21/06/2023 Determine Agent/Sales Channel to use New after 1.7.23 and Old before
LOAD *,
	 If(AMBMonthYear > MakeDate(2023,06,30),[AMBSales Channel Group New Logic],[AMBSales Channel Group Old Logic])									as [AMBSales Channel Group],
     If(AMBMonthYear > MakeDate(2023,06,30),[AMBAgent New Logic],[AMBAgent Old Logic])																as AMBAgent,
     If(AMBMonthYear > MakeDate(2022,06,30),[AMBPromotion New Logic],[AMBPromotion Old Logic])														as AMBPromotion;

LOAD *,
	 AMBMonthYear & '|' & "AMB Membership ID"																										as AMBMembership_KEY,
	 if(IsNull(AMBCoverTMP), [AMBOld Cover], AMBCoverTMP)																							as AMBCover,	
     ApplyMap('ProductStringMap',if(IsNull(AMBProductCodeTMP), [AMBOld Product Code], AMBProductCodeTMP),'Missing')									as [AMBProduct String Description],
	 if(IsNull(AMBEffectiveJoinDateTMP), [AMBOld Effective Join Date], AMBEffectiveJoinDateTMP)														as [AMBEffective Join Date],
	 if(IsNull(AMBEffectiveTerminationDateTMP), [AMBOld Effective Termination Date], AMBEffectiveTerminationDateTMP)									as [AMBEffective Termination Date],
	 if(IsNull(AMBStateTMP), [AMBOld State], AMBStateTMP)																							as AMBState,
	 if(IsNull(AMBBranchTMP), [AMBOld Branch], AMBBranchTMP)																							as AMBBranch, 
     ApplyMap('BranchGroupMapping',if(IsNull(AMBBranchTMP), [AMBOld Branch], AMBBranchTMP),'Unknown')												as [AMBBranch Grouping],     
     Coalesce(AMBAgentDescriptionTMP,[AMBOld Agent Description])																					as [AMBAgent New Logic], 				// AG from 1.7.23     
     Coalesce(AMBPromotionDescriptionTMP,[AMBOld Promotion Description])																			as [AMBPromotion New Logic], 			// MR From 1.7.22
     If(WildMatch(Coalesce(AMBAgentDescriptionTMP,[AMBOld Agent Description]),'No Agency','No Agent','CTM','Web Join','Compare Health','Choosi',
     	'Biloela Agency','Blackwater Agency','Blackwater','Covad','Dysart Agency','Forbes Agency','John Small Brokerage','Kalgoorlie Agency','Katoomba Agency',
        'Moura Agency - First National', 'Rylstone Agency', 'Sarina Agency','Telephone Sales', 'Union Shopper', 
        'Wellington Agency', 'YourShare','HICA Agency','YourShare', '*Parkes Agency*'),
     	ApplyMap('SalesChannelMapping',Coalesce(AMBSalesChannelTMP,[AMBOld Sales Channel]),'No Channel Group'),'Corporate')						as [AMBSales Channel Group New Logic], // AG from 1.7.23                   
     ApplyMap('AgentMap',"AMB Membership ID",'No Agency')																						as [AMBAgent Old Logic], 	// AG Pre 1.7.23
     ApplyMap('PromoMap',"AMB Membership ID",'No Promotion')																					as [AMBPromotion Old Logic], 	// MR Pre 1.7.23
     IF(WildMatch(ApplyMap('AgentMap',"AMB Membership ID",'No Agency'),'No Agency','No Agent'), 
     	ApplyMap('SalesChannelMapping',Coalesce(AMBSalesChannelTMP,[AMBOld Sales Channel]),'No Channel Group'),'Corporate') 						as [AMBSales Channel Group Old Logic],	// AG Pre 1.7.23
     if(IsNull(AMBLOMTMP), [AMBOld LOM], AMBLOMTMP)																									as AMBLOM,
     if(IsNull(AMBAgeTMP), [AMBOld Age], AMBAgeTMP)																									as AMBAge,
     if(IsNull(AMBAgeCohortTMP), [AMBOld AgeCohort], AMBAgeCohortTMP)																				as AMBAgeCohort,
     if(IsNull(AMBLOMCohortTMP), [AMBOld LOMCohort], AMBLOMCohortTMP)																				as AMBLOMCohort,
     if(IsNull(AMBExtrasFeeTMP), [AMBOld ExtrasFee], AMBExtrasFeeTMP)																				as [AMBAmb/Extras Fee],
	 ApplyMap('CoverTypeMapping',if(IsNull(AMBCoverTypeTMP), [AMBOld Cover Type], AMBCoverTypeTMP),[AMBOld Cover Type])									as [AMBCover Type],
     if(isnull([AMBOld Cover Type]), 'Missing', [AMBOld Cover Type])																				as [AMBTerminated Cover Type],
	 text(num(if(IsNull(AMBPostcodeTMP), [AMBOld Postcode], AMBPostcodeTMP), 0000))																	as AMBPostcode,
	 if(IsNull(AMBCoverTMP), 1, 0)																												as AMBTerminations,
	 if(IsNull([AMBOld Cover]), 1, 0)																											as AMBJoins
     
RESIDENT AMBMemberHistory;

DROP Fields 
//	 CoverTMP, 
//     [Old Cover], 
	 AMBProductCodeTMP, 
//     [Old Product Code], 
	 AMBHospProductIDTMP, 
//     [Old HospProductID],
//	 [AmbExtrasProductIDTMP], 
//     [Old AmbExtras ProductID],
	 AMBEffectiveJoinDateTMP, 
//     [Old Effective Join Date],
	 AMBEffectiveTerminationDateTMP, 
//     [Old Effective Termination Date],
// 	 TerminationCodeTMP,
//      [Old TerminationCode],
	 AMBStateTMP, 
//     [Old State],	
	 AMBBranchTMP, 
//     [Old Branch],
     AMBAgeTMP, 
//     [Old Age],
     AMBLOMTMP, 
//     [Old LOM],
     AMBAgeCohortTMP, 
//     [Old AgeCohort],
     AMBLOMCohortTMP,
//     [Old LOMCohort],
     AMBHospFeeTMP,
//     [Old HospFee],
     AMBExtrasFeeTMP,
//     [Old ExtrasFee],
	 AMBCoverTypeTMP,
//     [Old Cover Type],
	 AMBPostcodeTMP, 
//     [Old Postcode],	 
     AMBSalesChannelTMP,
//     [Old Sales Channel]
//	[Sales Channel GroupTMP],
     AMBAgentDescriptionTMP
;
 
 
//CurremtMemberCover to determine genuine terms (a non-genuine termination does not have a current ambulance cover - these are members that has upgraded.)  
CurrentMembershipCover:
LOAD
    membership_id as [AMB Membership ID],
    //cover_type,
    //FixCode,
    Product_Description as [Current Product Description]
//     Hospital_Product_id,
//     Extras_Product_id,
//     Hospital_Product_Code,
//     Extras_Product_Code
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_MemberCover.qvd]
(qvd);

AMBMembershipTerminations:
LOAD membership_id																as [AMB Membership ID],
	 date(effective_termination_date)											as [AMB Termination Date],
	 termination_code as [AMB Term Code];
SQL SELECT "membership_id",
	"termination_code",
    "effective_termination_date"
FROM paragon.dbo.memship
WHERE memship_status in ('A','T') and termination_code is not null;


LET vNoRows = NoOfRows('MembershipTerminations');
Trace MembershipTerminations Rows-$(vNoRows);


LEFT JOIN (AMBMembershipTerminations)
LOAD termination_code															as [AMB Term Code],
     description																as [AMBTermination Description],
     ApplyMap('TerminationDescriptionMap',description,'Unknown')				as [AMBTermination Description Group];
SQL SELECT "termination_code",
    description
FROM paragon.dbo."termination_code";
 
// Drop tables to remove synthetic keys (the relevant fields are in the AMBMemberStats table) 
DROP Tables AMBMemberHistory;

DROP Tables AMBAgeCohorts,AMBLOMCohorts,AMBCurrentMonthSnapshot;




//Dates for ambulance data model - [AMBPeriodID] is used for the max period total members calc so it does not display a total sum

AMBDateRange:
Load Distinct
	AMBMonthYear
Resident AMBMemberStats;

AMBCalendar:
Load Distinct
	AMBMonthYear,
    Year(AMBMonthYear) 												as AMBYear,
    if(Month(AMBMonthYear) >= 7, Year(AMBMonthYear)+1,Year(AMBMonthYear)) 	as [AMBFin Year],
    Month(AMBMonthYear) 												as AMBMonth,
    'Q' & Ceil(Month(AMBMonthYear)/3) 									as AMBQuarter,
    Year(AMBMonthYear)&'-Q' & Ceil(Month(AMBMonthYear)/3) 				as AMBYearQuarter,
    Year(AMBMonthYear)&Num(Month(AMBMonthYear), 00)						as AMBPeriod,
    if(Month(AMBMonthYear) >= 7, Year(AMBMonthYear)+1,Year(AMBMonthYear))
    &Num(Month(AMBMonthYear), 00)										as AMBFinPeriod
Resident AMBDateRange
order by AMBMonthYear asc;

AMBMasterCalendar:
NoConcatenate
Load*,
    AutoNumber([AMBFin Year],'FinYearID')                              as [AMBFinYearID],
    AutoNumber(AMBMonthYear, 'PeriodID')                               as [AMBPeriodID],
    AutoNumber(AMBMonthYear, 'PeriodNo')								as AMBPeriodNo
Resident AMBCalendar
Order by AMBMonthYear Asc;

Drop table AMBDateRange;
Drop Table AMBCalendar;


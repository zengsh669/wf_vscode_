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


SecurityMap:
Mapping
LOAD
    security_level,
    description
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_security_level.qvd]
(qvd);

[ArrearsReportPayroll]: 
LOAD
    membership_id 										as [Membership ID],
    memship_status,
    date(floor(date_paidto)) 							as [Date Paid To],
//    Num((today() - date_paidto),0) 						as DaysInArrears,
    ApplyMap('SecurityMap',security_level,'Unknown')	as [Security Level]
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_memship.qvd]
(qvd) WHERE memship_status = 'A' ;

left join ([ArrearsReportPayroll])
LOAD
    person_id,
    membership_id 										as [Membership ID],
    relationship
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_PersonMembership.qvd]
(qvd) WHERE relationship = 1;

 
left join ([ArrearsReportPayroll])
LOAD
    description 										AS Branch,
    membership_id 										as [Membership ID]
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_MemberBranch.qvd]
(qvd);

left join ([ArrearsReportPayroll])
LOAD
    membership_id 										as [Membership ID],
    FixCode,
    Product_Description
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_MemberCover.qvd]
(qvd);

left join ([ArrearsReportPayroll])
LOAD
    group_id,
    membership_id 										as [Membership ID]
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_MemberGroup.qvd]
(qvd);

left join ([ArrearsReportPayroll])
LOAD
    person_id,
    surname,
    first_name,
    first_name&' '&surname 								as name
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_Person.qvd]
(qvd);

left join ([ArrearsReportPayroll])
LOAD
    group_id,
    description 										as GroupingDesc
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_Grouping.qvd]
(qvd);

left join ([ArrearsReportPayroll])
LOAD
    group_id,
    billing_type,
    billing_freq,
    tpt_period											as [Tpt Period]
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_Billing_Group.qvd]
(qvd);

left join ([ArrearsReportPayroll])
LOAD
    membership_id								as [Membership ID],
    description									as AgentDesc
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_MemberAgent.qvd]
(qvd);

LIB CONNECT TO 'rpsqlrp01 - paragonreporting';
left Join ([ArrearsReportPayroll])
LOAD "main_ref_id" 											as [Membership ID],
    "postal_preference"										as [Post Preference],
    "main_ref_type"											as [Main Ref Type];
SQL SELECT *
FROM paragonreporting.dbo.web_security
WHERE "main_ref_type" = 'M';

RegisteredMO:
LOAD*,
  If([Post Preference] = 'E', 'Email',
    If([Post Preference] = 'P', 'Postal',
    	IF(ISNULL([Post Preference]), 'Not Registered to MO', 'Not Registered to MO')))	as [Postal Preference]
Resident [ArrearsReportPayroll];
Drop Table [ArrearsReportPayroll];
Rename Table RegisteredMO to [ArrearsReportPayroll];


Inner join ([ArrearsReportPayroll])
LOAD
    billing_type,
    description 															as BillingDes,
    if(description = 'Payroll','Payroll',
    if(wildmatch(description, '*Direct*'),'Direct Debit/Payer','Other')) 	as [Payment Type]
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_Billing_Type.qvd]
(qvd); 
//WHERE description = 'Payroll';


Inner join ([ArrearsReportPayroll])
LOAD * INLINE [
    billing_freq, typebill, amount
    0, d, 1
    1, d, 7
    2, d, 14
    3, d, 28
    4, m, 1
    5, m, 2
    6, m, 3
    7, m, 6
    8, m, 12
    9, d, 1
];

Bucket1:
LOAD *,
    if([Security Level] = 'No Access Restrictions',name,[Security Level]) 													as [Name],
    IF(typebill = 'd',
        Date(Floor([Date Paid To] + (amount * [Tpt Period]))),
        AddMonths([Date Paid To], amount * [Tpt Period])
    ) 																														AS [tpt_day],
    if(Product_Description = 'Ambulance', 'Ambulance Product','Non Ambulance Products') 									as [Directdebitfilter]
Resident [ArrearsReportPayroll];
Drop Table [ArrearsReportPayroll];
Rename Table Bucket1 to [ArrearsReportPayroll];

Bucket2:
LOAD *,
    NUM(Today() - [Date Paid To], 0)                                             							AS [DaysInArrears],
    Today()                                                                      							AS [Run Date],
    Date(MonthStart(Today()), 'MMM YYYY')                                       							AS [Run Month]
Resident [ArrearsReportPayroll];
Drop Table [ArrearsReportPayroll];
Rename Table Bucket2 to [ArrearsReportPayroll];

Bucket3:
Load*,
   If([DaysInArrears] > 57 , '58 Days plus in arrears',
   	(IF([DaysInArrears] > 44 and [DaysInArrears] <= 57 , '45-57 Days in arrears',
    	(IF([DaysInArrears] > 29 and [DaysInArrears] <= 44 , '30-44 Days in arrears',
        	(IF([DaysInArrears] > 14 and [DaysInArrears] <= 29 , '15-29 Days in arrears',
            	(IF([DaysInArrears] > 0 and [DaysInArrears] <= 14 , 'Less than 15 Days in arrears','No Arrears'))))))))) 	as [Arrears Category]
Resident [ArrearsReportPayroll];
Drop Table [ArrearsReportPayroll];
Rename Table Bucket3 to [ArrearsReportPayroll];
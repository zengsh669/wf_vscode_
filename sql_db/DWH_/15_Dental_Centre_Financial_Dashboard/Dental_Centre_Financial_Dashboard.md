# Dental Centre Financial Dashboard — QlikSense Load Script

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


Let vStartDate = Date(AddMonths(MonthStart(Today()), -36));

let vStartDate_1 = MakeDate(Year(AddYears(today(), -3)), 7, 1);

LIB CONNECT TO 'D4W (Live)';
MethodsofPayment_MAP:
MAPPING
LOAD 
	"method_of_paym_id",
    description;
SQL SELECT "method_of_paym_id",
    description
FROM dba."methods_of_paym";


MethodsofPaymentName_MAP:
MAPPING LOAD 
	"tot_paym_id",
    ApplyMap('MethodsofPayment_MAP', "method_of_paym_id")	 as PaymentMethodName;
SQL SELECT "method_of_paym_id",
    "tot_paym_id"
FROM dba.payments;

Discount_Category_MAP:
MAPPING
LOAD "cat_id",
    "cat_name";
SQL SELECT "cat_id",
    "cat_name"
FROM dba."discount_category";

Period_Map:
Mapping
Load * Inline [
Period, Month
01, Jul
02, Aug
03, Sep
04, Oct
05, Nov
06, Dec
07, Jan
08, Feb
09, Mar
10, Apr
11, May
12, Jun
];

LIB CONNECT TO 'D4W (Live)';
Age_MAP:
MAPPING
LOAD num(patient_id, 000000) as [Card No],
     "dob" as "Date of Birth";
SQL SELECT *
FROM dba.patients;

D4WDrID_MAP:
MAPPING
LOAD 
     member_id,
     firstname&' '&surname			as "Doctor Name"; 
SQL SELECT *
FROM dba.staff;

Appt_Book_To_DrNumber_MAP:
Mapping
Load * Inline [
app_book_number,	doct_id
4,					95						
5,					85
6,					94
9,					69
10,					74
11,					131
3,					91
2,					92
7,					93
8,					4
12,					144
];

LIB CONNECT TO 'D4W (Live)';
App_Duration_MAP:
Mapping Load distinct 
	"appoint_id",
	sum(duration)
group by 
	appoint_id, duration
    ;
SQL SELECT 
	"appoint_id",
    duration  
FROM dba."a_appointments";

LIB CONNECT TO 'rpsqlrp01 - paragonreporting';
ProviderGroupMapping:
Mapping
LOAD "provider_group_id",
    description;
SQL SELECT "provider_group_id",
    description
FROM paragonreporting.dbo."provider_group";


CoverType:
Mapping
LOAD "cover_type",
    description;
SQL SELECT  "cover_type",
    description
FROM paragonreporting.dbo."cover_type";

FinancialData:
LOAD
    "Account Num",
    ACCTID,
    "Create Date",
    "Create User",
    "Post Date",
    Period,
    "Journal ID",
    "Journal Detail",
    Amount,
    Quantity,
    "Journal Ref",
    "Fin Year",
    "Fin Period",
    Date(AddMonths(MakeDate([Fin Year]-1,7,1),[Fin Period]-1),'MMM-YYYY') as MonthYear,
    "Month",
    'Actual' as Source,
    "Budget Version",
    "Account Display",
    "Account Name",
    "Loc Code",
    Branch,
    Level3,
    Level2,
    Level1,
    Report
FROM [lib://TransformData (prdqs01_atobi)/Finance/DentalFinancialDetail.qvd]
(qvd)
Where [Fin Year] >= '2024'
and Source = 'Actual';

AllocatedExpensesCat:
Load *,
IF(wildmatch([Account Name], 'Rent Alloc Dent(WHld) -Lithgow',
'ExpAllocWages (WHld) -Dent HO',
'Phone Dent (WHld) -Lithgow',
'Wages Mgmt (WHld) -Dent HO'), 'Yes', 'No') as [Allocated Expense Y/N]
resident FinancialData;
drop table FinancialData;
rename table AllocatedExpensesCat to FinancialData;


Non_Mem_Fee:
LOAD * WHERE Date >= '1/7/2023' ;
LOAD*, 
Num(If(Month([MonthYear]) >= 7,
       Year([MonthYear])*100 + (Month([MonthYear])-6),
       (Year([MonthYear])-1)*100 + (Month([MonthYear])+6)), '000000') AS Period;
;
LOAD
    MonthYear,
    [Non Member Amount],
    [Bill Amount],
    [Non Member Amount]-[Bill Amount] 											as PotentialFee,
    'Non Member Fees'															as	NonMemberFeeFlag,
    'Non Member Fees'															as	Source,
    Year(MonthYear) 															as Year,
    if(Month(MonthYear) >= 7, Year(MonthYear)+1,Year(MonthYear)) 				as [Fin Year],
    //If(Month([MonthYear]) >= 7,Month([MonthYear])-6,Month([MonthYear])+6) 		AS [Period],  
    If(Month([MonthYear]) >= 7,Month([MonthYear])-6,Month([MonthYear])+6) 		AS [Fin Period], 
    date(MonthYear)																as Date
FROM [lib://TransformData (prdqs01_atobi)/Business KPIs Display/DentalNonMember_PotentialFee.qvd]
(qvd);


Concatenate (FinancialData)
Load * resident Non_Mem_Fee;
Drop table Non_Mem_Fee;

SwitchTmp:
Load *,
IF(Wildmatch([NonMemberFeeFlag], 'Non Member Fees'),'On', 'Off') as [Non Member Fees Switch]
resident FinancialData;
drop table FinancialData;
rename table SwitchTmp to FinancialData;

MAXPeriod:
NoConcatenate
Load
	Max(Period)				as MaxPeriod
Resident FinancialData;

Let vMaxPeriodTrans = Num(Peek('MaxPeriod',-1,'MAXPeriod'));

TMP:
CrossTable('PERIOD','BUDGET',7)
LOAD
    ACCTID,
    "Account Name",
    "Type",
    Level3,
    Level2,
    Level1,
    FSCSYR,
    "1"					as [01],
    "2"					as [02],
    "3"					as [03],
    "4"					as [04],
    "5"					as [05],
    "6"					as [06],
    "7"					as [07],
    "8"					as [08],
    "9"					as [09],
    "10",
    "11",
    "12"
FROM [lib://Manual Data (prdqs01_atobi)/Dental/Dental Budget FY_2026.xlsx]
(ooxml, embedded labels, table is Budget);

TMPBUD:
NoConcatenate
Load *,
Date(AddMonths(MakeDate([Fin Year]-1,7,1),[Fin Period]-1),'MMM-YYYY') as MonthYear;
Load
	ACCTID,
    [Account Name] 											as [Account Name_Budget],
    Num(FSCSYR&PERIOD)										as Period,
    BUDGET													as [Amount],
   	FSCSYR													as [Fin Year],
    Num(Right('00' & Num#(PERIOD),2)) 						as [Fin Period],
    Month(Date#(ApplyMap('Period_Map',Num#(PERIOD)),'MMM'))	as [Month],
    'Budget'												as [Source],
    Level3,
    Level2,
    Level1,
    Type
Resident TMP;
Drop table TMP;    

Left Join (TMPBUD)
Load Distinct
ACCTID, 
[Account Name]
Resident FinancialData;

Concatenate (FinancialData)
Load * resident TMPBUD;
Drop table TMPBUD;



LIB CONNECT TO 'D4W (Live)';
Payments_Invoices: 
LOAD * WHERE Payment_DateTest >= '1/7/2023' ;
LOAD
	invoice_id 																as [Invoice ID],
    [Payment ID],
    [Payment Type], 																			// this is a numeric value NOT linked to the payment method ?useful?
//	paid_by_patient,
//	paid_by_third,
//	[Fund Name],
    Payment_DateTest,
    MonthName(Payment_DateTest) 																		as [MonthYear],
    Date(Floor(Weekend(Payment_DateTest))) 																as [Weekend], 
        // Determine Financial Year
    If(Month(Payment_DateTest) >= 7,Year(Payment_DateTest) & '-' & Right(Year(Payment_DateTest)+1,2),
        Year(Payment_DateTest)-1 & '-' & Right(Year(Payment_DateTest),2)) 								AS [Fin Year_2],
     If(Month(Payment_DateTest) >= 7,Year(Payment_DateTest) + 1,Year(Payment_DateTest)) 				AS [Fin Year],       
 If(Month(Payment_DateTest) >= 7,Month(Payment_DateTest)-6,Month(Payment_DateTest)+6) 					AS [Fin Period],
	[Payment Amount]														as [Amount],
//    Date(Floor(date_created)) 												as [Account Create Date],
//    total																	as [Inv Total],
	ApplyMap('MethodsofPaymentName_MAP', [Payment ID], 'MISSING')			as [Payment Method],
//    num(responsible_party_id, 000000)										as [Payment Responsible Party ID],
//    ApplyMap('Discount_Category_MAP', discount_category_id)					as [Discount Reason],
    'D4W Payments'															as [Source]
    
//	 Date(Floor([Payment Date])) as [Payment Date],
//     ApplyMap('PatientName_MAP',num(patient_id, 000000)) 			as [Payment Patient Name]	// can't retrieve this as payments can be applied across multiple invoices & px
//     num(patient_id, 000000)										as [Payment Card No.],			
;
SQL
SELECT
a."id" invoice_id,
COALESCE(a.send_acc_to_pat_id,a.send_acc_to_third_party_id,0) responsible_party_id,
a.date_created,
tp.date_created_2 as Payment_DateTest,
tp.tot_paym_id as 'Payment ID',
tp.payment_type as 'Payment Type', 
pa.amount as 'Payment Amount',					// this gets the specific amount applied to an invoice
tp.paid_by_patient, 
tp.paid_by_third,
h.name 'Fund Name',
a.total,
tp.discount_category_id
// pay.amount as 'Payment Amount TOT',				// this gets the total payment which could be across multiple patients and/or invoices
//tp."date" as 'Payment Date',
// IF tp."payment_type" = 1 THEN r.cat_name ELSE m.description ENDIF as 'Payment Method',
// tr.patient_id, 

FROM "dba".patients_accounts as a 
Left Join "dba"."account_payment_plan" as app on app.patient_account_id = a.id
left join dba.payment_allocations as pa on pa.account_payment_plan_id = app.account_payment_plan_id
Left join dba.tot_payment as tp on tp.tot_paym_id = pa.tot_paym_id
left join "dba"."third_parties" as h on (h.third_party_id = tp.paid_by_third and h.thp_type = '1')
left join "dba"."discount_category" as r on r.cat_id = tp.discount_category_id
// Left join (Select distinct(t.patient_id) as 'patient_id', t.account_id
// 			from "dba"."treat" as t
//             group by t.account_id,
//             		t.patient_id) as tr on tr.account_id = a.id

Where tp.ref_status is null
and tp.tot_paym_id is not null
;


LET vStat = NoOfRows('Payments');
Stats:
LOAD * Inline [
Stat, 				Rows,				Comment
Payments Table, 	'$(vStat)',			6.2 Payments];

Left join (Payments_Invoices)
LOAD// 'Lithgow'																						as [Invoice Location],
//     If(Len(Trim(num(patient_id, 000000)))>0,num(patient_id, 000000))								as [Bill PatNumber],	// ?????? 1 invoice multiple patients ??
     invoice_id																						as [Invoice ID],
     patient_id, 
//     provider_id,																								
     [Bill DrNumber] 																				as [Bill DrNumber],
//	 Date(Floor(treat_date))																		as [Consult Date],
//     Date(Floor(date_created))																		as [Entry Date],
//     Money(amount)																					as [Bill Amount],
//     Money(gst_amount)																				as [Bill GST],
//     1																								as BillCount,
//     [ProviderNumber],
          firstname&' '&surname											as Dentist,
           [Bill DrNumber]&' - '& firstname&' '&surname							as [Dentist No. & Name];

SQL
SELECT
t.patient_id,
a."id" invoice_id,
t.provider_id,
t.treat_date,
s.pers_code as 'Bill DrNumber',
s.provider_no_1_id as [ProviderNumber],
s.surname,
s.firstname,
COALESCE(a.send_acc_to_pat_id,a.send_acc_to_third_party_id,0) responsible_party_id,
a.date_created,
p.item,
p.description,
t.fee * t.times amount,
COALESCE(CAST(ROUND((t.fee * t.times) * (g.gst_value/110 ),2) AS double),0) gst_amount,
t.times frequency,
t.rebate,
t.tooth tooth_no,
t.item_id

FROM "dba"."treat" t JOIN "dba".patients_accounts a ON (t.account_id = a."id")
JOIN "dba".procedures p ON (t.item_id = p.item_id)
LEFT OUTER JOIN "dba"."gst_tarifs" g ON (p.item_id = g.item_id)
JOIN "dba".staff s ON (t.provider_id = s.member_id)

Where p.show_in_accounts = '1'; 

TmpPayment:
NoConcatenate
Load Distinct
[Payment ID],
[Invoice ID],
[Fin Period] as [Period],
[Amount],
[Fin Year],
[Fin Period],
[Source],
[MonthYear],
[Weekend],
[Payment Method],
UPPER([Dentist]) as Dentist,
[Bill DrNumber]
Resident Payments_Invoices; 

Concatenate (FinancialData)
Load * resident TmpPayment;
Drop table TmpPayment;


TmpPay_Appt:
NoConcatenate
Load Distinct
[Payment ID]&'-'&[Invoice ID] as Pay_ApptKEY,
[patient_id],
[Amount],
[MonthYear]
Resident Payments_Invoices; 

Drop table Payments_Invoices; 


LIB CONNECT TO 'D4W (Live)';
Appointments:
LOAD * WHERE [Appt Date] >= '1/7/2023' AND [Appt Date] <= Today() ;
LOAD distinct *,
//	[Appt PatNumber] & '|' & [ApptBook DrNumber] & '|' & Date([Appt Date Formatted],'YYYYMMDD')			as D4WKey,
	[PatNumber + Appt Location] & '|' & [Appt Date]									as [Appt Key],
	Coalesce(Age([Appt Date],ApplyMap('Age_MAP',[Appt PatNumber])),'UNKNOWN')		as [Age at Appt TMP],
    ApplyMap('D4WDrID_MAP', [Appt Book doct_id TMP], [Appt Book doct_id TMP])			as [ApptBook Dentist Name],    
 If(Month([Appt Date]) >= 7,Year([Appt Date]) + 1,Year([Appt Date])) 		AS [Appt_Fin Year],       
 If(Month([Appt Date]) >= 7,Month([Appt Date])-6,Month([Appt Date])+6) 		AS [Appt_Period]    
    ;

LOAD  distinct
	"appoint_id"																		as [Raw ApptKey],
	"appt_id"																			as [Raw appt_id],
 ApplyMap('Appt_Book_To_DrNumber_MAP', app_book_id, 'OTHER')							as [Appt Book doct_id TMP],
    'Lithgow'   																		as [Appt Location],
    "pat_id"																			as [Appt PatNumber],
    num(pat_id, 000000) 																as [Card No],
    "pat_id" &'|'& 'Lithgow'															as [PatNumber + Appt Location],
    "app_date"																			as [Appt Date_RAW],
     Monthname("app_date")															    as [Appt MonthYear],
    date("app_date", 'YYYYMMDD')														as [Appt Date],      
    'Y'																					as [HasAppointment],
    "status"																			as [Appt Status],
        ApplyMap('App_Duration_MAP', appoint_id)											as [Appt Duration],
    if(wildmatch("status", '*A*'), 'Y', 'N')													as [Appt Attended Flag],
    if(wildmatch("status", '*F*'), 'Y', 'N')													as [Appt FTA Flag],
    if(wildmatch("status", '*U*'), 'Y', 'N')													as [Appt UTA Flag],
    if(wildmatch("status", '*W*'), 'Y', 'N')													as [Appt WaitingReschedule Flag], 
    'D4W Appointments'																							as [Source]
;
SQL SELECT 
	"appoint_id",
    "app_book_id",
    "app_date",
    "start",
    duration,
    descrip,
    notes,
    "pat_id",
    "doct_id",
    "status",
    "class_id",
    "date_of_creation",
    "appt_id",
    ref_status 
FROM dba."a_appointments"
where ref_status is NULL					// NOTE: This is always null but was on Centaur's data map - ensures that only non-deleted enteres are selected
and pat_id > 0
and pat_id <> 157373						// This is the 'Notes TIPS' patient created during the Oasis conversion
order by "app_date", appoint_id, "start" ;


Left Join (Appointments)
LOAD 
	num(patient_id, 000000) 											as [Card No];
//    "hf_plan_id"
//    "hf_member_code"													as [Member No.];
SQL SELECT *
FROM dba."patients_hf"
where patient_id <> 157373;						// This is the 'Notes TIPS' patient created during the Oasis conversion;

Left join (Appointments)
Load
    num(patient_id, 000000)												as [Card No],
    "Membership ID"														as [Mbr No],
     if("Membership ID">0, 'Y', 'N')									as Member_YorN
FROM [lib://ExtractData (prdqs01_atobi)/Dental/D4W/D4W_CustomField_MbrNo.qvd] (qvd);


AgeCohorts:
load * inline [
agemin, agemax, AgeCohort
-10, 17, 0-17
18, 29, 18-29
30, 44, 30-44
45, 59, 45-59
60, 74, 60-74
75, 199, 75+
];

left join IntervalMatch ([Age at Appt TMP]) 
LOAD agemin, agemax
Resident AgeCohorts;

left join (Appointments)
load [Age at Appt TMP],
	 AgeCohort
Resident AgeCohorts;
drop Table AgeCohorts;

Left Join (Appointments)
Load distinct 
Pay_ApptKEY,
[patient_id]		as [Appt PatNumber],
MonthYear			as [Appt MonthYear],
[Amount]			as [Payment Amount]
Resident TmpPay_Appt;

Drop Table TmpPay_Appt;

// Only includes appointed attended flag = 'Y'
Left Join (Appointments)
LOAD
    "Card No"		as [Appt PatNumber],
    min("Appt Date") as [First Appt Date]
FROM [lib://TransformData (prdqs01_atobi)/Business KPIs Display/DentalPatients_Display.qvd]
(qvd)
Group by "Card No";

DentalPatients2:
Load*,
if([Appt Date]=[First Appt Date],'New Patient','Not New') as [New Patient Flag - Dental]
Resident Appointments;
Drop Table Appointments;
Rename Table DentalPatients2 to Appointments;

TmpAppointment:
NoConcatenate
Load Distinct
Pay_ApptKEY,
 [Raw ApptKey],
//[Invoice ID],
[Appt_Period] as [Period],
[Payment Amount] as [Amount],
[Appt_Fin Year] as [Fin Year],
[Appt_Period] as [Fin Period],
[Source],
[Appt MonthYear] as [MonthYear],
//[Payment Method],
UPPER([ApptBook Dentist Name]) as [Dentist],
//[Bill DrNumber],
[Appt PatNumber],
[First Appt Date],
[Appt Date] as [Date],
Date(Floor(Weekend([Appt Date]))) as [Weekend],
[Appt Duration],
[New Patient Flag - Dental],
[Age at Appt TMP],
AgeCohort,
[Appt Attended Flag],
[Appt FTA Flag],
[Appt UTA Flag],
[Appt WaitingReschedule Flag],
Member_YorN
Resident Appointments; 

Concatenate (FinancialData)
Load * resident TmpAppointment;
Drop table TmpAppointment;


TmpAppointment_1:
NoConcatenate
Load Distinct
 [Raw ApptKey],
[Appt_Period] as [Period],
[Appt_Fin Year] as [Fin Year],
[Appt_Period] as [Fin Period],
'Chair Utilisation' as [Source],
[Appt MonthYear] as [MonthYear],
Upper([ApptBook Dentist Name]) as [Dentist],
[Appt PatNumber],
[Appt Date] as [Date],
 Date(Floor(Weekend([Appt Date]))) as [Weekend],
[Appt Duration],
[Appt Attended Flag],
[Appt FTA Flag],
[Appt UTA Flag],
[Appt WaitingReschedule Flag]
Resident Appointments; 
//Drop Table Appointments;

Concatenate (FinancialData)
Load * resident TmpAppointment_1;


DentistHours:
Load
    Date,
    Dentist,
    Sum([Appt Duration]) as [Appt Duration]
Resident TmpAppointment_1
Where [Appt Attended Flag] = 'Y'
Group By Date, Dentist;


TmpSorted:
NoConcatenate
Load
    Date,
    Dentist,
    [Appt Duration]
Resident DentistHours
Order By Date, Dentist;


DentistRank:
NoConcatenate
Load
    Date,
    Dentist,
    [Appt Duration],
    If(Date = Peek('Date'),
        Peek('ChairID') + 1,
        1
    ) as ChairID
Resident TmpSorted;


Dates:
Load Distinct Date
Resident TmpAppointment_1;


Chairs:
Load 
    Date,
    IterNo() as ChairID
Resident Dates
While IterNo() <= 5;


Left Join (Chairs)
Load
    Date,
    ChairID,
    Dentist,
    [Appt Duration]
Resident DentistRank;

Concatenate (FinancialData)
LOAD*, 
Num(If(Month([MonthYear]) >= 7,
       Year([MonthYear])*100 + (Month([MonthYear])-6),
       (Year([MonthYear])-1)*100 + (Month([MonthYear])+6)), '000000') AS Period;
Load 
    Date,
    'Chair UtilisationTest' as [Source],
    ChairID,
    UPPER(Dentist) as Dentist,
    [Appt Duration],
 If(Month([Date]) >= 7,Year([Date]) + 1,Year([Date])) 		AS [Fin Year],       
 If(Month([Date]) >= 7,Month([Date])-6,Month([Date])+6) 		AS [Fin Period],
 Monthname(Date) as [MonthYear],
 Date(Floor(Weekend(Date))) as [Weekend]
Resident Chairs;

Drop Tables 
    TmpAppointment_1,
    DentistHours,
    TmpSorted,
    DentistRank,
    Chairs,
    Dates;

    TMP_Appt_Bud:
CrossTable('PERIOD','BUDGET',2)
LOAD
    FSCSYR,
    Dentist,
    "1"					as [01],
    "2"					as [02],
    "3"					as [03],
    "4"					as [04],
    "5"					as [05],
    "6"					as [06],
    "7"					as [07],
    "8"					as [08],
    "9"					as [09],
    "10",
    "11",
    "12"
FROM [lib://Manual Data (prdqs01_atobi)/Dental/DentalBudget_Appointments.xlsx]
(ooxml, embedded labels, table is Budget);

TMPBUD_Appt:
NoConcatenate
Load *,
Date(AddMonths(MakeDate([Fin Year]-1,7,1),[Fin Period]-1),'MMM-YYYY') as MonthYear;
Load
    Num(FSCSYR&PERIOD)										as Period,
    Dentist,
    BUDGET													as [Amount],
   	FSCSYR													as [Fin Year],
    Num(Right('00' & Num#(PERIOD),2)) 						as [Fin Period],
    Month(Date#(ApplyMap('Period_Map',Num#(PERIOD)),'MMM'))	as [Month],
    'Appointment Budget'												as [Source]
Resident TMP_Appt_Bud;
Drop table TMP_Appt_Bud;    


Concatenate (FinancialData)
Load * resident TMPBUD_Appt;
Drop table TMPBUD_Appt;

LIB CONNECT TO 'D4W (Live)';
TreatmentsTmp:
LOAD*
Where wildmatch([Treatment Description3], '*Compliment*', '*Complaint*')
;
LOAD num(patient_id, 000000) & '|' & provider_id & '|' & Date(date_created,'YYYYMMDD')		as D4WKey,
     num(patient_id, 000000)																as [Treatment PatNumber],
     treat_id																				as PlanNumber,
     item_id																				as [Treatment ItemCode],
     if(isnull(treat_date), 'N', 'Y')														as [Treatment Completed],
     date(floor(treat_date))																as [Treatment Date Created],
      Monthname(treat_date)																	as [MonthYear],
      Month(treat_date)																		as [Month],
     provider_id																			as [Treatment Provider ID],
     provider_no																			as [Treatment Provider No.],
     "Bill DrNumber"																		as [Treatment DrNumber],
     item																					as [Treatment Description2],
     description																			as [Treatment Description3],
     'Dental NPS'																					as Source;

SQL
SELECT
t.patient_id,
a."id" invoice_id,
t.provider_id,
s.pers_code as 'Bill DrNumber',
s.provider_no_1_id provider_no,
COALESCE(a.send_acc_to_pat_id,a.send_acc_to_third_party_id,0) responsible_party_id,
a.date_created,
p.item,
p.description,
t.fee * t.times amount,
COALESCE(CAST(ROUND((t.fee * t.times) * (g.gst_value/110 ),2) AS double),0) gst_amount,
t.times frequency,
t.rebate,
t.tooth as 'tooth_no',
t.treat_date, 
t.treat_id, 
t.chart_id, 
t.visit_id,
t.user_id,
t.item_id, 
t.ref_number

FROM "dba"."treat" t left JOIN "dba".patients_accounts a ON (t.account_id = a."id")
left JOIN "dba".procedures p ON (t.item_id = p.item_id)
LEFT OUTER JOIN "dba"."gst_tarifs" g ON (p.item_id = g.item_id)
left JOIN "dba".staff s ON (t.provider_id = s.member_id)
--Where p.non_treat <> '0'
;


LIB CONNECT TO 'D4W (Live)';
Left Join (TreatmentsTmp)
LOAD "treat_id" as [PlanNumber],
    notes,
    "ref_number",
    "ref_status",
    "is_plan";
SQL SELECT "treat_id",
    notes,
    "ref_number",
    "ref_status",
    "is_plan"
FROM dba."Treat_notes";

Left Join (TreatmentsTmp)
LOAD 
	num(patient_id, 000000) 											as [Treatment PatNumber],
    "hf_member_code"													as [Member No.]
    ;
SQL SELECT *
FROM dba."patients_hf"
where patient_id <> 157373;						// This is the 'Notes TIPS' patient created during the Oasis conversion;

NPSCategory:
Load*, 
   IF(WildMatch([Treatment Description3], '*Compliment*'),'Promoter',
   IF(WildMatch([Treatment Description3], '*Complaint*'), 'Detractor', 'Passive')) as [NPS_Level]
Resident TreatmentsTmp;
Drop Table TreatmentsTmp;
Rename Table NPSCategory to TreatmentsTmp;

Treatments:
Load*, 
    Year(MonthYear) 												as Year,
    if(Month(MonthYear) >= 7, Year(MonthYear)+1,Year(MonthYear)) 	as [Fin Year],
     If(Month([Date]) >= 7,Month([Date])-6,Month([Date])+6) 		AS [Period]  
    ;
Load
Source,
[Treatment Date Created] as [Date],
[MonthYear],
[Month],
[Member No.]			as [Membership Number],
notes 					as [Comment],
[NPS_Level]
Resident TreatmentsTmp;
Drop Table TreatmentsTmp;

Concatenate (Treatments)
Load*, 
    Year(MonthYear) 												as Year,
    if(Month(MonthYear) >= 7, Year(MonthYear)+1,Year(MonthYear)) 	as [Fin Year],
         If(Month([Date]) >= 7,Month([Date])-6,Month([Date])+6) 		AS [Period]  ;
LOAD
   'Dental NPS' 			as Source,
   ResponseId,
//    Interaction,
    StartDate			as [Date],
    MonthYear,
    month(StartDate) 			as [Month],
    MembershipNumber	as [Membership Number],
    Feedback 			as Comment,
//    CustomerSatisfactionLevel,
    NetPromoterLevel	as [NPS_Level]
FROM [lib://TransformData (prdqs01_atobi)/NPS_HCS_Data/Qualtrics_NPS_HCS_Data.qvd]
(qvd)
Where Interaction = 'Dental';

TmpNPS:
LOAD * WHERE [Date] >= '1/7/2023' AND [Date] <= Today() ;
NoConcatenate
Load 
[Period],
[Fin Year],
[Period] as [Fin Period],
[Source],
[MonthYear],
[NPS_Level],
[Membership Number],
[Date]
Resident Treatments; 
Drop table Treatments;

Concatenate (FinancialData)
Load * resident TmpNPS;
Drop table TmpNPS;


LIB CONNECT TO 'rpsqlrp01 - paragonreporting';
// Only include members on extras product within 50km radius of lithgow dental facility 
GroupKey:
LOAD*,
Num(If(Month([MonthYear]) >= 7,
       Year([MonthYear])*100 + (Month([MonthYear])-6),
       (Year([MonthYear])-1)*100 + (Month([MonthYear])+6)), '000000') AS Period;
Load*, 
    'Member Utilisation' as [Source],
Year(date(floor(rundate-1)))                                   as Year,   
    Month(Date) 											as [EndOfCalYearMonth],
 If(Month([Date]) >= 7,Year([Date]) + 1,Year([Date])) 		AS [Fin Year],       
 If(Month([Date]) >= 7,Month([Date])-6,Month([Date])+6) 		AS [Fin Period]
;
LOAD "row_id",
    "membership_id"																		as [Mbr No],
    cover,
    date(floor(rundate-1))																as Date,
    date(floor(rundate))																as rundateTmp,
    Month(date((rundate-1)))															as [EOM Month],
    monthname(date((rundate-1)))														as MonthYear,
    Year(date(rundate-1))																as [EOM Year],
    rundate,
    "hosp_product_id",
    "extras_product_id",
    ApplyMap('CoverType',"cover_type", 'MISSING')										as [Cover Type],
    "memship_status",
    "count_active",
    postcode;
SQL SELECT *
FROM paragonreporting.dbo."group_key_full_by_branch"
where 
extras_product_id is not null
and month(rundate) = '1'
and rundate > '$(vStartDate_1)';

// for the year to date Metric
Concatenate (GroupKey)
LOAD*,
Num(If(Month([MonthYear]) >= 7,
       Year([MonthYear])*100 + (Month([MonthYear])-6),
       (Year([MonthYear])-1)*100 + (Month([MonthYear])+6)), '000000') AS Period;
Load*, 
    'Member Utilisation' as [Source],
Year(date(floor(rundate-1)))                                   as Year,   
    Month(Date) 											as [EndOfCalYearMonth],
 If(Month([Date]) >= 7,Year([Date]) + 1,Year([Date])) 		AS [Fin Year],       
 If(Month([Date]) >= 7,Month([Date])-6,Month([Date])+6) 		AS [Fin Period]
;
LOAD "row_id",
    "membership_id"																		as [Mbr No],
    cover,
    date(floor(rundate-1))																as Date,
    date(floor(rundate))																as rundateTmp,
    Month(date((rundate-1)))															as [EOM Month],
    monthname(date((rundate-1)))														as MonthYear,
    Year(date(rundate-1))																as [EOM Year],
    rundate,
    "hosp_product_id",
    "extras_product_id",
    ApplyMap('CoverType',"cover_type", 'MISSING')										as [Cover Type],
    "memship_status",
    "count_active",
    postcode;
SQL SELECT *
FROM paragonreporting.dbo.group_key_full_by_branch
WHERE extras_product_id IS NOT NULL
AND rundate = (
    SELECT MAX(rundate)
    FROM paragonreporting.dbo.group_key_full_by_branch);

Inner Join (GroupKey)
LOAD "person_id"																		as [Person ID],
    "membership_id"																		as [Mbr No],
    relationship,
    status_flag																			as person_status,
    "join_date"																			as person_join_date,
    "termination_date"																	as person_termination_date;
SQL SELECT *
FROM paragonreporting.dbo."person_membership";

GroupKey3:
LOAD * WHERE [Active as at Time] = 'Active' ;
LOAD *,
if(person_join_date > rundate,'Not Active Yet',
if(person_join_date <= rundate and isnull(person_termination_date),'Active',
if(person_termination_date > rundate, 'Active',
if(person_termination_date <= rundate,'Terminated'))))									as [Active as at Time]
Resident GroupKey;
Drop Table GroupKey;
Rename Table GroupKey3 to GroupKey;

// Members with Postcodes within a 50km radius of Lithgow Dental Facility based on https://www.freemaptools.com/find-australian-postcodes-inside-radius.htm
Inner Join (GroupKey)
LOAD
    Postcode as postcode,
    "Care Centre",
    Radius
FROM [lib://Manual Data (prdqs01_atobi)/Membership App 2/Care Centre Radius Mapping.xlsx]
(ooxml, embedded labels, table is CareCentresPostcodeRadius)
Where Wildmatch([Care Centre], 'Lithgow Care Centre')
and Wildmatch([Radius], 'Within 50Km');


// Left join (GroupKey)
// Load
//     num(patient_id, 000000)												as [Card No],
//     "Membership ID"														as [Mbr No],
//      if("Membership ID">0, 'Y', 'N')									as Member_YorN
// FROM [lib://ExtractData (prdqs01_atobi)/Dental/D4W/D4W_CustomField_MbrNo.qvd] (qvd);

Claimed_Within_Year:
LOAD*,
[Person ID]&'-'&service_date 																				as VisitKey;
LOAD
    claim_id																								as [Claim ID],
    claim_line_id																							as [Claim Line ID],
    trim(provider_number_id)																				as [Provider Number ID],
    person_id										as [Person ID],
    "membership_id" 								as [Mbr No],
    service_date,
    Year(date(floor(service_date)))                    as Year
//    status_date
    ;
SQL SELECT *
FROM paragonreporting.dbo."claim_line"
WHERE claim_line_status_type = 'P' and service_date > '$(vStartDate_1)';

Inner Join (Claimed_Within_Year)
LOAD trim("provider_number_id")																					as [Provider Number ID],
//    trim("provider_id")																							as [Provider ID],
    ApplyMap('ProviderGroupMapping',"provider_group_id",'No Group')												as [Provider Group]
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_ProviderNumber.qvd] (qvd)
Where provider_group_id = 1; // WF Dental

// Based on Service Date
Left Join (GroupKey) 
Load
[Mbr No],
[Person ID],
[Year],
Count(Distinct([VisitKey])) as VisitsByYear
Resident Claimed_Within_Year
Group by [Mbr No],
[Person ID],
[Year];
Drop Table Claimed_Within_Year;

Concatenate (FinancialData)
Load * resident GroupKey;
Drop table GroupKey;

//Clinical Admin Hours Patient Card 158315
//Meetings Hours Patient Card 159324

DentistUtilisation_1:
NoConcatenate
LOAD * WHERE [Weekend] >= '1/7/2023' AND [Weekend] <= Today() ;
Load*,
Num(If(Month([MonthYear]) >= 7,
       Year([MonthYear])*100 + (Month([MonthYear])-6),
       (Year([MonthYear])-1)*100 + (Month([MonthYear])+6)), '000000') AS Period;
Load*,
 If(Month([Weekend]) >= 7,Year([Weekend]) + 1,Year([Weekend])) 		AS [Fin Year],       
 If(Month([Weekend]) >= 7,Month([Weekend])-6,Month([Weekend])+6) 		AS [Fin Period],
 Monthname([Weekend]) as [MonthYear];
Load Distinct
 [Raw ApptKey],
'Dentist Utilisation' as [Source],
UPPER([ApptBook Dentist Name]) as [Dentist],
[Appt PatNumber],
[Appt Date] as [Date],
date(Floor(Weekend([Appt Date]))) as [Weekend],
[Appt Duration] / 60 as [Hrs],
'AdminMeetingAppts'  as SourceCalc
Resident Appointments
Where Wildmatch([Appt PatNumber], '158315', '159324');

Concatenate (FinancialData)
Load * resident DentistUtilisation_1;
Drop Table DentistUtilisation_1;

DentistUtilisation:
LOAD Distinct
    Payroll_KEY,
    "Cost Centre",
    Hrs,
    "Transaction Type",
    "Leave Reason",
    SourceCalc,
    "Default Cost Account Description",
    Date(Floor(Weekend("Payroll Run Date"))) as [Weekend],
    "Payroll Run Date" ,
 If(Month([Payroll Run Date]) >= 7,Year([Payroll Run Date]) + 1,Year([Payroll Run Date])) 		AS [Fin Year],       
 If(Month([Payroll Run Date]) >= 7,Month([Payroll Run Date])-6,Month([Payroll Run Date])+6) 		AS [Fin Period],
 Monthname([Payroll Run Date]) as [MonthYear],    
    "Employee Code",
    Upper("Full Name")			as Dentist,
    'Dentist Utilisation' as [Source]
FROM [lib://TransformData (prdqs01_atobi)/Finance/DentistLeaveHours.qvd]
(qvd);

  
Concatenate (FinancialData)
LOAD * WHERE [Weekend] >= '1/7/2023' AND [Weekend] <= Today();
LOAD*, 
Num(If(Month([MonthYear]) >= 7,
       Year([MonthYear])*100 + (Month([MonthYear])-6),
       (Year([MonthYear])-1)*100 + (Month([MonthYear])+6)), '000000') AS Period;
Load * resident DentistUtilisation;
Drop table DentistUtilisation;
       

TMP_Utilisation_Bud:
CrossTable('PERIOD','BUDGET',1)
LOAD
    FSCSYR,
    "1"					as [01],
    "2"					as [02],
    "3"					as [03],
    "4"					as [04],
    "5"					as [05],
    "6"					as [06],
    "7"					as [07],
    "8"					as [08],
    "9"					as [09],
    "10",
    "11",
    "12"
FROM [lib://Manual Data (prdqs01_atobi)/Dental/DentalBudget_DentistUtilisation.xlsx]
(ooxml, embedded labels, table is Budget);

TMPBUD_DenUti:
NoConcatenate
Load *,
Date(AddMonths(MakeDate([Fin Year]-1,7,1),[Fin Period]-1),'MMM-YYYY') as MonthYear;
Load
    Num(FSCSYR&PERIOD)										as Period,
    BUDGET													as [Amount],
   	FSCSYR													as [Fin Year],
    Num(Right('00' & Num#(PERIOD),2)) 						as [Fin Period],
    Month(Date#(ApplyMap('Period_Map',Num#(PERIOD)),'MMM'))	as [Month],
    'Dentist Utilisation Budget'												as [Source]
Resident TMP_Utilisation_Bud;
Drop table TMP_Utilisation_Bud;    


Concatenate (FinancialData)
Load * resident TMPBUD_DenUti;
Drop table TMPBUD_DenUti;

TMP_ClinRev_Bud:
CrossTable('PERIOD','BUDGET',1)
LOAD
    FSCSYR,
    "1"					as [01],
    "2"					as [02],
    "3"					as [03],
    "4"					as [04],
    "5"					as [05],
    "6"					as [06],
    "7"					as [07],
    "8"					as [08],
    "9"					as [09],
    "10",
    "11",
    "12"
FROM [lib://Manual Data (prdqs01_atobi)/Dental/DentalBudget_RevenuePerClinicianHour.xlsx]
(ooxml, embedded labels, table is Budget);

TMPBUD_ClinRev:
NoConcatenate
Load *,
Date(AddMonths(MakeDate([Fin Year]-1,7,1),[Fin Period]-1),'MMM-YYYY') as MonthYear;
Load
    Num(FSCSYR&PERIOD)										as Period,
    BUDGET													as [Amount],
   	FSCSYR													as [Fin Year],
    Num(Right('00' & Num#(PERIOD),2)) 						as [Fin Period],
    Month(Date#(ApplyMap('Period_Map',Num#(PERIOD)),'MMM'))	as [Month],
    'Dentist Revenue Budget'												as [Source]
Resident TMP_ClinRev_Bud;
Drop table TMP_ClinRev_Bud;    


Concatenate (FinancialData)
Load * resident TMPBUD_ClinRev;
Drop table TMPBUD_ClinRev;

TmpAppointment_Ret:
NoConcatenate
Load Distinct
 [Raw ApptKey],
[Appt_Period] as [Period],
[Appt_Fin Year] as [Fin Year],
[Appt_Period] as [Fin Period],
'Patient Retention' as [Source],
[Appt MonthYear] as [MonthYear],
Upper([ApptBook Dentist Name]) as [Dentist],
[Appt PatNumber],
Date(Floor([Appt Date])) as [Date],
 Date(Floor(Weekend([Appt Date]))) as [Weekend],
[Appt Duration],
[Appt Attended Flag],
[Appt FTA Flag],
[Appt UTA Flag],
[Appt WaitingReschedule Flag]
Resident Appointments; 
Drop Table Appointments;

// Concatenate (FinancialData)
// Load * resident TmpAppointment_1;


AttendedApptBase:
Load
    Date as ApptDate,
    [Appt PatNumber],
    Sum([Appt Duration]) as [Appt Duration]
Resident TmpAppointment_Ret
Where [Appt Attended Flag] = 'Y'
Group By Date, [Appt PatNumber];

Appointments_Sorted:
LOAD
    [Appt PatNumber],
    Date(Floor([ApptDate])) as ApptDate
Resident AttendedApptBase
Order By [Appt PatNumber], ApptDate DESC;

Appointments_Final:
LOAD
    [Appt PatNumber],
    ApptDate,
 If([Appt PatNumber] = Peek([Appt PatNumber]),
        Peek([ApptDate])) 											as NextApptDate,
    If([Appt PatNumber] = Peek([Appt PatNumber])
        AND Peek(ApptDate) > ApptDate,Peek(ApptDate) - ApptDate) 	as DaysTillNextAppt        

Resident Appointments_Sorted
Order By [Appt PatNumber], ApptDate DESC;

Concatenate (FinancialData)
LOAD*, 
Num(If(Month([MonthYear]) >= 7,
       Year([MonthYear])*100 + (Month([MonthYear])-6),
       (Year([MonthYear])-1)*100 + (Month([MonthYear])+6)), '000000') AS Period;
LOAD*, 'Patient Retention' as [Source], 
If(DaysTillNextAppt > 0 AND DaysTillNextAppt <= 365,1,0) as ReturnedWithin12Months,
 If(Month([ApptDate]) >= 7,Year([ApptDate]) + 1,Year([ApptDate])) 		AS [Fin Year],       
 If(Month([ApptDate]) >= 7,Month([ApptDate])-6,Month([ApptDate])+6) 		AS [Fin Period],
 Monthname(ApptDate) as [MonthYear],
 Date(Floor(Weekend(ApptDate))) as [Weekend]    
Resident Appointments_Final;

Drop Tables 
	TmpAppointment_Ret,
    AttendedApptBase,
    Appointments_Final,
    Appointments_Sorted;
    
    
// Appointments_Next:
// LOAD
//     [Appt PatNumber],
//     ApptDate as NextApptDate
// Resident AttendedApptBase;

// LEFT JOIN (AttendedApptBase)
// LOAD
//     [Appt PatNumber],
//     NextApptDate
// Resident Appointments_Next;

// Appointments_NextClean:
// LOAD
//     [Appt PatNumber],
//     ApptDate,
//     Min(NextApptDate) as NextApptDate
// Resident AttendedApptBase
// Where NextApptDate > ApptDate
// Group By [Appt PatNumber], ApptDate;

// LEFT JOIN (AttendedApptBase)
// LOAD
//     [Appt PatNumber],
//     ApptDate,
//     NextApptDate
// Resident Appointments_NextClean;

// Concatenate (FinancialData)
// LOAD*, 'Patient Retention' as [Source]
// Resident AttendedApptBase;

// Drop Tables 
// 	TmpAppointment_Ret,
//     AttendedApptBase,
//     Appointments_Next,
//     Appointments_NextClean;

Exit Script;
AdditionDeductions_Map:
Mapping
LOAD idAddDeduct,
    cDescription;
SQL SELECT *
FROM Payroll.dbo."_iptblAdditionsDeductions";

CostCentre_Map:
Mapping
LOAD idCostAccount,
    cDescription;
SQL SELECT *
FROM Payroll.dbo."_iptblCostAccounts";

GL_MAP1:
Mapping
LOAD 
	cCostAccount,
    iLedgerAccID;
SQL SELECT *
FROM Payroll.dbo."_iptblGLBatchDetailsLedgerLink";

GL_MAP1_ARCHIVE:
Mapping
LOAD 
	cCostAccount,
    iLedgerAccID;
SQL SELECT *
FROM "Payroll_Archive".dbo."_iptblGLBatchDetailsLedgerLink";

GL_MAP2:
Mapping
LOAD "Account ID",
    Account;
SQL SELECT *
FROM Payroll.dbo."_eivGLAccounts";

GL_MAP2_ARCHIVE:
Mapping
LOAD "Account ID",
    Account;
SQL SELECT *
FROM "Payroll_Archive".dbo."_eivGLAccounts";

SuperFund_Map:
Mapping
LOAD idSuperFund,
    cFundName;
SQL SELECT *
FROM Payroll.dbo."_iptblSuperFund";

Termination_Map:
Mapping
LOAD idTerminationReason,
    cTerminationReason;
SQL SELECT *
FROM Payroll.dbo."_iptblTerminationReason";

LeaveReason_Map:
Mapping
LOAD 
	idLeaveReason,
    Capitalize(cDescription)				as Description;
SQL SELECT *
FROM Payroll.dbo."_ipvLeaveReasons";



Period_Map:
Mapping
LOAD Counter,
	Date(Left("Period End",10))				as [Payroll Run Date];
SQL SELECT *
FROM Payroll.dbo."_eivPeriods";

Period_Map_ARCHIVE:
Mapping
LOAD Counter,
	Date(Left("Period End",10))				as [Payroll Run Date];
SQL SELECT *
FROM "Payroll_Archive".dbo."_eivPeriods";

/////Mapping fromAccPac
Segment1_Map:
Mapping
LOAD
    SEGVAL,
    SEGVALDESC
FROM [lib://ExtractData (prdqs01_atobi)/AccPac_GL_Segments.qvd]
(qvd) where IDSEG = '000001';

Segment2_Map:
Mapping
LOAD
    SEGVAL,
    SEGVALDESC
FROM [lib://ExtractData (prdqs01_atobi)/AccPac_GL_Segments.qvd]
(qvd) where IDSEG = '000002';

Segment3_Map:
Mapping
LOAD
    SEGVAL,
    SEGVALDESC
FROM [lib://ExtractData (prdqs01_atobi)/AccPac_GL_Segments.qvd]
(qvd) where IDSEG = '000003';

Segment4_Map:
Mapping
LOAD
    SEGVAL,
    SEGVALDESC
FROM [lib://ExtractData (prdqs01_atobi)/AccPac_GL_Segments.qvd]
(qvd) where IDSEG = '000004';

Segment5_Map:
Mapping
LOAD
    SEGVAL,
    SEGVALDESC
FROM [lib://ExtractData (prdqs01_atobi)/AccPac_GL_Segments.qvd]
(qvd) where IDSEG = '000005';

Segment6_Map:
Mapping
LOAD
    SEGVAL,
    SEGVALDESC
FROM [lib://ExtractData (prdqs01_atobi)/AccPac_GL_Segments.qvd]
(qvd) where IDSEG = '000006';

Segment7_Map:
Mapping
LOAD
    SEGVAL,
    SEGVALDESC
FROM [lib://ExtractData (prdqs01_atobi)/AccPac_GL_Segments.qvd]
(qvd) where IDSEG = '000007';

Segment8_Map:
Mapping
LOAD
    SEGVAL,
    SEGVALDESC
FROM [lib://ExtractData (prdqs01_atobi)/AccPac_GL_Segments.qvd]
(qvd) where IDSEG = '000008';

Segment9_Map:
Mapping
LOAD
    SEGVAL,
    SEGVALDESC
FROM [lib://ExtractData (prdqs01_atobi)/AccPac_GL_Segments.qvd]
(qvd) where IDSEG = '000009';

Segment10_Map:
Mapping
LOAD
    SEGVAL,
    SEGVALDESC
FROM [lib://ExtractData (prdqs01_atobi)/AccPac_GL_Segments.qvd]
(qvd) where IDSEG = '000010';

AccountGrp_Map:
Mapping
LOAD
    ACCTGRPCOD,
    ACCTGRPDES						
FROM [lib://ExtractData (prdqs01_atobi)/AccPac_GLACCGRP.qvd]
(qvd);

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
SecurityMap:
Mapping
LOAD
    security_level,
    description
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_security_level.qvd]
(qvd);
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

//THis is for support staff
SupportAward:
Mapping
LOAD
    Award&Level					as [Award + level],
//    "Pay Point"				as [Award Pay point level],
    "Minimum hourly rate"		as [Min Award hourly rate]
FROM [lib://Manual Data (prdqs01_atobi)/Award Levels min rates.xlsx]
(ooxml, embedded labels, table is Sheet5);


//This is for health professionals
HealthProfessionalAward:
Mapping
LOAD
    Award&Level					as [Award + level],
    "Pay Point"					as [Award Pay point level]
//     "Minimum hourly rate"		as [Min Award hourly rate]
FROM [lib://Manual Data (prdqs01_atobi)/Award Levels min rates.xlsx]
(ooxml, embedded labels, table is Sheet5);


"Employee Details":
LOAD "Employee ID"															as [Employee ID],
	 "Employee Code"														as [Employee Code],
    Surname,
    "First Name",
    "Middle Name",
    "Preferred Name",
    "Given Names",
    "Other Names",
    "Full Name",
    "Surname with Initials",
    Initials,
    Title,
    Gender,
    "Marital Status",
    "Date Of Birth",
    "Age",
    Date(Left("Hired Date",10))												as [Hired Date],
    if(Month( Date(Left("Hired Date",10))) >= 7, 
    Year( Date(Left("Hired Date",10)))+1,
    Year( Date(Left("Hired Date",10))))										as [Hired FinYear],
    Date(Monthstart("Hired Date"), 'MMM-YYYY')								as [Hired MonthYear],
    "Years of Service",
    if("Years of Service" < 1, '<1',
    if("Years of Service" >=1 and "Years of Service" <= 5, '1 to 5 years',
    if("Years of Service" > 5 and "Years of Service" <= 9, '6 to 10 years',
    if("Years of Service" >= 10,'10+ years'))))  							as [LOS Grp],
    //if("Years of Service" > 5 and "Years of Service" <= 10, '6 to 10 years','10+ years')))  as [LOS Grp],
    "Aboriginal/Torres Strait",
    "Physical Street",
    "Physical Suburb",
    "Physical State",
    "Physical State Code",
    "Physical Postal Code",
    "Physical Country",
    "Physical Street"&' '&  "Physical Suburb"&' '&"Physical State"&' '&"Physical Postal Code" 	as [Full Physical Address],
    "Postal Street",
    "Postal Suburb",
    "Postal State",
    "Postal State Code",
    "Postal Postal Code",
    "Postal Country",
    "Postal Street"&' '&  "Postal Suburb"&' '&"Postal State"&' '&"Postal Postal Code" 			as [Full Postal Address],
    "Phone Number",
    "Mobile Number",
    "Email Address",
    "Email Type",
    "Payroll Company ID",
    "Payroll Company Code",
    "Payroll Company Description",
    "Payroll Company",
    "Pay Frequency ID",
    "Pay Frequency",
    "Location ID",
     Location,
    "Pay Point",
    "Employment Type",
    ApplyMap('GL_MAP2',ApplyMap('GL_MAP1',"Default Cost Account Code"))			as [ACCTID],
    "Default Cost Account Code",
    "Default Cost Account Description"		as "Default Cost Account DescriptionTMP",
    if(wildMatch(Upper("Default Cost Account Description"),'DIRECTOR*'),1,0)			as [DirectorFlag],
    "Default Cost Account",
    "Normal Hours Paid",
    "Employee Terminated",
    Date(Left("Termination Date",10))											as [Termination Date],
    if(Month( Date(Left("Termination Date",10))) >= 7, 
    Year( Date(Left("Termination Date",10)))+1,
    Year( Date(Left("Termination Date",10))))									as [Termination FinYear],
    Date(Monthstart("Termination Date"), 'MMM-YYYY')							as [Termination MonthYear],
    "Termination Reason",
     "Base Wage",
    "Yearly Salary",
    "Autopay Amount",
    "Normal Hourly Rate",
    "Time and a Half Hourly Rate",
    "Double Time Rate",
    "Other Hourly Rate",
    "Award Hourly Rate",
    "Job Classification",
	Date(Monthstart("Termination Date"), 'MMM-YYYY')&[Employee ID]					as [Termination Key];
SQL SELECT *
FROM Payroll.dbo."_ipvRBMEmpDetails";

////Archive records
LOAD "Employee ID"									as [Employee ID],
    PurgeChar("Employee Code",'H')					as [Employee Code],
    Surname,
    "First Name",
    "Middle Name",
    "Preferred Name",
    "Given Names",
    "Other Names",
    "Full Name",
    "Surname with Initials",
    Initials,
    Title,
    Gender,
    "Marital Status",
    "Date Of Birth",
    "Age",
    Date(Left("Hired Date",10))						as [Hired Date],
    if(Month( Date(Left("Hired Date",10))) >= 7, 
    Year( Date(Left("Hired Date",10)))+1,
    Year( Date(Left("Hired Date",10))))									as [Hired FinYear],
    Date(Monthstart("Hired Date"), 'MMM-YYYY')							as [Hired MonthYear],
    "Years of Service",
    if("Years of Service" < 1, '<1',
    if("Years of Service" >=1 and "Years of Service" <= 5, '1 to 5 years',
    if("Years of Service" > 5 and "Years of Service" <= 10, '6 to 10 years','10+ years')))  as [LOS Grp],
    "Aboriginal/Torres Strait",
    "Physical Street",
    "Physical Suburb",
    "Physical State",
    "Physical State Code",
    "Physical Postal Code",
    "Physical Country",
    "Physical Street"&' '&  "Physical Suburb"&' '&"Physical State"&' '&"Physical Postal Code" 	as [Full Physical Address],
    "Postal Street",
    "Postal Suburb",
    "Postal State",
    "Postal State Code",
    "Postal Postal Code",
    "Postal Country",
    "Postal Street"&' '&  "Postal Suburb"&' '&"Postal State"&' '&"Postal Postal Code" 			as [Full Postal Address],
    "Phone Number",
    "Mobile Number",
    "Email Address",
    "Email Type",
    "Payroll Company ID",
    "Payroll Company Code",
    "Payroll Company Description",
    "Payroll Company",
    "Pay Frequency ID",
    "Pay Frequency",
    "Location ID",
     Location,
    "Pay Point",
    "Employment Type",
    ApplyMap('GL_MAP2_ARCHIVE',ApplyMap('GL_MAP1_ARCHIVE',"Default Cost Account Code"))			as [ACCTID],
    "Default Cost Account Code",
    "Default Cost Account Description"		as "Default Cost Account DescriptionTMP",
    if(wildMatch(Upper("Default Cost Account Description"),'DIRECTOR*'),1,0)			as [DirectorFlag],
    "Default Cost Account",
    "Normal Hours Paid",
    "Employee Terminated",
    Date(Left("Termination Date",10))											as [Termination Date],
    if(Month( Date(Left("Termination Date",10))) >= 7, 
    Year( Date(Left("Termination Date",10)))+1,
    Year( Date(Left("Termination Date",10))))									as [Termination FinYear],
    Date(Monthstart("Termination Date"), 'MMM-YYYY')							as [Termination MonthYear],
    "Termination Reason",
     "Base Wage",
    "Yearly Salary",
    "Autopay Amount",
    "Normal Hourly Rate",
    "Time and a Half Hourly Rate",
    "Double Time Rate",
    "Other Hourly Rate",
    "Award Hourly Rate",
    "Job Classification",
      /////////////This is for Staff Turnover report/////////////
    Date(Monthstart("Termination Date"), 'MMM-YYYY')&[Employee ID]					as [Termination Key]
Where Not Exists("Employee ID");
SQL Select *
FROM "Payroll_Archive".dbo."_ipvRBMEmpDetails";

////Data From Accpac
Left Join ("Employee Details")
LOAD
    ACCTID,
    ACCTFMTTD								as [Account Display],
    ACCTDESC								as [Account Name],
    ApplyMap('AccountGrp_Map',ACCTGRPCOD)	as [Account Group],
    ACSEGVAL01								as [Account Num],
    ApplyMap('Segment2_Map',ACSEGVAL02)		as [Company],
    ApplyMap('Segment3_Map',ACSEGVAL03)		as [DivisionTMP],
    ApplyMap('Segment4_Map',ACSEGVAL04)		as [State],
    ApplyMap('Segment5_Map',ACSEGVAL05)		as [BranchTMP],
    ApplyMap('Segment6_Map',ACSEGVAL06)		as [Product],
    ApplyMap('Segment7_Map',ACSEGVAL07)		as [Cover],
    ApplyMap('Segment9_Map',ACSEGVAL09)		as [Department]
FROM [lib://ExtractData (prdqs01_atobi)/AccPac_GL_Accounts.qvd]
(qvd);

///////////////This is for Award levels///////////////////

LIB CONNECT TO 'PRDSQL03 (prdqs01_atobi)';
Awards:
LOAD "idEmployee"				as [Employee ID],
	ucEEGenDesc1,
    if(wildmatch(ucEEGenDesc2,'Health Professional'),Applymap('HealthProfessionalAward',ucEEGenDesc1&replace(ucEEGenDesc2,'Health Professional Level ','')),
    ApplyMap('SupportAward',ucEEGenDesc1&replace(ucEEGenDesc2,'Support Level ',''))) 		as [Award Minimum Hourly Rate],
    
 ////////////////////////////To try bring in Min hourly rate for HPSS level 3////////////////////////////////////////////////////////////      
//     ApplyMap('SupportAward',ucEEGenDesc1&replace(ucEEGenDesc2,'Support Level ',''),'Nothing') as [WWWWWWW], 
//     ApplyMap('HealthProfessionalAward',ucEEGenDesc1&replace(ucEEGenDesc2,'Health Professional Level ',''),'Nothing') as [YYY], 
    ucEEGenDesc2,
    ucEEGenDesc3,
    ucEEGenDesc4,
    //////////These are for Reporting Executive (Free text out of MicrOpay)//////////
    ucEEGenDesc5,
    ucEEGenDesc6;
SQL SELECT *
FROM Payroll.dbo."_iptblEmployee";

//////////////// This is for FTE Board Report//////////
FTE:
Load *,
if(wildmatch("Default Cost Account DescriptionTMP", 'Employee Dentists', 'Lithgow Dental'), [FTE 38],[FTE 35])		as [FTE Calc];
Load*,
"Normal Hours Paid"/35				as [FTE 35],
"Normal Hours Paid"/38				as [FTE 38]
Resident "Employee Details";
Drop Table "Employee Details";
Rename Table FTE to "Employee Details";
LIB CONNECT TO 'PRDSQL03-MERIDIAN - Connx LIVE (westfund_russellm)';



/////////audit report///////////////
//FROM Payroll.dbo."_iptblEmployeeChange";

/*////////////////////////////////////////////////////////////////////////
//	Initial Version 
//		Created By:		Sharon Prior (AtoBi)
//		Details:	Payroll archive view
//
//
//
//		Change Log: Mon R added IncludeTrans_flag for movement monitoring
//
////////////////////////////////////////////////////////////////////////*/

TransactionsTMP:
LOAD idEmployeeTrans										as [Transaction ID],
    iEmployeeID												as [Employee ID],
    iPeriodID												as [Transaction Period],
	//iEmployeeID&'|'&iPeriodID&'|'&iLeaveReasonID			as Liability_KEY,
    iEmployeeID&'|'&iPeriodID								as Payroll_KEY,
    ApplyMap('Period_Map',iPeriodID)						as [Payroll Run Date],
    iSickLeaveID,
    iAnnualLeaveID,
    iLongServiceLeaveID,
    iLeaveReasonID											as [Leave Reason ID],
    if(Match(iLeaveReasonID,2,4,6,8,9,12,13,14,15,19),1,0)	as [Unplanned Leave Flag],
    if(Match(iLeaveReasonID,6,8,9,13,19),'Other',
    ApplyMap('LeaveReason_Map',iLeaveReasonID))				as [Leave Grouped Reason], 
    ApplyMap('LeaveReason_Map',iLeaveReasonID)				as [Leave Reason],
    iAddsDedsID												as [Transaction TypeID],
    ApplyMap('AdditionDeductions_Map',iAddsDedsID)			as [Transaction Type],
    if(Match(iAddsDedsID,1,4,5,9,10,11),'Salaries',
    if(Match(iAddsDedsID,22,23,24,26,27,29,30,31,32,33,34, 42,45,46,49,81,109,115,116,136,138,143, 154),'Other Benefits',
    if(Match(iAddsDedsID,35,41,104,125,126,127,128,129,130,131,132),'Termination')))										as [Transaction Group],
    iOtherLeaveID,
    iPostType,
    ApplyMap('CostCentre_Map',iCostAccountID)				as [Cost Centre],
    bPosted,
    Date(Left(dEffectiveDate,10))							as [Transaction Effective DateTMP],
    bIncludeInPayslip										as [Included in Payslip],
    bPayslipPrinted											as [Payslip Printed],
    bEFT													as [EFT],
    fHours													as [Hrs],
    fUnits													as [Units],
    fRate													as [Rate],
    fAmount													as [Amount],
    iSuperSchemeID,
    iSuperFundID,
    ApplyMap('SuperFund_Map',iSuperFundID)					as [Super Fund Name],
    fSGLSalaryAndWagesAmount								as [GL Amount],
    fSGLSalaryAndWagesHours									as [GL Hours];

SQL SELECT *
FROM Payroll.dbo."_ipvEmployeeTrans";
//Where dEffectiveDate >= '01/07/2007';

LOAD idEmployeeTrans										as [Transaction ID],
    iEmployeeID												as [Employee ID],
    iPeriodID												as [Transaction Period],
	//iEmployeeID&'|'&iPeriodID&'|'&iLeaveReasonID			as [Liability_KEY],
    iEmployeeID&'|'&iPeriodID								as Payroll_KEY,
    ApplyMap('Period_Map_ARCHIVE',iPeriodID)				as [Payroll Run Date],
    iSickLeaveID,
    iAnnualLeaveID,
    iLongServiceLeaveID,
    iLeaveReasonID											as [Leave Reason ID],
    if(Match(iLeaveReasonID,2,4,6,8,9,12,13,14,15,19),1,0)	as [Unplanned Leave Flag],
    if(Match(iLeaveReasonID,6,8,9,13,19),'Other',
    ApplyMap('LeaveReason_Map',iLeaveReasonID))				as [Leave Grouped Reason], 
    ApplyMap('LeaveReason_Map',iLeaveReasonID)				as [Leave Reason],
    iAddsDedsID												as [Transaction TypeID],
    ApplyMap('AdditionDeductions_Map',iAddsDedsID)			as [Transaction Type],
    if(Match(iAddsDedsID,1,4,5,9,10,11),'Salaries',
    if(Match(iAddsDedsID,22,23,24,26,27,29,30,31,32,33,34, 42,45,46,49,81,109,115,116,136,138,143, 154),'Other Benefits',
    if(Match(iAddsDedsID,35,41,104,125,126,127,128,129,130,131,132),'Termination')))							as [Transaction Group],
    iOtherLeaveID,
    iPostType,
    ApplyMap('CostCentre_Map',iCostAccountID)				as [Cost Centre],
    bPosted,
    Date(Left(dEffectiveDate,10))							as [Transaction Effective DateTMP],
    bIncludeInPayslip										as [Included in Payslip],
    bPayslipPrinted											as [Payslip Printed],
    bEFT													as [EFT],
    fHours													as [Hrs],
    fUnits													as [Units],
    fRate													as [Rate],
    fAmount													as [Amount],
    iSuperSchemeID,
    iSuperFundID,
    ApplyMap('SuperFund_Map',iSuperFundID)					as [Super Fund Name],
    fSGLSalaryAndWagesAmount								as [GL Amount],
    fSGLSalaryAndWagesHours									as [GL Hours];

SQL SELECT *
FROM "Payroll_Archive".dbo."_ipvEmployeeTrans";
    
    
Left Join (TransactionsTMP)
LOAD "Transaction Period"									as [Transaction Period],
     Date("Pay Week Date")									as [Pay Week Date]
     
FROM [lib://Manual Data (prdqs01_atobi)/PayRun Dates.xlsx] (ooxml, embedded labels, table is Sheet1);


Transactions:
NoConcatenate
LOAD *,
	 if([Transaction Effective DateTMP] < '01/02/2016',
     	"Pay Week Date",[Transaction Effective DateTMP])	as [Transaction Effective Date],
 If([Transaction Type] = 'Net Pay' 
 				//OR WildMatch([Transaction Type], '*Salary Sacrfice*', '*Salary Sacrif*')
                , 1, 0) as IncludeTrans_Flag,        
        
If(WIldmatch([Transaction Type], 'Tax','Normal Pay','Annual Leave'), 1, 0) as IncludeTrans_Flag2   

Resident TransactionsTMP
WHERE [Transaction Effective DateTMP] >= '01/07/2007';


//For budgets to align
Left Join (Transactions)
LOAD Distinct [Employee ID],
    [DivisionTMP]											as Division,
    [BranchTMP]												as Branch,
    "Default Cost Account DescriptionTMP"					as "Default Cost Account Description",
    if(wildmatch([Default Cost Account DescriptionTMP] = 'Employee Dentists', 'Lithgow Dental'),38,35)						as DfltHrsFTE
RESIDENT "Employee Details";



// //////////If statement on front end works status rework doesnt. Below is trying to add the If statement into the back////////////////////////////////


// Alex Graydon 07/03/2023
// Generate Monthly flags to indicate Employee status in any month

TermDate_Map:
MAPPING
LOAD [Employee ID],
	 [Termination Date]
RESIDENT [Employee Details];


LastRunDate_Map:
MAPPING
LOAD [Employee ID],
	 Date(Max([Payroll Run Date]))							as [Payroll Run Date]
RESIDENT Transactions
GROUP BY [Employee ID];


EmployeeStatus:
LOAD Payroll_KEY,
	 [Employee ID],
	 Division,
     Branch,
     [Default Cost Account Description],
     [Transaction TypeID],
	 [Payroll Run Date],
     [Last Payroll Run],
     If([Termination Date]-1<=[Payroll Run Date] and [Last Payroll Run],'Terminated','Active')	as [Employee Status],
     If([Termination Date]-1<=[Payroll Run Date] and [Last Payroll Run],0,1)					as [Active Flag],
     If([Termination Date]-1<=[Payroll Run Date] and [Last Payroll Run],1,0)					as [Terminated Flag],
     'Actual'																					as Source;
     
LOAD Payroll_KEY,
	 [Employee ID],
	 Division,
     Branch,
     [Default Cost Account Description],
     [Transaction TypeID],
	 [Payroll Run Date],
     If(ApplyMap('LastRunDate_Map',[Employee ID])=[Payroll Run Date],1,0)						as [Last Payroll Run],
     Coalesce(ApplyMap('TermDate_Map',[Employee ID],Null()),MakeDate(9999))						as [Termination Date]
     
RESIDENT Transactions;

DROP Fields Division,Branch,[Default Cost Account Description],[Payroll Run Date] FROM Transactions;
DROP fields DivisionTMP,BranchTMP,[Transaction Effective DateTMP];

DROP Table TransactionsTMP;

DentistLeaveHours:
NoConcatenate
Load 
	 Payroll_KEY,
    [Employee ID],
    [Cost Centre],
    [Hrs], 
    [Transaction Type], 
    [Leave Reason],
    'LeaveHrs' as SourceCalc
Resident Transactions
Where wildmatch([Transaction Type], 'Sick Leave', 'Annual Leave', 'Other Leave', 'Long Service Leave', 'Paid Maternity Leave');

Concatenate (DentistLeaveHours)
Load 
	 Payroll_KEY,
    [Employee ID],
    [Cost Centre],
    [Hrs], 
    [Transaction Type], 
    [Leave Reason],
    'HrsPaid' as SourceCalc
Resident Transactions
Where wildmatch([Transaction Type],'Annual Leave','Double Time Pay','Long Service Leave','Normal Pay','Other Leave','Sick Leave','Time and a Half Pay');

Left Join (DentistLeaveHours)
Load * 
Where [Default Cost Account Description] = 'Employee Dentists';
LOAD 
	Payroll_KEY,
	"Employee ID"															as [Employee ID],
    [Default Cost Account Description],
    	[Payroll Run Date]
Resident EmployeeStatus;   
   
Left Join (DentistLeaveHours)
LOAD "Employee ID"															as [Employee ID],
	 "Employee Code"														as [Employee Code],
    "Full Name"
Resident [Employee Details];

Store DentistLeaveHours into [lib://TransformData (prdqs01_atobi)/Finance/DentistLeaveHours.qvd] (qvd);
drop tables DentistLeaveHours;

DROP Fields [Employee ID] FROM Transactions;

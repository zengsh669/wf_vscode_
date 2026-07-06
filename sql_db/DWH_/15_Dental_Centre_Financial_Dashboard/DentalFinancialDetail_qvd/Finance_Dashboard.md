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
SET FirstMonthOfYear=7;
SET CollationLocale='en-AU';
SET CreateSearchIndexOnReload=1;
SET MonthNames='Jan.;Feb.;Mar.;Apr.;May;Jun.;Jul.;Aug.;Sep.;Oct.;Nov.;Dec.';
SET LongMonthNames='January;February;March;April;May;June;July;August;September;October;November;December';
SET DayNames='Mon.;Tue.;Wed.;Thu.;Fri.;Sat.;Sun.';
SET LongDayNames='Monday;Tuesday;Wednesday;Thursday;Friday;Saturday;Sunday';
SET NumericalAbbreviation='3:k;6:M;9:G;12:T;15:P;18:E;21:Z;24:Y;-3:m;-6:μ;-9:n;-12:p;-15:f;-18:a;-21:z;-24:y';

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

AcctType_Map:
Mapping
LOAD
    ACCTID,
    ACCTTYPE
FROM [lib://ExtractData (prdqs01_atobi)/AccPac_GL_Accounts.qvd]
(qvd);

GLStructure:
LOAD
    ACCTID,
    ACCTFMTTD								as [Account Display],
    ACCTDESC								as [Account Name],
    ApplyMap('AccountGrp_Map',ACCTGRPCOD)	as [Account Group],
    ACSEGVAL01								as [Account Num],
    ApplyMap('Segment2_Map',ACSEGVAL02)		as [Company],
    ApplyMap('Segment3_Map',ACSEGVAL03)		as [Division],
    ApplyMap('Segment4_Map',ACSEGVAL04)		as [State],
    ApplyMap('Segment5_Map',ACSEGVAL05)		as [Branch],
    ACSEGVAL05								as [Loc Code],
    ApplyMap('Segment6_Map',ACSEGVAL06)		as [Product],
    ApplyMap('Segment7_Map',ACSEGVAL07)		as [Cover],
    ApplyMap('Segment9_Map',ACSEGVAL09)		as [HO Department],
    ACSEGVAL02,
    ACSEGVAL03,
    ACSEGVAL01&'|'&ACSEGVAL03				as [ReportKEY]
FROM [lib://ExtractData (prdqs01_atobi)/AccPac_GL_Accounts.qvd]
(qvd);

AdditionalLayout:
LOAD
    "Range Start",
    "Range End",
    SortOrder,
    Level3,
    Level2,
    Level1,
    Report
FROM [lib://Manual Data (prdqs01_atobi)/Finance P&L Mapping.xlsx]
(ooxml, embedded labels, table is Sheet1)
Where Report = 'Dental';


TMP:
Load Distinct
	[Account Num]				
Resident GLStructure;

TMP2:
IntervalMatch ([Account Num])
LOAD "Range Start", "Range End" Resident AdditionalLayout;
Drop table TMP;


left join (AdditionalLayout)
Load * Resident TMP2;
Drop table TMP2;

TMPLayout2:
LOAD
    "Range Start",
    "Range End",
    SortOrder,
    Level3,
    Level2,
    Level1,
    Report
FROM [lib://Manual Data (prdqs01_atobi)/Finance P&L Mapping.xlsx]
(ooxml, embedded labels, table is Sheet1)
Where Report = 'Eyewear';

TMP:
Load Distinct
	[Account Num]
Resident GLStructure;

TMP2:
IntervalMatch ([Account Num])
LOAD "Range Start", "Range End" Resident TMPLayout2;
Drop table TMP;


left join (TMPLayout2)
Load * Resident TMP2;
Drop table TMP2;

Concatenate(AdditionalLayout)
Load * Resident TMPLayout2;
Drop table TMPLayout2;

TMPLayout3:
LOAD
    "Range Start",
    "Range End",
    SortOrder,
    Level3,
    Level2,
    Level1,
    Report
FROM [lib://Manual Data (prdqs01_atobi)/Finance P&L Mapping.xlsx]
(ooxml, embedded labels, table is Sheet1)
Where Report = 'Health';

TMP:
Load Distinct
	[Account Num]
Resident GLStructure;

TMP2:
IntervalMatch ([Account Num])
LOAD "Range Start", "Range End" Resident TMPLayout3;
Drop table TMP;


left join (TMPLayout3)
Load * Resident TMP2;
Drop table TMP2;

Concatenate(AdditionalLayout)
Load * Resident TMPLayout3;
Drop table TMPLayout3;

TMPLayout4:
LOAD
    "Range Start",
    "Range End",
    SortOrder,
    Level3,
    Level2,
    Level1,
    Report
FROM [lib://Manual Data (prdqs01_atobi)/Finance P&L Mapping.xlsx]
(ooxml, embedded labels, table is Sheet2)
Where Report = 'Consol';

TMP:
Load Distinct
	[Account Num]
Resident GLStructure
Where ACSEGVAL02 = '1';

TMP2:
IntervalMatch ([Account Num])
LOAD "Range Start", "Range End" Resident TMPLayout4;
Drop table TMP;


left join (TMPLayout4)
Load * Resident TMP2;
Drop table TMP2;


Concatenate(AdditionalLayout)
Load * Resident TMPLayout4;
Drop table TMPLayout4;
JournalsTMP:
Load *,
    dayname(ConvertToLocalTime(Timestamp#(AUDTDATE&AUDTTIME, 'YYYYMMDDhhmmssff'), 'Sydney'))		as [Create Date]
	;


LOAD
    ACCTID,
    JNLDTLREF&'>'&ACCTID															as _RCPACCTKEY,

    Applymap('AcctType_Map',ACCTID)													as [AcctType],
    //MakeDate(FISCALYR, Month(Date#(ApplyMap('Period_Map',FISCALPERD),'MMM')),'01')	as [Period Allocation Date],
    FISCALYR																		as [Fin Year],
	FISCALPERD																		as [Fin Period],
    Month(Date#(ApplyMap('Period_Map',FISCALPERD),'MMM'))							as [Month],
    FISCALYR&FISCALPERD																as Period,
    SRCELEDGER,
    SRCETYPE,
    POSTINGSEQ																		as [Journal ID],
    BATCHNBR																		as [Batch ID],
    CNTDETAIL,
    AUDTDATE,
//     Date(date#(date#(AUDTDATE, 'YYYYMMDD'), 'YYYYMMDD'))							as [Create Date],
//     AUDTTIME,
    num(AUDTTIME, 00000000)															as AUDTTIME,
    AUDTUSER																		as [Create User],
    AUDTORG,
    Date(date#(date#(JRNLDATE, 'YYYYMMDD'), 'YYYYMMDD'))							as [Post Date],
    COMPANYID,
    JNLDTLDESC																		as [Journal Detail],
    JNLDTLREF																		as [Journal Ref],
    TRANSAMT*-1																		as [Amount],
    TRANSQTY																		as [Quantity],
    DOCDATE																			as [Journal Date],
    'Actual'																		as [Source] 
FROM [lib://ExtractData (prdqs01_atobi)/AccPac_GL_Post.qvd]
(qvd)
Where FISCALPERD <= '12';

drop field AUDTDATE;

////Only P&L
Journals:
NoConcatenate
Load * Resident JournalsTMP
Where [AcctType] = 'I';
Drop table JournalsTMP;


    
//From another source system.  Qvd generated by the Daily PO application as data transfrom has been done in that application that 
//is required for the fields needed.
//SP (atobi) 18/04/2019
//CH (atobi) 21001/2020 - added RCPNUMBER and ACCTID key to link journal lines with correct Receipts.

Receipts:
LOAD
//    RCPNUMBER							as [Journal Ref],
    RCPNUMBER,
    RCPNUMBER&'>'&PurgeChar(ACCTID, '-')	as _RCPACCTKEY,
    "Receipt Date",
    RQNNUMBER,
    PONUMBER,
    VDCODE,
    VDNAME,
    TOTALVALUE,
    ITEMNO,
    STOCKITEM,
    ITEMDESC,
    REQRNAME
FROM [lib://TransformData (prdqs01_atobi)/Finance/ReceiptsForFinanceApp.qvd]
(qvd) where isnull(RCPNUMBER) = 0;

MAXPeriod:
NoConcatenate
Load
	Max(Period)				as MaxPeriod
Resident Journals;

Let vMaxPeriodTrans = Num(Peek('MaxPeriod',-1,'MAXPeriod'));



TMP:
CrossTable('PERIOD','BUDGET',14)
LOAD
    ACCTID,
    FSCSYR,
    FSCSDSG,
    FSCSCURN,
    CURNTYPE,
    AUDTDATE							as AUDTDATE_TMP,
    AUDTTIME,
    AUDTUSER,
    AUDTORG,
    SWRVL,
    CODERVL,
    SCURNDEC,
    OPENBAL,
    ACTIVITYSW,
    NETPERD1							as [01],
    NETPERD2							as [02],
    NETPERD3							as [03],
    NETPERD4							as [04],
    NETPERD5							as [05],
    NETPERD6							as [06],
    NETPERD7							as [07],
    NETPERD8							as [08],
    NETPERD9							as [09],
    NETPERD10							as [10],
    NETPERD11							as [11],
    NETPERD12							as [12]
FROM [lib://ExtractData (prdqs01_atobi)/AccPac_GL_Budget.qvd]
(qvd) where ACTIVITYSW = 1;


TMP2:
Load *,
	dayname(ConvertToLocalTime(Timestamp#(AUDTDATE_TMP&AUDTTIME, 'YYYYMMDDhhmmssff'), 'Sydney'))		as [AUDTDATE]
Resident TMP;
Drop table TMP;
drop field AUDTDATE_TMP;
rename table TMP2 to TMP;


TMPBUD:
NoConcatenate
Load
	ACCTID,
    //MakeDate(FSCSYR, Month(Date#(PERIOD,'MMM')),'01')	as [Period Allocation Date],
   FSCSDSG													as [Budget Version],
   FSCSYR													as [Fin Year],
    Month(Date#(ApplyMap('Period_Map',Num#(PERIOD)),'MMM'))	as [Month],
    Num(FSCSYR&PERIOD)										as Period,
    BUDGET*-1												as [Amount],
    'Budget'												as [Source]
Resident TMP;
Drop table TMP;    


Concatenate (Journals)
Load * resident TMPBUD;
//where Period <= '$(vMaxPeriodTrans)';
Drop table TMPBUD;


MedicareRevenue:
NoConcatenate
Load 
	ACCTID,
    [Create Date],
    [Create User],
    [Post Date],
    Period,
    [Journal ID],
    [Journal Detail],
    Amount,
    Quantity,
    [Journal Ref],   	
    [Fin Year],
    [Fin Period],
    [Month],
    Source,
    [Budget Version]
Resident Journals
where wildmatch(ACCTID, '41502E*');


inner Join (MedicareRevenue)
Load 
	ACCTID,
    [Account Display],
	[Account Name],
    [Loc Code]
Resident GLStructure
where Division = 'Eyeware';


Store MedicareRevenue into [lib://TransformData (prdqs01_atobi)/Finance/MedicareRevenueforEyeCare.qvd] (qvd);
drop tables MedicareRevenue;

CostofGoods:
NoConcatenate
Load 
	ACCTID,
    [Fin Year],
    [Fin Period],
    [Month],
    [Create Date],
    [Create User],
    [Post Date],
    Period,
    [Journal ID],
    [Journal Detail],
    Amount,
    Quantity,
    [Journal Ref],
    Source,
    [Budget Version]
Resident Journals
where wildmatch(ACCTID, '51*');


left Join (CostofGoods)
Load 
	ACCTID,
    [Account Display],
	[Account Name],
    [Loc Code]
Resident GLStructure;


Store CostofGoods into [lib://TransformData (prdqs01_atobi)/Finance/CostofGoodsforEyeCare.qvd] (qvd);
drop tables CostofGoods;

DentalDetail:
NoConcatenate
Load 
	ACCTID,
    [Create Date],
    [Create User],
    [Post Date],
    Period,
    [Journal ID],
    [Journal Detail],
    Amount,
    Quantity,
    [Journal Ref],   	
    [Fin Year],
    [Fin Period],
    [Month],
    Source,
    [Budget Version]
Resident Journals;


inner Join (DentalDetail)
Load 
	ACCTID,
    [Account Display],
	[Account Name],
    [Loc Code],
    [Branch],
    [Account Num]
Resident GLStructure
where Division = 'Dental';


left Join (DentalDetail)
load
    Level3,
    Level2,
    Level1,
    Report,
    [Account Num]
Resident AdditionalLayout;
    

Store DentalDetail into [lib://TransformData (prdqs01_atobi)/Finance/DentalFinancialDetail.qvd] (qvd);
drop tables DentalDetail;

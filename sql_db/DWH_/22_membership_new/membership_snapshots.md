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
SET NumericalAbbreviation='3:k;6:M;9:G;12:T;15:P;18:E;21:Z;24:Y;-3:m;-6:μ;-9:n;-12:p;-15:f;-18:a;-21:z;-24:y';

LET vToday			= num(If(Hour(Now())<17,Today()-1,Today()));
LET vSnapShotDate	= Date(vToday,'YYYYMMDD');
LET vSnapShotMonth	= Date(vToday,'YYYYMM');
LET vCalcDay		= Date(vToday);
LET vHistoryDay		= Date('31/8/2018');

LET vDataPath		= 'lib://ExtractData (prdqs01_atobi)/';
LET vTransformPath	= 'lib://TransformData (prdqs01_atobi)/Membership Snapshots/';

//TRACE vToday: $(vToday);
TRACE vSnapShotDate: $(vSnapShotDate);
//*****************************************************************************************************
//*	Daily membership Snapshot
//*
//*		Author:	Sharon Prior
//*		Date:	20/08/2018
//*
//*	HISTORY:
//*
//*		Date		Person			Description
//*		20/08/2019	Sharon Prior	Initial Version
//*		28/07/2021	Alex Graydon	Move History Section here so code block is complete
//*
//*****************************************************************************************************

if Today() <= '$(vHistoryDay)' then

History:
LOAD
    "Membership Number",
    1								as Joins,
    "Effective Join Date",
    "Effective Join Date"			as Date  
   
FROM [lib://TransformData (prdqs01_atobi)/Membership_Transformed.qvd] (qvd)
Where "Effective Join Date" <= '$(vHistoryDay)';

Concatenate(History)
LOAD
    "Membership Number",
    1								as Terminations,
    "Effective Termination Date"	as Date  
   
FROM [lib://TransformData (prdqs01_atobi)/Membership_Transformed.qvd] (qvd)
Where "Membership Status" = 'Terminated' and "Effective Termination Date" <= '$(vHistoryDay)';

Store History into [lib://TransformData (prdqs01_atobi)/Membership Snapshots/Movement_Summary_Tmp_History.qvd] (qvd);
Drop table History;


Else

Membership_status_map:
Mapping
LOAD "memship_status",
    if(Match(description,'Sales Lead','Prospective'),'Lead/Prospect',description)	as description
FROM ['$(vDataPath)'Paragon_Memship_status.qvd] (qvd);

Cover_Type_Map:
Mapping
LOAD
    cover_type,
    description
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_CoverType.qvd]
(qvd);

Hear_About:
Mapping
Load Distinct
    hear_about_id,
    description
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_HearAbout.qvd]
(qvd);

Channel_Map:
Mapping
LOAD
    sales_channel_id,
    description
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_PromoSalesChannel.qvd]
(qvd);


"Memberships":
LOAD Distinct
    "membership_id"																	as [Membership Number],
    fund_id,
    termination_code,
    applymap('Membership_status_map',"memship_status",'MISSING') 					as [Membership Status],
    date(floor("effective_join_date")) 												as [Effective Join Date],
    date(floor("effective_termination_date"))										as [Effective Termination Date],
    Date(Floor(Today()))															as [SnapShot Date],
    "create_operator"																as [Create Operator],
     state
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_Memberships.qvd]
(qvd)
Where Match("memship_status",'A','T');


left join (Memberships)
LOAD 
	"membership_id"															as [Membership Number],
    "group_id"																as [Agent ID],
    description																as [Agent]
FROM ['$(vDataPath)'Paragon_MemberAgent.qvd](qvd);

left join (Memberships)
LOAD
    "membership_id"															as [Membership Number],
	"group_id"																as [Branch ID],
    description																as [Branch]
FROM ['$(vDataPath)'Paragon_MemberBranch.qvd](qvd);


let vStat = NoOfRows('Memberships');
Load * Inline [
Stat, 						Rows,				Comment
Membership Table, 			'$(vStat)',			Before Join];

		
Left Join (Memberships)
LOAD 
	"membership_id"												as [Membership Number],
	FixCode														as [Product Code],
    "cover_type"												as [Cover Type],
    description													as [Cover Description],
    "Product_Description"										as [Product Description],
    ApplyMap('Cover_Type_Map', cover_type, 'Missing') 			as [Cover Type Description]
FROM ['$(vDataPath)'Paragon_MemberCover.qvd](qvd);

let vStat = NoOfRows('Memberships');
Load * Inline [
Stat, 						Rows,				Comment
Membership Table, 			'$(vStat)',			After Product Join];

TMPPerson:
LOAD
    Count(person_id)											as [Person Count],
    membership_id												as [Membership Number]
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_PersonMembership.qvd]
(qvd)
Where isnull(termination_date)
Group by membership_id;

Left Join (Memberships)
Load * Resident TMPPerson;
Drop table TMPPerson;

"PersonMaxVerTMP":
LOAD "membership_id"														as [Membership Number],
    "person_id"																as [Person ID]
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_PersonContact.qvd]
(qvd) Where relationship = 1;

left Join("PersonMaxVerTMP")
Load Distinct 
	person_id																as [Person ID],
    Max(person_version)														as [Max Person Version]
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_Person.qvd]
(qvd)
Group by person_id;


left Join("PersonMaxVerTMP")
LOAD
    person_id																as [Person ID],
    person_version															as [Max Person Version],
    applymap('Hear_About',"hear_about_id",'MISSING')						as [Hear About],
    date_of_birth															as [Date of Birth]
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_Person.qvd]
(qvd);

left Join ("PersonMaxVerTMP")
LOAD 
	"person_id"																as [Person ID],
    "membership_id"															as [Membership Number],
    postcode																as [Person Postcode]
FROM ['$(vDataPath)'Paragon_PersonPostal.qvd](qvd);


TMPPROMO:
LOAD 
    main_ref																as [Person ID],
    Max(status_date)														as [status_date]
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_PromoReference.qvd]
(qvd) Group by main_ref;

Left Join (TMPPROMO)
Load
	main_ref																as [Person ID],
 	promotion_id															as [Promotion ID],
    applymap('Channel_Map',sales_channel_id,'MISSING')						as [Sales Channel],
    [status_date]
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_PromoReference.qvd]
(qvd);

left Join("PersonMaxVerTMP")
Load * Resident TMPPROMO;
Drop table TMPPROMO;

left join (Memberships)
Load * Resident PersonMaxVerTMP;
Drop table PersonMaxVerTMP;

TMPFees:
LOAD Distinct
    membership_id,
    Max(cover_version)														as [Max Cover Version]
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_Cover_Product.qvd]
(qvd)
Group By membership_id;

Left Join (TMPFees)
LOAD Distinct
    membership_id,
    cover_version															as [Max Cover Version],
	product_id
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_Cover_Product.qvd]
(qvd);

MaxTmp:
NoConcatenate
LOAD
    product_id,
    Max(product_fee_version)							as [Max Product Fee Version]
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_Product_Fee.qvd]
(qvd) where status_flag = 'A'
Group By product_id;

left Join (MaxTmp)
Load
	product_id,
    cover_state											as state,
    cover_type											as [Cover Type],
	product_fee_version									as [Max Product Fee Version],
    product_fee_amount									as [Weekly Amount]
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_Product_Fee.qvd]
(qvd);

left Join (TMPFees)
Load * Resident MaxTmp;
Drop table MaxTmp;

SumFees:
NoConcatenate
Load
	membership_id										as [Membership Number],
    state,
    [Cover Type],
    Sum([Weekly Amount])								as [Weekly Total Premium]
Resident TMPFees
Group By membership_id,state,[Cover Type];
Drop table TMPFees;

left Join (Memberships)
Load
  [Membership Number],
  state,
  [Cover Type],
  [Weekly Total Premium],
  [Weekly Total Premium] * 52									as [Annual Total Premium]
Resident SumFees;
Drop table SumFees;



STORE Memberships into [lib://TransformData (prdqs01_atobi)/Membership Snapshots/Membership_SnapShot_$(vSnapShotDate).qvd] (qvd);
STORE Memberships into [lib://TransformData (prdqs01_atobi)/Membership Snapshots/Membership_SnapShot_Latest.qvd] (qvd);


Drop table Memberships;

endif;
//*****************************************************************************************************
//*	Monthly membership Snapshot
//*
//*		Author:	Alex Graydon
//*		Date:	03/11/2021
//*
//*	HISTORY:
//*
//*		Date		Person			Description
//*		03/11/2021	Alex Graydon	Initial Version
//*		08/11/2021	Alex Graydon	Add Premium data for Broker Commission
//*
//*****************************************************************************************************

Memberships_Tmp:
LOAD * FROM [lib://TransformData (prdqs01_atobi)/Membership Snapshots/Membership_SnapShot_Latest.qvd] (qvd);
DROP Fields "Weekly Total Premium","Annual Total Premium";


LEFT JOIN (Memberships_Tmp)
LOAD Distinct "Membership Number",
     "origin_number"												as [Origin Number],
     Num(member1_loading/100,'#0.0%')								as [Member1 Loading],
     Num(member2_loading/100,'#0.0%')								as [Member2 Loading],
     Num("Overall Aged Discount"/100,'#0.0%')						as [Overall Aged Discount]
FROM [lib://TransformData (prdqs01_atobi)/Membership_Transformed.qvd] (qvd); 


LEFT JOIN (Memberships_Tmp)
LOAD "Membership Number",
     "Annual Total Premium"											as [Annual Total Amount],
     "Annual Auxillary Amount",
     "Annual Hospital Amount"
FROM [lib://TransformData (prdqs01_atobi)/ProductPremium_View_Transformed.qvd] (qvd);


LEFT JOIN (Memberships_Tmp)
LOAD membership_id													as [Membership Number],
     Num(discount_amount/100,'#0.0%')								as [Agent Discount]
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_MemberAgent.qvd] (qvd)
WHERE discount_amount > 0
AND isnull(termination_date);


Memberships:
LOAD *,
	 [Annual LHC Amount]+[Annual Total Amount]
     	-[Annual Agent Discount]-[Annual Age Discount Amount]  		as [Annual Total Premium];
     
LOAD *,
	 "Annual Hospital Amount" * "Overall Aged Discount"				as [Annual Age Discount Amount],
     "Annual Total Amount" * alt("Agent Discount",0)				as [Annual Agent Discount],
     Alt(if(match("Cover Type",'C','F'),  
   		RangeAvg("Member1 Loading","Member2 Loading"), 
     	"Member1 Loading") * "Annual Hospital Amount",0)			as [Annual LHC Amount]

RESIDENT Memberships_Tmp;


STORE Memberships into [lib://TransformData (prdqs01_atobi)/Membership Snapshots/Membership_Month_SnapShot_$(vSnapShotMonth).qvd] (qvd);

DROP Tables Memberships_Tmp,Memberships;

//*****************************************************************************************************
//*	Load all snapshots
//*	AG 28 July 2021 Mod to improve performance only load the daily snapshot files that are required
//*		1. Today - Run date if after 5pm Run date -1 if before
//*		2. Yesterday - Starting from Today-1 find the last daily snapshot
//*		3. Previous Month - Find the last snapshot for the previous month
//*		4. Previous FY - Find the last snapshot for the previous financial year
//*		5. Month LY - Find the last snapshot for the same month of the previous year
//*
//*		Author:	Sharon Prior
//*		Date:	20/08/2018
//*
//*	HISTORY:
//*
//*		Date		Person			Description
//*		20/08/2019	Sharon Prior	Initial Version
//*		28/07/2021	Alex Graydon	Only load Required days for calculating movements to improve performance
//*
//*****************************************************************************************************

DatesToLoad:
LOAD $(vSnapShotDate)	as DateToLoad
AUTOGENERATE 1;

// Find Previous Snapshot date/file 
LET vFound 			= 0;
LET vFileDateNum	= vToday-1;

DO While vFound=0
   
    FOR Each vFile in FileList(vTransformPath & 'Membership_SnapShot_' & Date(vFileDateNum,'YYYYMMDD') & '.qvd')
    	TRACE $(vFile);
        LET vPreviousDay = Date(vFileDateNum);
        
        DatesToLoad:
		LOAD Date($(vFileDateNum),'YYYYMMDD')	as DateToLoad
		AUTOGENERATE 1;
        
		LET vFound = 1;
    NEXT

	LET vFileDateNum = vFileDateNum - 1;

LOOP

// Find Previous Month Last Snapshot date/file 
LET vFound 			= 0;
LET vFileDateNum	= MonthStart(vToday)-1;

DO While vFound=0
   
    FOR Each vFile in FileList(vTransformPath & 'Membership_SnapShot_' & Date(vFileDateNum,'YYYYMMDD') & '.qvd')
    	TRACE $(vFile);
        LET vPreviousMonth = Date(vFileDateNum);
        
        DatesToLoad:
		LOAD Date($(vFileDateNum),'YYYYMMDD')	as DateToLoad
		AUTOGENERATE 1;
        
		LET vFound = 1;
    NEXT

	LET vFileDateNum = vFileDateNum - 1;

LOOP

// Find Last Snapshot date/file of the previous financial year
LET vFound 			= 0;
LET vFileDateNum	= Floor(YearEnd(vToday,-1,7));

DO While vFound=0
   
    FOR Each vFile in FileList(vTransformPath & 'Membership_SnapShot_' & Date(vFileDateNum,'YYYYMMDD') & '.qvd')
    	TRACE $(vFile);
        LET vLYStart = Date(vFileDateNum);
        
        DatesToLoad:
		LOAD Date($(vFileDateNum),'YYYYMMDD')	as DateToLoad
		AUTOGENERATE 1;        
        
		LET vFound = 1;
    NEXT

	LET vFileDateNum = vFileDateNum - 1;

LOOP

// Find Last Snapshot date/file of the same month last year
LET vFound 			= 0;
LET vFileDateNum	= Floor(Monthend(AddMonths(vToday,-12)));

DO While vFound=0
   
    FOR Each vFile in FileList(vTransformPath & 'Membership_SnapShot_' & Date(vFileDateNum,'YYYYMMDD') & '.qvd')
    	
        LET vLYMonth = Date(vFileDateNum);
        
        DatesToLoad:
		LOAD Date($(vFileDateNum),'YYYYMMDD')	as DateToLoad
		AUTOGENERATE 1;        
        
		LET vFound = 1;
    NEXT

	LET vFileDateNum = vFileDateNum - 1;

LOOP


DateList:
LOAD Concat(DISTINCT DateToLoad,',')			as DateList
RESIDENT DatesToLoad;

LET vDatestoLoad	= Peek('DateList');
DROP Tables DateList,DatesToLoad;

TRACE vDatestoLoad: $(vDatestoLoad);
TRACE ;


FOR Each vFileDateNum in $(vDatestoLoad)

Step1a:
LOAD [SnapShot Date],
     [Membership Number],
     [Membership Status],
     [Product Code],
     [Effective Join Date],
     [Effective Termination Date],
     [Cover Type],
     [Person Count],
     state,
     fund_id,
     termination_code,
     "Create Operator",
     "Agent ID",
     Agent,
     "Branch ID",
     Branch,
     "Hear About",
     "Date of Birth",
     //"Promotion ID",
     MaxString("Sales Channel")				as [Sales Channel], //To address history files, 27/09 rectified to have no duplicates
     "Weekly Total Premium",
     "Annual Total Premium"
FROM [$(vTransformPath)Membership_SnapShot_$(vFileDateNum).qvd] (qvd)
GROUP BY [SnapShot Date],
    [Membership Number],
    [Membership Status],
    [Product Code],
    [Effective Join Date],
    [Effective Termination Date],
    [Cover Type],
    [Person Count],
    state,
    fund_id,
    termination_code,
    "Create Operator",
    "Agent ID",
    Agent,
    "Branch ID",
    Branch,
    "Hear About",
    "Date of Birth",
    "Weekly Total Premium",
    "Annual Total Premium";

NEXT;

//*****************************************************************************************************
//*	Calculate Daily Movements
//*		Compares latest snapshot to the previous one
//*
//*		Author:	Sharon Prior
//*		Date:	20/08/2018
//*
//*	HISTORY:
//*
//*		Date		Person			Description
//*		20/08/2019	Sharon Prior	Initial Version
//*		28/07/2021	Alex Graydon	Variables for dates are set in Base Load
//*
//*****************************************************************************************************

// Let vPreviousDay = Date(Floor(Today()-1));
// Let vCalcDay = Date(Floor(Today()));

TRACE vPreviousDay: $(vPreviousDay);
TRACE vCalcDay: $(vCalcDay);
TRACE ;

Step1b:
NoConcatenate
Load 
	[SnapShot Date],
    [Membership Number],
    [Membership Status],
    [Product Code],
    [Effective Join Date],
    [Effective Termination Date],
    [Cover Type],
    [Person Count],
    state,
    fund_id,
    termination_code,
    "Create Operator",
    "Agent ID",
    Agent,
    "Branch ID",
    Branch,
    "Hear About",
    "Date of Birth",
    //"Promotion ID",
    "Sales Channel",
    "Weekly Total Premium",
    "Annual Total Premium"
Resident Step1a
Where [SnapShot Date] >= '$(vPreviousDay)';
//Drop table Step1a;


//Joins and terminations movements
Step2:
NoConcatenate
Load
	[SnapShot Date],
    [Membership Number],
    [Membership Status],
    [Product Code],
    [Effective Join Date],
    [Effective Termination Date],
    [Cover Type],
    [Person Count],
    state,
    fund_id,
    termination_code,
    "Create Operator",
    "Agent ID",
    Agent,
    "Branch ID",
    Branch,
    "Hear About",
    "Date of Birth",
    //"Promotion ID",
    "Sales Channel",
    "Weekly Total Premium",
    "Annual Total Premium"
Resident Step1b
Order by [Membership Number],[SnapShot Date] asc;
Drop table Step1b;

Step2b:
NoConcatenate
Load
	*,
	if(Previous([Membership Number]) <> [Membership Number] and
    	[Membership Status] = 'Active',1,0)										as [New Join Flag],
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	Previous([Membership Status]) = 'Active' and 
        [Membership Status] = 'Terminated',1,0)									as [Terminated Flag],
    
    if([Membership Status] = 'Active' and
    	[Effective Join Date] > Monthend(Today()),1,0)							as [Financial Join Flag]   ,
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous([Product Code]) <> [Product Code]	,1,0)						as [Product Change Flag],
   
   if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous([Product Code]) <> [Product Code],Previous([Product Code])	)	as [Old Product Code],
      [Product Code]															as [Current Product Code],
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous([Cover Type]) <> [Cover Type]	,1,0)							as [Cover Change Flag],
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous([Cover Type]) <> [Cover Type],Previous([Cover Type])	)		as [Old Cover Type],
     [Cover Type]																as [Current Cover Type],
   
   if(	Previous([Membership Number]) = [Membership Number] and
   		[Membership Status] = 'Active' and
    	Previous([Person Count]) <> [Person Count]	,1,0)						as [Person Count Change Flag],
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous([Person Count]) <> [Person Count],Previous([Person Count])	)	as [Old Person Count],
     [Person Count]																as [Current Person Count],
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Sales Channel") <> "Sales Channel",1,0)						as [Sales Channel Flag],
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Sales Channel") <> "Sales Channel",Previous("Sales Channel")) as [Old Sales Channel],
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Agent") <> "Agent",1,0)										as [Agent Flag],
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Agent") <> "Agent",Previous("Agent")) 						as [Old Agent],
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Branch") <> "Branch",1,0)										as [Branch Flag],
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Branch") <> "Branch",Previous("Branch")) 						as [Old Branch],
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") <> "Product Code" and
        Previous("Annual Total Premium") < "Annual Total Premium",1,0)			as [Product Upgrade],
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") <> "Product Code" and
        Previous("Annual Total Premium") < "Annual Total Premium",
        Previous([Product Code])) 												as [Product Upgrade Old Product], 
	
	if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") <> "Product Code" and
        Previous("Annual Total Premium") > "Annual Total Premium",1,0)			as [Product Downgrade],
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") <> "Product Code" and
        Previous("Annual Total Premium") > "Annual Total Premium",
        Previous([Product Code])) 												as [Product Downgrade Old Product], 
	
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") = "Product Code" and
        Previous(state) <> state and
        Previous("Annual Total Premium") < "Annual Total Premium",1,0)			as [Other/State Upgrade],
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") = "Product Code" and
        Previous(state) <> state and
        Previous("Annual Total Premium") < "Annual Total Premium",
        Previous(state)) 														as [Other/State Upgrade Old State], 
	
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") = "Product Code" and
        Previous(state) <> state and
        Previous("Annual Total Premium") > "Annual Total Premium",1,0)			as [Other/State Downgrade],
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") = "Product Code" and
        Previous(state) <> state and
        Previous("Annual Total Premium") > "Annual Total Premium",
        Previous(state)) 														as [Other/State Downgrade Old State], 
	
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") = "Product Code" and
        Previous(state) = state and
        Previous("Annual Total Premium") < "Annual Total Premium",1,0)			as [Annual Premium increase Flag],
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") = "Product Code" and
        Previous(state) = state and
        Previous("Annual Total Premium") > "Annual Total Premium",1,0)			as [Annual Premium decrease Flag]
    
//     if(Previous([Membership Number]) <> [Membership Number] and
//     	[Membership Status] = 'Active',
//         age([Effective Join Date],"Date of Birth"))								as [New Join Age],
//     if(	Previous([Membership Number]) = [Membership Number] and
//     	Previous([Membership Status]) = 'Active' and 
//         [Membership Status] = 'Terminated',
//         age([Effective Termination Date],"Date of Birth"))						as [Terminated Age]
    
Resident Step2;
Drop table Step2;

Step2c:
NoConcatenate
Load *
Resident Step2b 
Where [SnapShot Date] = '$(vCalcDay)';

Drop table Step2b;

Movement:
NoConcatenate
Load
	[SnapShot Date]										as [Date],
    [Membership Number],
	[New Join Flag]										as [Joins],
    [Financial Join Flag],
    [Effective Join Date],
    age([Effective Join Date],"Date of Birth")			as [New Join Age]
//    [New Join Age]
Resident Step2c
Where ([New Join Flag] = 1 or [Financial Join Flag] = 1);// and [SnapShot Date] = '$(vCalcDay)';

Concatenate (Movement)
Load
	[SnapShot Date]										as [Date],
    [Membership Number],
	[Terminated Flag]									as [Terminations],
    age([Effective Termination Date],"Date of Birth")	as [Terminated Age]
//    [Terminated Age]
Resident Step2c
Where [Terminated Flag] = 1;// and [SnapShot Date] = '$(vCalcDay)';

Concatenate (Movement)
Load
	[SnapShot Date]										as [Date],
    [Membership Number],
	[Product Change Flag]								as [Product Change Flag],
    [Old Product Code],
    [Current Product Code]
Resident Step2c
Where [Product Change Flag] = 1;// and [SnapShot Date] = '$(vCalcDay)';

Concatenate (Movement)
Load
	[SnapShot Date]										as [Date],
    [Membership Number],
	[Cover Change Flag],
    [Old Cover Type],
    [Current Cover Type]
Resident Step2c
Where [Cover Change Flag] = 1;// and [SnapShot Date] = '$(vCalcDay)';

Concatenate (Movement)
Load
	[SnapShot Date]										as [Date],
    [Membership Number],
	[Person Count Change Flag],
    [Old Person Count],
    [Current Person Count]
Resident Step2c
Where [Person Count Change Flag] = 1;// and [SnapShot Date] = '$(vCalcDay)';

Concatenate (Movement)
Load
	[SnapShot Date]										as [Date],
    [Membership Number],
	[Sales Channel Flag],
    [Old Sales Channel],
    [Sales Channel]										as [Current Sales Channel]
Resident Step2c
Where [Sales Channel Flag] = 1;

Concatenate (Movement)
Load
	[SnapShot Date]										as [Date],
    [Membership Number],
	[Agent Flag],
    [Old Agent],
    [Agent]												as [Current Agent]
Resident Step2c
Where [Agent Flag] = 1;


Concatenate (Movement)
Load
	[SnapShot Date]										as [Date],
    [Membership Number],
	[Branch Flag],
    [Old Branch],
    [Branch]											as [Current Branch]
Resident Step2c
Where [Branch Flag] = 1;

Concatenate (Movement)
Load
	[SnapShot Date]										as [Date],
    [Membership Number],
	[Product Upgrade],
    [Product Upgrade Old Product],
    [Product Code]										as [Upgrade Current Product Code]
Resident Step2c
Where [Product Upgrade] = 1;

Concatenate (Movement)
Load
	[SnapShot Date]										as [Date],
    [Membership Number],
	[Product Downgrade],
    [Product Downgrade Old Product],
    [Product Code]										as [Downgrade Current Product Code]
Resident Step2c
Where [Product Downgrade] = 1;

Concatenate (Movement)
Load
	[SnapShot Date]										as [Date],
    [Membership Number],
	[Other/State Upgrade],
    [Other/State Upgrade Old State],
    state												as [Other Upgrade Current State]
Resident Step2c
Where [Other/State Upgrade] = 1;

Concatenate (Movement)
Load
	[SnapShot Date]										as [Date],
    [Membership Number],
	[Other/State Downgrade],
    [Other/State Downgrade Old State],
    state												as [Other Downgrade Current State]
Resident Step2c
Where [Other/State Downgrade] = 1;

Concatenate (Movement)
Load
	[SnapShot Date]										as [Date],
    [Membership Number],
	[Annual Premium increase Flag]
Resident Step2c
Where [Annual Premium increase Flag] = 1;

Concatenate (Movement)
Load
	[SnapShot Date]										as [Date],
    [Membership Number],
	[Annual Premium decrease Flag]
Resident Step2c
Where [Annual Premium decrease Flag] = 1;

Drop table Step2c;

Movement_Summary:
NoConcatenate
LOAD *
FROM [$(vTransformPath)Movement_Summary.qvd] (qvd) 
where [Date] < '$(vCalcDay)';

Concatenate (Movement_Summary)
Load *
Resident Movement;

Drop table Movement;


Store Movement_Summary into [$(vTransformPath)Movement_Summary.qvd] (qvd);
Drop table Movement_Summary;

//*****************************************************************************************************
//*	Calculate Monthly Movements
//*		Compares latest snapshot to the last one in the previous month
//*
//*		Author:	Sharon Prior
//*		Date:	20/08/2018
//*
//*	HISTORY:
//*
//*		Date		Person			Description
//*		20/08/2019	Sharon Prior	Initial Version
//*		28/07/2021	Alex Graydon	Variables for dates are set in Base Load
//*
//*****************************************************************************************************

// Let  vPreviousMonth = Date(MonthStart(Floor(Today()))-1);
// Let  vCalcDay = Date(Floor(Today()));

TRACE vPreviousMonth: $(vPreviousMonth);
TRACE vCalcDay: $(vCalcDay);
TRACE ;

Step1b:
NoConcatenate
Load Distinct
	[SnapShot Date],
    [Membership Number],
    [Membership Status],
    [Product Code],
    [Effective Join Date],
    [Effective Termination Date],
    [Cover Type],
    [Person Count],
    state,
    fund_id,
    termination_code,
    "Create Operator",
    "Agent ID",
    Agent,
    "Branch ID",
    Branch,
    "Hear About",
    "Date of Birth",
    //"Promotion ID",
    "Sales Channel",
    "Weekly Total Premium",
    "Annual Total Premium"
Resident Step1a
Where [SnapShot Date] = '$(vPreviousMonth)';
Concatenate (Step1b)
Load Distinct
	[SnapShot Date],
    [Membership Number],
    [Membership Status],
    [Product Code],
    [Effective Join Date],
    [Effective Termination Date],
    [Cover Type],
    [Person Count],
    state,
    fund_id,
    termination_code,
    "Create Operator",
    "Agent ID",
    Agent,
    "Branch ID",
    Branch,
    "Hear About",
    "Date of Birth",
    //"Promotion ID",
    "Sales Channel",
    "Weekly Total Premium",
    "Annual Total Premium"
Resident Step1a
Where [SnapShot Date] = '$(vCalcDay)';
//Drop table Step1a;



//Joins and terminations movements
Step2:
NoConcatenate
Load
	[SnapShot Date],
    [Membership Number],
    [Membership Status],
    [Product Code],
    [Effective Join Date],
    [Effective Termination Date],
    [Cover Type],
    [Person Count],
    state,
    fund_id,
    termination_code,
    "Create Operator",
    "Agent ID",
    Agent,
    "Branch ID",
    Branch,
    "Hear About",
    "Date of Birth",
    //"Promotion ID",
    "Sales Channel",
    "Weekly Total Premium",
    "Annual Total Premium"
Resident Step1b
Order by [Membership Number],[SnapShot Date] asc;
drop table Step1b;


Step2b:
NoConcatenate
Load
	*,
	if(Previous([Membership Number]) <> [Membership Number] and
    	[Membership Status] = 'Active',1,0)										as [New Join Flag],
        
    if(	Previous([Membership Number]) = [Membership Number] and
    	Previous([Membership Status]) <> 'Active' and 
        [Membership Status] = 'Active',1,0)										as [Rejoin Flag],
        
    if(Previous([Membership Number]) = [Membership Number] and
    	Previous([Membership Status]) = 'Active' and 
        [Membership Status] = 'Suspended',1,0)									as [Suspended Flag],    
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	Previous([Membership Status]) = 'Active' and 
        [Membership Status] = 'Terminated',1,0)									as [Terminated Flag],
    
    if(Previous([Membership Number]) <> [Membership Number] and
    	[Membership Status] = 'Active' and
    	[Effective Join Date] > Monthend(Today()),1,0)							as [Financial Join Flag]   ,
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous([Product Code]) <> [Product Code]	,1,0)						as [Product Change Flag],
   
   if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous([Product Code]) <> [Product Code],Previous([Product Code])	)	as [Old Product Code],
      [Product Code]															as [Current Product Code],
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous([Cover Type]) <> [Cover Type]	,1,0)							as [Cover Change Flag],
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous([Cover Type]) <> [Cover Type],Previous([Cover Type])	)		as [Old Cover Type],
     [Cover Type]																as [Current Cover Type],
   
   if(	Previous([Membership Number]) = [Membership Number] and
   		[Membership Status] = 'Active' and
    	Previous([Person Count]) <> [Person Count]	,1,0)						as [Person Count Change Flag],
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous([Person Count]) <> [Person Count],Previous([Person Count])	)	as [Old Person Count],
     [Person Count]																as [Current Person Count],
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Sales Channel") <> "Sales Channel",1,0)						as [Sales Channel Flag],
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Sales Channel") <> "Sales Channel",Previous("Sales Channel")) as [Old Sales Channel],
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Agent") <> "Agent",1,0)										as [Agent Flag],
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Agent") <> "Agent",Previous("Agent")) 						as [Old Agent],
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Branch") <> "Branch",1,0)										as [Branch Flag],
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Branch") <> "Branch",Previous("Branch")) 						as [Old Branch],
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") <> "Product Code" and
        Previous("Annual Total Premium") < "Annual Total Premium",1,0)			as [Product Upgrade],
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") <> "Product Code" and
        Previous("Annual Total Premium") < "Annual Total Premium",
        Previous([Product Code])) 												as [Product Upgrade Old Product], 
	
     if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") <> "Product Code" and
        Previous("Annual Total Premium") < "Annual Total Premium",
        Previous("Annual Total Premium")) 										as [Product Upgrade Old Premium],
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") <> "Product Code" and
        Previous("Annual Total Premium") < "Annual Total Premium",
        ("Annual Total Premium")) 												as [Product Upgrade New Premium],
        
	if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") <> "Product Code" and
        Previous("Annual Total Premium") > "Annual Total Premium",1,0)			as [Product Downgrade],
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") <> "Product Code" and
        Previous("Annual Total Premium") > "Annual Total Premium",
        Previous([Product Code])) 												as [Product Downgrade Old Product], 
        
         if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") <> "Product Code" and
        Previous("Annual Total Premium") > "Annual Total Premium",
        Previous("Annual Total Premium")) 										as [Product Downgrade Old Premium], 
        
         if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") <> "Product Code" and
        Previous("Annual Total Premium") > "Annual Total Premium",
        ("Annual Total Premium")) 												as [Product Downgrade New Premium], 
	
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") = "Product Code" and
        Previous(state) <> state and
        Previous("Annual Total Premium") < "Annual Total Premium",1,0)			as [Other/State Upgrade],
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") = "Product Code" and
        Previous(state) <> state and
        Previous("Annual Total Premium") < "Annual Total Premium",
        Previous(state)) 														as [Other/State Upgrade Old State], 
        
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") = "Product Code" and
        Previous(state) <> state and
        Previous("Annual Total Premium") < "Annual Total Premium",
        Previous("Annual Total Premium")) 										as [Other/State Upgrade Old Premium],
        
     if(Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") = "Product Code" and
        Previous(state) <> state and
        Previous("Annual Total Premium") < "Annual Total Premium",
        ("Annual Total Premium")) 												as [Other/State Upgrade New Premium],
	
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") = "Product Code" and
        Previous(state) <> state and
        Previous("Annual Total Premium") > "Annual Total Premium",1,0)			as [Other/State Downgrade],
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") = "Product Code" and
        Previous(state) <> state and
        Previous("Annual Total Premium") > "Annual Total Premium",
        Previous(state)) 														as [Other/State Downgrade Old State], 
        
         if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") = "Product Code" and
        Previous(state) <> state and
        Previous("Annual Total Premium") > "Annual Total Premium",
        Previous("Annual Total Premium")) 										as [Other/State Downgrade Old Premium], 
        
         if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") = "Product Code" and
        Previous(state) <> state and
        Previous("Annual Total Premium") > "Annual Total Premium",
        ("Annual Total Premium")) 												as [Other/State Downgrade New Premium], 
        
	
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") = "Product Code" and
        Previous(state) = state and
        Previous("Annual Total Premium") < "Annual Total Premium",1,0)			as [Annual Premium increase Flag],
        
            if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") = "Product Code" and
        Previous(state) = state and
        Previous("Annual Total Premium") < "Annual Total Premium",
        Previous("Annual Total Premium"))										as [Annual Premium increase Old Premium],
        
           if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") = "Product Code" and
        Previous(state) = state and
        Previous("Annual Total Premium") < "Annual Total Premium",
        ("Annual Total Premium"))												as [Annual Premium increase New Premium],
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") = "Product Code" and
        Previous(state) = state and
        Previous("Annual Total Premium") > "Annual Total Premium",1,0)			as [Annual Premium decrease Flag],
        
        if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") = "Product Code" and
        Previous(state) = state and
        Previous("Annual Total Premium") > "Annual Total Premium",
        Previous("Annual Total Premium"))										as [Annual Premium decrease Old Premium],
                
        if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") = "Product Code" and
        Previous(state) = state and
        Previous("Annual Total Premium") > "Annual Total Premium",
        ("Annual Total Premium"))												as [Annual Premium decrease New Premium]
    
//     if(Previous([Membership Number]) <> [Membership Number] and
//     	[Membership Status] = 'Active',
//         age([Effective Join Date],"Date of Birth"))								as [New Join Age],
//     if(	Previous([Membership Number]) = [Membership Number] and
//     	Previous([Membership Status]) = 'Active' and 
//         [Membership Status] = 'Terminated',
//         age([Effective Termination Date],"Date of Birth"))						as [Terminated Age]//,
    
//     if(	Previous([Membership Number]) = [Membership Number] and
//     	[Membership Status] = 'Active' and
//     	Previous("[Person Postcode]") <> "[Person Postcode]",1,0)				as [PostCode Flag],
//     [Person Postcode]															as [Current PostCode],
//     if(	Previous([Membership Number]) = [Membership Number] and
//     	[Membership Status] = 'Active' and
//     	Previous("[Person Postcode]") <> "[Person Postcode]",
//         Previous("[Person Postcode]")) 											as [Old Branch]
    
Resident Step2;
Drop table Step2;

Step2c:
NoConcatenate
Load *
Resident Step2b 
Where [SnapShot Date] = '$(vCalcDay)';

Drop table Step2b;

Movement:
NoConcatenate
Load
	[SnapShot Date]										as [Date],
    [Membership Number],
	[New Join Flag]+[Rejoin Flag]						as [Joins],
    [Financial Join Flag],
    [Effective Join Date],
	age([Effective Join Date],"Date of Birth")			as [New Join Age],    
//    [New Join Age],
    [Rejoin Flag]
Resident Step2c
Where ([New Join Flag] = 1 or [Financial Join Flag] = 1 or [Rejoin Flag] = 1);// and [SnapShot Date] = '$(vCalcDay)';

Concatenate (Movement)
Load
	[SnapShot Date]										as [Date],
    [Membership Number],
	[Terminated Flag]									as [Terminations],
	age([Effective Termination Date],"Date of Birth")	as [Terminated Age]    
//    [Terminated Age]
Resident Step2c
Where [Terminated Flag] = 1;// and [SnapShot Date] = '$(vCalcDay)';

Concatenate(Movement)
Load [SnapShot Date]									as [Date],
    [Membership Number],
	[Suspended Flag]									as [Suspensions]
Resident Step2c
Where [Suspended Flag] = 1;

Concatenate (Movement)
Load
	[SnapShot Date]										as [Date],
    [Membership Number],
	[Product Change Flag]								as [Product Change Flag],
    [Old Product Code],
    [Current Product Code]
Resident Step2c
Where [Product Change Flag] = 1;// and [SnapShot Date] = '$(vCalcDay)';

Concatenate (Movement)
Load
	[SnapShot Date]										as [Date],
    [Membership Number],
	[Cover Change Flag],
    [Old Cover Type],
    [Current Cover Type]
Resident Step2c
Where [Cover Change Flag] = 1;// and [SnapShot Date] = '$(vCalcDay)';

Concatenate (Movement)
Load
	[SnapShot Date]										as [Date],
    [Membership Number],
	[Person Count Change Flag],
    [Old Person Count],
    [Current Person Count]
Resident Step2c
Where [Person Count Change Flag] = 1;// and [SnapShot Date] = '$(vCalcDay)';

Concatenate (Movement)
Load
	[SnapShot Date]										as [Date],
    [Membership Number],
	[Sales Channel Flag],
    [Old Sales Channel],
    [Sales Channel]										as [Current Sales Channel]
Resident Step2c
Where [Sales Channel Flag] = 1;

Concatenate (Movement)
Load
	[SnapShot Date]										as [Date],
    [Membership Number],
	[Agent Flag],
    [Old Agent],
    [Agent]												as [Current Agent]
Resident Step2c
Where [Agent Flag] = 1;


Concatenate (Movement)
Load
	[SnapShot Date]										as [Date],
    [Membership Number],
	[Branch Flag],
    [Old Branch],
    [Branch]											as [Current Branch]
Resident Step2c
Where [Branch Flag] = 1;

Concatenate (Movement)
Load
	[SnapShot Date]										as [Date],
    [Membership Number],
	[Product Upgrade],
    [Product Upgrade Old Product],
    [Product Code]										as [Upgrade Current Product Code],
    [Product Upgrade New Premium],
    [Product Upgrade Old Premium]
Resident Step2c
Where [Product Upgrade] = 1;

Concatenate (Movement)
Load
	[SnapShot Date]										as [Date],
    [Membership Number],
	[Product Downgrade],
    [Product Downgrade Old Product],
    [Product Code]										as [Downgrade Current Product Code],
    [Product Downgrade New Premium],
    [Product Downgrade Old Premium]
Resident Step2c
Where [Product Downgrade] = 1;

Concatenate (Movement)
Load
	[SnapShot Date]										as [Date],
    [Membership Number],
	[Other/State Upgrade],
    [Other/State Upgrade Old State],
    state												as [Other Upgrade Current State],
    [Other/State Upgrade New Premium],
    [Other/State Upgrade Old Premium]
Resident Step2c
Where [Other/State Upgrade] = 1;

Concatenate (Movement)
Load
	[SnapShot Date]										as [Date],
    [Membership Number],
	[Other/State Downgrade],
    [Other/State Downgrade Old State],
    state												as [Other Downgrade Current State],
    [Other/State Downgrade Old Premium],
    [Other/State Downgrade New Premium]
Resident Step2c
Where [Other/State Downgrade] = 1;

Concatenate (Movement)
Load
	[SnapShot Date]										as [Date],
    [Membership Number],
	[Annual Premium increase Flag],
    [Annual Premium increase Old Premium],
    [Annual Premium increase New Premium]
Resident Step2c
Where [Annual Premium increase Flag] = 1;

Concatenate (Movement)
Load
	[SnapShot Date]										as [Date],
    [Membership Number],
	[Annual Premium decrease Flag],
    [Annual Premium decrease New Premium],
    [Annual Premium decrease Old Premium]
Resident Step2c
Where [Annual Premium decrease Flag] = 1;

// Concatenate (Movement)
// Load
// 	[SnapShot Date]										as [Date],
//     [Membership Number],
// 	[PostCode Flag],
//     [Old PostCode],
//     [Current PostCode]
// Resident Step2c
// Where [PostCode Flag] = 1;

Drop table Step2c;

// ///If you need to rebuild for the first month comparison use below
// Store Movement into [lib://TransformData (prdqs01_atobi)/Membership Snapshots/MTD_Movement_Summary.qvd] (qvd);
// Exit script;

//if Date(Floor(today())) = MonthEnd(Date(Floor(Today())))  then
Monthly_Movement_Summary:
NoConcatenate
LOAD *
FROM [$(vTransformPath)MTD_Movement_Summary.qvd] (qvd) 
where [Date] <= '$(vPreviousMonth)';

Concatenate (Monthly_Movement_Summary)
Load *
Resident Movement;

Drop table Movement;



Store Monthly_Movement_Summary into [$(vTransformPath)MTD_Movement_Summary.qvd] (qvd);

Drop table Monthly_Movement_Summary;



//*****************************************************************************************************
//*	Calculate YTD Movements
//*		Compares latest snapshot to the last one in the previous financial year
//*
//*		Author:	Sharon Prior
//*		Date:	20/08/2018
//*
//*	HISTORY:
//*
//*		Date		Person			Description
//*		20/08/2019	Sharon Prior	Initial Version
//*		28/07/2021	Alex Graydon	Variables for dates are set in Base Load
//*
//*****************************************************************************************************

// vLYStart = MakeDate(if(Month(Today())>=7,Year(Today()),Year(Today())-1),'06','30');
// vCalcDay = Date(Floor(Today()));

TRACE vLYStart: $(vLYStart);
TRACE vCalcDay: $(vCalcDay);
TRACE ;

Step1b:
NoConcatenate
Load *
Resident Step1a
Where [SnapShot Date] = '$(vLYStart)';

Concatenate (Step1b)
Load *
Resident Step1a
Where [SnapShot Date] = '$(vCalcDay)';
//Drop table Step1a;



//Joins and terminations movements
Step2:
NoConcatenate
Load
	[SnapShot Date],
    [Membership Number],
    [Membership Status],
    [Product Code],
    [Effective Join Date],
    [Effective Termination Date],
    [Cover Type],
    [Person Count],
    state,
    fund_id,
    termination_code,
    "Create Operator",
    "Agent ID",
    Agent,
    "Branch ID",
    Branch,
    "Hear About",
    "Date of Birth",
    //"Promotion ID",
    "Sales Channel",
    "Weekly Total Premium",
    "Annual Total Premium"
Resident Step1b
Order by [Membership Number],[SnapShot Date] asc;

drop table Step1b;


Step2b:
NoConcatenate
Load
	*,
	if(Previous([Membership Number]) <> [Membership Number] and
    	[Membership Status] = 'Active',1,0)										as [New Join Flag],
        
    if(	Previous([Membership Number]) = [Membership Number] and
    	Previous([Membership Status]) <> 'Active' and 
        [Membership Status] = 'Active',1,0)										as [Rejoin Flag],
        
    if(Previous([Membership Number]) = [Membership Number] and
    	Previous([Membership Status]) = 'Active' and 
        [Membership Status] = 'Suspended',1,0)									as [Suspended Flag],    
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	Previous([Membership Status]) = 'Active' and 
        [Membership Status] = 'Terminated',1,0)									as [Terminated Flag],
    
    if(Previous([Membership Number]) <> [Membership Number] and
    	[Membership Status] = 'Active' and
    	[Effective Join Date] > MakeDate(Year(Today()),'06','30'),1,0)			as [Financial Join Flag]   ,
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous([Product Code]) <> [Product Code]	,1,0)						as [Product Change Flag],
   
   if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous([Product Code]) <> [Product Code],Previous([Product Code])	)	as [Old Product Code],
      [Product Code]															as [Current Product Code],
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous([Cover Type]) <> [Cover Type]	,1,0)							as [Cover Change Flag],
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous([Cover Type]) <> [Cover Type],Previous([Cover Type])	)		as [Old Cover Type],
     [Cover Type]																as [Current Cover Type],
   
   if(	Previous([Membership Number]) = [Membership Number] and
   		[Membership Status] = 'Active' and
    	Previous([Person Count]) <> [Person Count]	,1,0)						as [Person Count Change Flag],
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous([Person Count]) <> [Person Count],Previous([Person Count])	)	as [Old Person Count],
     [Person Count]																as [Current Person Count],
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Sales Channel") <> "Sales Channel",1,0)						as [Sales Channel Flag],
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Sales Channel") <> "Sales Channel",Previous("Sales Channel")) as [Old Sales Channel],
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Agent") <> "Agent",1,0)										as [Agent Flag],
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Agent") <> "Agent",Previous("Agent")) 						as [Old Agent],
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Branch") <> "Branch",1,0)										as [Branch Flag],
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Branch") <> "Branch",Previous("Branch")) 						as [Old Branch],
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") <> "Product Code" and
        Previous("Annual Total Premium") < "Annual Total Premium",1,0)			as [Product Upgrade],
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") <> "Product Code" and
        Previous("Annual Total Premium") < "Annual Total Premium",
        Previous([Product Code])) 												as [Product Upgrade Old Product], 
	
     if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") <> "Product Code" and
        Previous("Annual Total Premium") < "Annual Total Premium",
        Previous("Annual Total Premium")) 										as [Product Upgrade Old Premium],
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") <> "Product Code" and
        Previous("Annual Total Premium") < "Annual Total Premium",
        ("Annual Total Premium")) 												as [Product Upgrade New Premium],
        
	if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") <> "Product Code" and
        Previous("Annual Total Premium") > "Annual Total Premium",1,0)			as [Product Downgrade],
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") <> "Product Code" and
        Previous("Annual Total Premium") > "Annual Total Premium",
        Previous([Product Code])) 												as [Product Downgrade Old Product], 
        
         if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") <> "Product Code" and
        Previous("Annual Total Premium") > "Annual Total Premium",
        Previous("Annual Total Premium")) 										as [Product Downgrade Old Premium], 
        
         if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") <> "Product Code" and
        Previous("Annual Total Premium") > "Annual Total Premium",
        ("Annual Total Premium")) 												as [Product Downgrade New Premium], 
	
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") = "Product Code" and
        Previous(state) <> state and
        Previous("Annual Total Premium") < "Annual Total Premium",1,0)			as [Other/State Upgrade],
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") = "Product Code" and
        Previous(state) <> state and
        Previous("Annual Total Premium") < "Annual Total Premium",
        Previous(state)) 														as [Other/State Upgrade Old State], 
        
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") = "Product Code" and
        Previous(state) <> state and
        Previous("Annual Total Premium") < "Annual Total Premium",
        Previous("Annual Total Premium")) 										as [Other/State Upgrade Old Premium],
        
     if(Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") = "Product Code" and
        Previous(state) <> state and
        Previous("Annual Total Premium") < "Annual Total Premium",
        ("Annual Total Premium")) 												as [Other/State Upgrade New Premium],
	
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") = "Product Code" and
        Previous(state) <> state and
        Previous("Annual Total Premium") > "Annual Total Premium",1,0)			as [Other/State Downgrade],
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") = "Product Code" and
        Previous(state) <> state and
        Previous("Annual Total Premium") > "Annual Total Premium",
        Previous(state)) 														as [Other/State Downgrade Old State], 
        
         if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") = "Product Code" and
        Previous(state) <> state and
        Previous("Annual Total Premium") > "Annual Total Premium",
        Previous("Annual Total Premium")) 										as [Other/State Downgrade Old Premium], 
        
         if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") = "Product Code" and
        Previous(state) <> state and
        Previous("Annual Total Premium") > "Annual Total Premium",
        ("Annual Total Premium")) 												as [Other/State Downgrade New Premium], 
        
	
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") = "Product Code" and
        Previous(state) = state and
        Previous("Annual Total Premium") < "Annual Total Premium",1,0)			as [Annual Premium increase Flag],
        
            if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") = "Product Code" and
        Previous(state) = state and
        Previous("Annual Total Premium") < "Annual Total Premium",
        Previous("Annual Total Premium"))										as [Annual Premium increase Old Premium],
        
           if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") = "Product Code" and
        Previous(state) = state and
        Previous("Annual Total Premium") < "Annual Total Premium",
        ("Annual Total Premium"))												as [Annual Premium increase New Premium],
    
    if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") = "Product Code" and
        Previous(state) = state and
        Previous("Annual Total Premium") > "Annual Total Premium",1,0)			as [Annual Premium decrease Flag],
        
        if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") = "Product Code" and
        Previous(state) = state and
        Previous("Annual Total Premium") > "Annual Total Premium",
        Previous("Annual Total Premium"))										as [Annual Premium decrease Old Premium],
                
        if(	Previous([Membership Number]) = [Membership Number] and
    	[Membership Status] = 'Active' and
    	Previous("Product Code") = "Product Code" and
        Previous(state) = state and
        Previous("Annual Total Premium") > "Annual Total Premium",
        ("Annual Total Premium"))												as [Annual Premium decrease New Premium]
    
//     if(Previous([Membership Number]) <> [Membership Number] and
//     	[Membership Status] = 'Active',
//         age([Effective Join Date],"Date of Birth"))								as [New Join Age],
//     if(	Previous([Membership Number]) = [Membership Number] and
//     	Previous([Membership Status]) = 'Active' and 
//         [Membership Status] = 'Terminated',
//         age([Effective Termination Date],"Date of Birth"))						as [Terminated Age]//,
    
//     if(	Previous([Membership Number]) = [Membership Number] and
//     	[Membership Status] = 'Active' and
//     	Previous("[Person Postcode]") <> "[Person Postcode]",1,0)				as [PostCode Flag],
//     [Person Postcode]															as [Current PostCode],
//     if(	Previous([Membership Number]) = [Membership Number] and
//     	[Membership Status] = 'Active' and
//     	Previous("[Person Postcode]") <> "[Person Postcode]",
//         Previous("[Person Postcode]")) 											as [Old Branch]
    
Resident Step2;
Drop table Step2;

Step2c:
NoConcatenate
Load *
Resident Step2b 
Where [SnapShot Date] = '$(vCalcDay)';

Drop table Step2b;

Movement:
NoConcatenate
Load
	[SnapShot Date]										as [Date],
    [Membership Number],
	[New Join Flag]+[Rejoin Flag]						as [Joins],
    [Financial Join Flag],
    [Effective Join Date],
    age([Effective Join Date],"Date of Birth")			as [New Join Age],
//    [New Join Age],
    [Rejoin Flag]
Resident Step2c
Where ([New Join Flag] = 1 or [Financial Join Flag] = 1 or [Rejoin Flag] = 1);// and [SnapShot Date] = '$(vCalcDay)';

Concatenate (Movement)
Load
	[SnapShot Date]										as [Date],
    [Membership Number],
	[Terminated Flag]									as [Terminations],
    age([Effective Termination Date],"Date of Birth")	as [Terminated Age]
//    [Terminated Age]
Resident Step2c
Where [Terminated Flag] = 1;// and [SnapShot Date] = '$(vCalcDay)';

Concatenate(Movement)
Load [SnapShot Date]									as [Date],
    [Membership Number],
	[Suspended Flag]									as [Suspensions]
Resident Step2c
Where [Suspended Flag] = 1;

Concatenate (Movement)
Load
	[SnapShot Date]										as [Date],
    [Membership Number],
	[Product Change Flag]								as [Product Change Flag],
    [Old Product Code],
    [Current Product Code]
Resident Step2c
Where [Product Change Flag] = 1;// and [SnapShot Date] = '$(vCalcDay)';

Concatenate (Movement)
Load
	[SnapShot Date]										as [Date],
    [Membership Number],
	[Cover Change Flag],
    [Old Cover Type],
    [Current Cover Type]
Resident Step2c
Where [Cover Change Flag] = 1;// and [SnapShot Date] = '$(vCalcDay)';

Concatenate (Movement)
Load
	[SnapShot Date]										as [Date],
    [Membership Number],
	[Person Count Change Flag],
    [Old Person Count],
    [Current Person Count]
Resident Step2c
Where [Person Count Change Flag] = 1;// and [SnapShot Date] = '$(vCalcDay)';

Concatenate (Movement)
Load
	[SnapShot Date]										as [Date],
    [Membership Number],
	[Sales Channel Flag],
    [Old Sales Channel],
    [Sales Channel]										as [Current Sales Channel]
Resident Step2c
Where [Sales Channel Flag] = 1;

Concatenate (Movement)
Load
	[SnapShot Date]										as [Date],
    [Membership Number],
	[Agent Flag],
    [Old Agent],
    [Agent]												as [Current Agent]
Resident Step2c
Where [Agent Flag] = 1;


Concatenate (Movement)
Load
	[SnapShot Date]										as [Date],
    [Membership Number],
	[Branch Flag],
    [Old Branch],
    [Branch]											as [Current Branch]
Resident Step2c
Where [Branch Flag] = 1;

Concatenate (Movement)
Load
	[SnapShot Date]										as [Date],
    [Membership Number],
	[Product Upgrade],
    [Product Upgrade Old Product],
    [Product Code]										as [Upgrade Current Product Code],
    [Product Upgrade New Premium],
    [Product Upgrade Old Premium]
Resident Step2c
Where [Product Upgrade] = 1;

Concatenate (Movement)
Load
	[SnapShot Date]										as [Date],
    [Membership Number],
	[Product Downgrade],
    [Product Downgrade Old Product],
    [Product Code]										as [Downgrade Current Product Code],
    [Product Downgrade New Premium],
    [Product Downgrade Old Premium]
Resident Step2c
Where [Product Downgrade] = 1;

Concatenate (Movement)
Load
	[SnapShot Date]										as [Date],
    [Membership Number],
	[Other/State Upgrade],
    [Other/State Upgrade Old State],
    state												as [Other Upgrade Current State],
    [Other/State Upgrade New Premium],
    [Other/State Upgrade Old Premium]
Resident Step2c
Where [Other/State Upgrade] = 1;

Concatenate (Movement)
Load
	[SnapShot Date]										as [Date],
    [Membership Number],
	[Other/State Downgrade],
    [Other/State Downgrade Old State],
    state												as [Other Downgrade Current State],
    [Other/State Downgrade Old Premium],
    [Other/State Downgrade New Premium]
Resident Step2c
Where [Other/State Downgrade] = 1;

Concatenate (Movement)
Load
	[SnapShot Date]										as [Date],
    [Membership Number],
	[Annual Premium increase Flag],
    [Annual Premium increase Old Premium],
    [Annual Premium increase New Premium]
Resident Step2c
Where [Annual Premium increase Flag] = 1;

Concatenate (Movement)
Load
	[SnapShot Date]										as [Date],
    [Membership Number],
	[Annual Premium decrease Flag],
    [Annual Premium decrease New Premium],
    [Annual Premium decrease Old Premium]
Resident Step2c
Where [Annual Premium decrease Flag] = 1;

// Concatenate (Movement)
// Load
// 	[SnapShot Date]										as [Date],
//     [Membership Number],
// 	[PostCode Flag],
//     [Old PostCode],
//     [Current PostCode]
// Resident Step2c
// Where [PostCode Flag] = 1;

Drop table Step2c;

//if Date(Floor(today())) = MonthEnd(Date(Floor(Today())))  then
YTD_Movement_Summary:
NoConcatenate
LOAD *
FROM [$(vTransformPath)YTD_Movement_Summary.qvd] (qvd) 
where [Date] <= '$(vLYStart)';

Concatenate (YTD_Movement_Summary)
Load *
Resident Movement;

Drop table Movement;

// Store Movement into [lib://TransformData (prdqs01_atobi)/Membership Snapshots/YTD_Movement_Summary.qvd] (qvd);
// exit script;

Store YTD_Movement_Summary into [$(vTransformPath)YTD_Movement_Summary.qvd] (qvd);

Drop table YTD_Movement_Summary;

//*****************************************************************************************************
//*	Calculate Growth and Retention Rates
//*		Compares latest snapshot to the last one in the same month previous year
//*
//*		Author:	Sharon Prior
//*		Date:	20/08/2018
//*
//*	HISTORY:
//*
//*		Date		Person			Description
//*		20/08/2019	Sharon Prior	Initial Version
//*		28/07/2021	Alex Graydon	Variables for dates are set in Base Load
//*
//*****************************************************************************************************

//MonthlyRetention
// Let  vPreviousMonth = Date(Monthend(AddMonths(Floor(Today()),-12)));
// Let  vCalcDay = Date(Floor(Today()));

TRACE vLYMonth: $(vLYMonth);
TRACE vCalcDay: $(vCalcDay);
TRACE ;

 
Step1b:
NoConcatenate
Load Distinct
	[SnapShot Date],
    [Membership Number],
    [Product Code],
    [Cover Type],
    "Sales Channel",
    1									as [Retained Count]
Resident Step1a
Where [SnapShot Date] = '$(vCalcDay)' 
and [Membership Status] = 'Active' 
and not Match([Product Code],'AMBU','AMBUU','AMB','PAM','BAM');

//AG 28 June 21 this element creates an orphaned table in previous version
//             as has a noconcatenate statement
// Concatenate(Step1b)
// Load Distinct
// 	[SnapShot Date],
//     [Membership Number],
//     [Product Code],
//     [Cover Type],
//     "Sales Channel",
//     1									as [Retained Count]
// Resident Step1a
// Where [SnapShot Date] = '$(vCalcDay)' 
// and [Membership Status] = 'Terminated' 
// and [Effective Termination Date] > MonthEnd('$(vCalcDay)')
// and not Match([Product Code],'AMBU','AMBUU','AMB','PAM','BAM');


Step1c:
NoConcatenate
Load distinct
	'$(vCalcDay)'						as [SnapShot Date],
	[Membership Number],
    [Product Code]						as [TMPProductCode],
    [Cover Type]						as [TMPCoverType],
    "Sales Channel"						as [TMPSalesChannel],
    1									as [Previous MemberCount]
Resident Step1a
Where [SnapShot Date] = '$(vLYMonth)' 
and [Membership Status] = 'Active' 
and not Match([Product Code],'AMBU','AMBUU','AMB','PAM','BAM');

Left Join (Step1c)
Load * Resident Step1b;
Drop table Step1b;



Step1d:
NoConcatenate
Load [SnapShot Date],
	 [Membership Number],
     [Retained Count],
     [Previous MemberCount],
     If(Isnull([Product Code]),[TMPProductCode],[Product Code])			as [Product Code],
     If(Isnull([Cover Type]),[TMPCoverType],[Cover Type])				as [Cover Type],
     If(Isnull("Sales Channel"),[TMPSalesChannel],"Sales Channel")		as "Sales Channel"
Resident Step1c;

Drop table Step1c;


RetentionRates:
NoConcatenate
LOAD * 
FROM [$(vTransformPath)MonthlyRetentionRates.qvd] (qvd)
WHERE "SnapShot Date" <= Date(Monthend(AddMonths($(vToday),-1)));

TMPDateMax:
Load Max("SnapShot Date")		as MaxDate
Resident RetentionRates;

Let  vMaxDateStore = Peek('MaxDate',0,'TMPDateMax');
Drop Table TMPDateMax;

Concatenate(RetentionRates)
LOAD *
RESIDENT Step1d
WHERE [SnapShot Date] > '$(vMaxDateStore)';

Drop table Step1d;



Store RetentionRates into [$(vTransformPath)MonthlyRetentionRates.qvd] (qvd);
Drop table RetentionRates;



/* Section to just get counts per file for Growth rates
------------------------------------------------------------------*/

MemberCount_Summary:
NoConcatenate
LOAD *
FROM [$(vTransformPath)MemberCount_Summary.qvd] (qvd) 
where [SnapShot Date] < '$(vCalcDay)';

Concatenate (MemberCount_Summary)
LOAD Distinct
 	[SnapShot Date],
    Count([Membership Number])					as MembershipCount
RESIDENT Step1a
WHERE [Membership Status] = 'Active'
AND [SnapShot Date] = '$(vCalcDay)'
GROUP BY [SnapShot Date];

Store MemberCount_Summary into [$(vTransformPath)MemberCount_Summary.qvd] (qvd);
Drop table MemberCount_Summary;

// Step1a_MemberCountTMP:
// NoConcatenate
// Load Distinct
//  	[SnapShot Date],
//     Count([Membership Number])					as MembershipCount
// Resident Step1a
// Where  [Membership Status] = 'Active'
// Group By [SnapShot Date];

// Step1b_MemberCountTMP:
// NoConcatenate
// LOAD
//     "SnapShot Date",
//     MembershipCount
// FROM [$(vTransformPath)MemberCount_Summary.qvd] (qvd);

// TMPCount1:
// Load
// Max("SnapShot Date")		as MaxCountDate
// Resident Step1b_MemberCountTMP;

// Let  vMaxCountDate = Peek('MaxCountDate',0,'TMPCount1');
// Drop Table TMPCount1;

// Concatenate(Step1b_MemberCountTMP)
// Load *
// Resident Step1a_MemberCountTMP
// Where [SnapShot Date] > '$(vMaxCountDate)';

// Drop table Step1a_MemberCountTMP;

// Store Step1b_MemberCountTMP into [$(vTransformPath)MemberCount_Summary.qvd] (qvd);
// Drop table Step1b_MemberCountTMP;
/*------------------------------------------------------------------*/

drop Table Step1a;

exit script;
Drop Table Step1a;

Exit Script;


# Qualtrics NPS Score

Qlik load script for the "Qualtrics NPS Score" app.

```qlik
SET ThousandSep=',';
SET DecimalSep='.';
SET MoneyThousandSep=',';
SET MoneyDecimalSep='.';
SET MoneyFormat='$#,##0.00;-$#,##0.00';
SET TimeFormat='hh:mm:ss';
SET DateFormat='D/M/YYYY';
SET TimestampFormat='D/M/YYYY hh:mm:ss';
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

//*****************************************************************************************************
//*	Load Qualtrix Responses for all Surveys
//*
//*		Author:	Alex Graydon
//*		Date:	21/10/2021
//*
//*	HISTORY:
//*
//*		Date		Person					Description
//*		21/10/2021	Alex Graydon			Initial Version
//*		15/12/2021	Kathryn Whitehouse		Added StartDate, MonthYear & EndDate to the DataforBI Export
//*
//*****************************************************************************************************

NPS_Score:
LOAD *
FROM [lib://TransformData (prdqs01_atobi)/Qualtrics/Qualtrics_CSAT.qvd] (qvd)
WHERE Len(Trim("Member Number"))>0;


CONCATENATE (NPS_Score)
LOAD *
FROM [lib://TransformData (prdqs01_atobi)/Qualtrics/Qualtrics_POC.qvd] (qvd)
WHERE Len(Trim("Member Number"))>0;


CONCATENATE (NPS_Score)
LOAD *
FROM [lib://TransformData (prdqs01_atobi)/Qualtrics/Qualtrics_HealthServices.qvd] (qvd)
WHERE Len(Trim("Member Number"))>0;


CONCATENATE (NPS_Score)
LOAD *
FROM [lib://TransformData (prdqs01_atobi)/Qualtrics/Qualtrics_MentalHealth.qvd] (qvd)
WHERE Len(Trim("Member Number"))>0;


CONCATENATE (NPS_Score)
LOAD *
FROM [lib://TransformData (prdqs01_atobi)/Qualtrics/Qualtrics_Wellbeing.qvd] (qvd)
WHERE Len(Trim("Member Number"))>0;


CONCATENATE (NPS_Score)
LOAD *
FROM [lib://TransformData (prdqs01_atobi)/Qualtrics/Qualtrics_Wellbeing_V2.qvd] (qvd)
WHERE Len(Trim("Member Number"))>0;



/*

AG - 20260630 moved to Qualtrics Data Extract as transforms should not be done in presentation Apps 

DataforBI:
NoConcatenate
Load
	Survey_id,
    [Survey Name]							as SurveyName,
    ResponseId,
    Interaction,
    StartDate,
    MonthYear,
    EndDate,
    "Provider/Program/Staff"				as Provider_Program_Staff,
    [Provider Type]							as ProviderType,
    ProviderNo,
    [Provider Address]						as ProviderAddress,
    [Provider Suburb]						as ProviderSuburb,
    [Provider State]						as ProviderState,
    [Provider Postcode]						as ProviderPostcode,
    Product									as MembershipProduct,
    [Member Number]							as MembershipNumber,
    ClaimNo,
    Postcode								as MemberPostcode,
    State									as MemberState,
    Region									as MemberBranch,
    [Customer Satisfaction Level]			as CustomerSatisfactionLevel,
    [Customer Satisfaction Score]			as CustomerSatisfactionScore,
    [Customer Effort Level]					as CustomerEffortLevel,
    [Net Promoter Level] 					as NetPromoterLevel,
    [Net Promoter Score]					as NetPromoterScore
Resident NPS_Score
where StartDate >= MakeDate(Year(AddYears(today(), -5)), 7, 1)
and [Survey Name] = 'Customer Satisfaction Survey'
and match(Interaction, 'Eye Care', 'Dental');



Concatenate (DataforBI)
Load
	Survey_id,
    [Survey Name]							as SurveyName,
    ResponseId,
    Interaction,
    StartDate,
    EndDate,
    "Provider/Program/Staff"				as Provider_Program_Staff,
    [Provider Type]							as ProviderType,
    ProviderNo,
    [Provider Address]						as ProviderAddress,
    [Provider Suburb]						as ProviderSuburb,
    [Provider State]						as ProviderState,
    [Provider Postcode]						as ProviderPostcode,
    Product									as MembershipProduct,
    [Member Number]							as MembershipNumber,
    ClaimNo,
    Postcode								as MemberPostcode,
    State									as MemberState,
    Region									as MemberBranch,
    [Customer Satisfaction Level]			as CustomerSatisfactionLevel,
    [Customer Satisfaction Score]			as CustomerSatisfactionScore,
    [Customer Effort Level]					as CustomerEffortLevel,
    [Net Promoter Level] 					as NetPromoterLevel,
    [Net Promoter Score]					as NetPromoterScore
Resident NPS_Score
where StartDate >= MakeDate(Year(AddYears(today(), -5)), 7, 1)
and not match([Survey Name], 'Customer Satisfaction Survey');



STORE "DataforBI" INTO [lib://prdqs01_QlikData_Export_Files/InsightActuary/QualtricsSurveyData.csv] (txt);

drop table DataforBI;

*/
/*
AG - 20260630 moved to Qualtrics Data Extract as transforms should not be done in presentation Apps 

DataforScreen:
NoConcatenate
Load
	Survey_id,
    [Survey Name]							as SurveyName,
    ResponseId,
    Interaction,
    StartDate,
    MonthYear,
    EndDate,
    "Provider/Program/Staff"				as Provider_Program_Staff,
    [Provider Type]							as ProviderType,
    ProviderNo,
    [Provider Address]						as ProviderAddress,
    [Provider Suburb]						as ProviderSuburb,
    [Provider State]						as ProviderState,
    [Provider Postcode]						as ProviderPostcode,
    Product									as MembershipProduct,
    [Member Number]							as MembershipNumber,
    ClaimNo,
    Postcode								as MemberPostcode,
    State									as MemberState,
    Region									as MemberBranch,
    [Customer Satisfaction Level]			as CustomerSatisfactionLevel,
    [Customer Satisfaction Score]			as CustomerSatisfactionScore,
    [Customer Effort Level]					as CustomerEffortLevel,
    [Net Promoter Level] 					as NetPromoterLevel,
    [Net Promoter Score]					as NetPromoterScore
Resident NPS_Score
where StartDate >= MakeDate(Year(AddYears(today(), -5)), 7, 1);



Concatenate (DataforScreen)
Load
	Survey_id,
    [Survey Name]							as SurveyName,
    ResponseId,
    Interaction,
    StartDate,
    EndDate,
    "Provider/Program/Staff"				as Provider_Program_Staff,
    [Provider Type]							as ProviderType,
    ProviderNo,
    [Provider Address]						as ProviderAddress,
    [Provider Suburb]						as ProviderSuburb,
    [Provider State]						as ProviderState,
    [Provider Postcode]						as ProviderPostcode,
    Product									as MembershipProduct,
    [Member Number]							as MembershipNumber,
    ClaimNo,
    Postcode								as MemberPostcode,
    State									as MemberState,
    Region									as MemberBranch,
    [Customer Satisfaction Level]			as CustomerSatisfactionLevel,
    [Customer Satisfaction Score]			as CustomerSatisfactionScore,
    [Customer Effort Level]					as CustomerEffortLevel,
    [Net Promoter Level] 					as NetPromoterLevel,
    [Net Promoter Score]					as NetPromoterScore
Resident NPS_Score
where StartDate >= MakeDate(Year(AddYears(today(), -5)), 7, 1);


Store DataforScreen into [lib://TransformData (prdqs01_atobi)/Business KPIs Display/NPS_Display.qvd] (qvd);

drop table DataforScreen;

DataforHCS_NPS_Calcs:
NoConcatenate
Load
	Survey_id,
    [Survey Name]							as SurveyName,
    ResponseId,
    Interaction,
    StartDate,
    MonthYear,
    EndDate,
    "Provider/Program/Staff"				as Provider_Program_Staff,
    [Provider Type]							as ProviderType,
    ProviderNo,
    [Provider Group],
    [Provider Address]						as ProviderAddress,
    [Provider Suburb]						as ProviderSuburb,
    [Provider State]						as ProviderState,
    [Provider Postcode]						as ProviderPostcode,
    Product									as MembershipProduct,
    [Member Number]							as MembershipNumber,
    ClaimNo,
    Postcode								as MemberPostcode,
    State									as MemberState,
    Region									as MemberBranch,
    [Customer Satisfaction Level]			as CustomerSatisfactionLevel,
    [Customer Satisfaction Score]			as CustomerSatisfactionScore,
    [Customer Effort Level]					as CustomerEffortLevel,
    [Net Promoter Level] 					as NetPromoterLevel,
    [Net Promoter Score]					as NetPromoterScore,
    Feedback,
    [Feedback Improvements],
    [Program Type]
Resident NPS_Score
where StartDate >= MakeDate(Year(AddYears(today(), -5)), 7, 1);


//Store DataforHCS_NPS_Calcs into [lib://TransformData (prdqs01_atobi)/NPS_HCS_Data/Qualtrics_NPS_HCS_Data.qvd] (qvd);

drop table DataforHCS_NPS_Calcs;
*/
```

# Qualtrics Data Extract

Qlik load script for the "Qualtrics Data Extract" app.

```qlik
SET ThousandSep=',';
SET DecimalSep='.';
SET MoneyThousandSep=',';
SET MoneyDecimalSep='.';
SET MoneyFormat='$#,##0.00;-$#,##0.00';
SET TimeFormat='h:mm:ss TT';
SET DateFormat='DD/MM/YYYY';
SET TimestampFormat='DD/MM/YYYY h:mm:ss TT';
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

LET vQwcConnectionName	= 'lib://QlikWebConnector';
SET vQVDLocation		= 'lib://TransformData (prdqs01_atobi)/Qualtrics/';



// Set variable with a list of Surveys to Extract
//		SV_eXLP1SmIM6zjdXv	Customer Satisdfaction Survey 
//		SV_9GjRYiNTNKsuKkR	POC Survey 
//		SV_ehsRPAs5hPLId3n	90 Day NPS
//		SV_2o9xqMfmpVNZKp8	10 Day NPS - New member survey
//		SV_1Yx80MMG0nDHTAF	Health Services	
//		SV_2hm4kwhNudIHB2t	Mental Health Program
//		SV_6m5bFDluaJjxO8R	UPDATING Health and Wellbeing Program
//		SV_efX6mORlYWtebXg 	HCS NPS Questionnaire (Updated)

SET vSurveys			= 'SV_eXLP1SmIM6zjdXv','SV_9GjRYiNTNKsuKkR','SV_ehsRPAs5hPLId3n','SV_2o9xqMfmpVNZKp8','SV_1Yx80MMG0nDHTAF','SV_2hm4kwhNudIHB2t','SV_6m5bFDluaJjxO8R','SV_efX6mORlYWtebXg';

//*****************************************************************************************************
//*	Extract Qualtrics Surveys
//*
//*		Author:	Alex Graydon
//*		Date:	26/10/2021
//*
//*	HISTORY:
//*
//*		Date		Person			Description
//*		26/10/2021	Alex Graydon	Initial Version
//*
//*****************************************************************************************************
//Healthy Weight for Life

ProgramProviderId_Map:
MAPPING
LOAD * Inline [
Program,					provider_number_id
360 Med Care,				F200017B
Hospital Care at Home,		F300006H
Rehabilitation at Home,		F300006H
MindStep,					F300006H
HWFL,						G200010Y
];

ProgramProvider_Map:
MAPPING
LOAD * Inline [
provider_number_id,			provider
F200017B,					360 Med Care
F300006H,					Remedy at Home
G200010Y,					Prima Health Solutions Pty ltd
];
//LOAD provider_number_id,
//	 account_name
//FROM [lib://ExtractData (prdqs01_atobi)/Paragon_ProviderNumber.qvd] (qvd);


ProviderTypeDesc_Map:
MAPPING
LOAD provider_type,
     description
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_Provider_Type.qvd] (qvd);


ProviderIdType_Map:
MAPPING
LOAD provider_id,
	 ApplyMap('ProviderTypeDesc_Map',provider_type)	as Type
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_Provider.qvd] (qvd);


ProviderType_Map:
MAPPING
LOAD provider_number_id,
	 ApplyMap('ProviderIdType_Map',provider_id)		as Type
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_ProviderNumber.qvd] (qvd);


ProviderAddress_Map:
MAPPING
LOAD provider_number_id,
	 address_line1 & chr(13) & address_line2		as address
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_ProviderNumber.qvd] (qvd);


ProviderState_Map:
MAPPING
LOAD provider_number_id,
	 state
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_ProviderNumber.qvd] (qvd);


ProviderSuburb_Map:
MAPPING
LOAD provider_number_id,
	 suburb
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_ProviderNumber.qvd] (qvd);


ProviderPostcode_Map:
MAPPING
LOAD provider_number_id,
	 Num(postcode,'0000')							as postcode
FROM [lib://ExtractData (prdqs01_atobi)/Paragon_ProviderNumber.qvd] (qvd);


BranchLocations:
LOAD Location & ' Eye Care'							as Location,
     Street,
     Suburb,
     State,
     Num(Postcode,'0000')							as Postcode,
     [Provider Type] & ' Service Provider'			as ProviderType
FROM [lib://Manual Data (prdqs01_atobi)/Eye Care/BranchLocations.xlsx] (ooxml, embedded labels, table is Sheet1);

LOAD Location & ' Dental Centre'					as Location,
     Street,
     Suburb,
     State,
     Num(Postcode,'0000')							as Postcode,
     [Provider Type] & ' Service Provider'			as ProviderType
FROM [lib://Manual Data (prdqs01_atobi)/Dental/BranchLocations.xlsx] (ooxml, embedded labels, table is Sheet1);


BranchType_Map:
MAPPING
LOAD Location,
	 ProviderType
RESIDENT BranchLocations;

BranchAddress_Map:
MAPPING
LOAD Location,
	 Street
RESIDENT BranchLocations;

BranchState_Map:
MAPPING
LOAD Location,
	 State
RESIDENT BranchLocations;

BranchSuburb_Map:
MAPPING
LOAD Location,
	 Suburb
RESIDENT BranchLocations;

BranchPostcode_Map:
MAPPING
LOAD Location,
	 Postcode
RESIDENT BranchLocations;


DROP Table BranchLocations;

//*****************************************************************************************************
//*	Extract Qualtrics Surveys
//*
//*		Author:	Alex Graydon
//*		Date:	20/10/2021
//*
//*	HISTORY:
//*
//*		Date		Person			Description
//*		20/10/2021	Alex Graydon	Initial Version
//*		30/04/2024	Alex Graydon	Change to Builtin Qualtrics connector
//*
//*****************************************************************************************************

LIB CONNECT TO 'Qualtrics';


Qualtrics_Surveys:
LOAD id																as Survey_id,
     name															as Survey_name,
     ownerId														as Survey_ownerId,
     lastModified													as Survey_lastModified,
     Timestamp(timestamp#(lastModified, 'YYYY-MM-DD hh:mm:ss'))		as Survey_lastModified_timestamp,
     Date(date#(left(lastModified, 10), 'YYYY-MM-DD'))				as Survey_lastModified_date,
     Time(time#(mid(lastModified, 12, 8), 'hh:mm:ss'))				as Survey_lastModified_time,
     creationDate													as Survey_creationDate,
     Timestamp(timestamp#(creationDate, 'YYYY-MM-DD hh:mm:ss'))		as Survey_creationDate_timestamp,
     Date(date#(left(creationDate, 10), 'YYYY-MM-DD'))				as Survey_creationDate_date,
     Time(time#(mid(creationDate, 12, 8), 'hh:mm:ss'))				as Survey_creationDate_time,
     isActive														as Survey_isActive;

SELECT id,
	name,
	ownerId,
	lastModified,
	creationDate,
	isActive
FROM Surveys;

//FROM [$(vQwcConnectionName)]
//(URL IS [http://localhost:5555/data?connectorID=QualtricsConnector&table=Surveys&appID=], qvx);


Survey_MAP:
MAPPING
LOAD Survey_id,
     Survey_name
RESIDENT Qualtrics_Surveys;


STORE Qualtrics_Surveys into [$(vQVDLocation)Qualtrics_Surveys.qvd] (qvd);
DROP Table Qualtrics_Surveys;


//*****************************************************************************************************
//*	Extract Qualtrics Survey Questions
//*
//*
//*		Author:	Alex Graydon
//*		Date:	20/10/2021
//*
//*	HISTORY:
//*
//*		Date		Person			Description
//*		20/10/2021	Alex Graydon	Initial Version
//*		30/06/2026	Alex Graydon	Change to Builtin Qualtrics connector
//*
//*****************************************************************************************************

//LIB CONNECT TO 'QualtricsAPI_GET';
LIB CONNECT TO 'Qualtrics';


For Each vSurveyID IN $(vSurveys)

//     RestConnectorMasterTable:
//     SQL SELECT 
//         "__KEY_root",
//         (SELECT 
//             "__FK_result",
//             "__KEY_result",
//             (SELECT 
//                 "QuestionText",
//                 "DefaultChoices",
//                 "DataExportTag",
//                 "QuestionType",
//                 "Selector",
//                 "QuestionDescription",
//                 "QuestionID" AS "QuestionID_u5",
//                 "NextChoiceId",
//                 "NextAnswerId",
//                 "QuestionText_Unsafe",
//                 "SubSelector",
//                 "__KEY_elements",
//                 "__FK_elements"
//             FROM "elements" PK "__KEY_elements" FK "__FK_elements")
//         FROM "result" PK "__KEY_result" FK "__FK_result")
//     FROM JSON (wrap on) "root" PK "__KEY_root"
//     WITH CONNECTION (  
// 		URL "https://syd1.qualtrics.com/API/v3/survey-definitions/$(vSurveyID)/questions",
//         HTTPHEADER "X-API-TOKEN" "lyf0SLF0sEvAgCx6t94UskYsmiTBfWt7ADZ3dnwn"
//     );


// 	Qualtrics_Questions:
//     LOAD '$(vSurveyID)'											as Survey_id,
//           ApplyMap('Survey_MAP','$(vSurveyID)')					as [Survey Name],
//           QuestionID_u5											as QuestionID,
//           QuestionText,
//           DefaultChoices,
//           DataExportTag,
//           QuestionType,
//           Selector												as QuestionSelector,
//           QuestionDescription,
//           NextChoiceId											as QuestionNextChoiceId,
//           NextAnswerId											as QuestionNextAnswerId,
//           //QuestionText_Unsafe,
//           SubSelector											as QuestionSubSelector
//           //[__KEY_elements]
//           //[__FK_elements] AS [__KEY_result]
//     RESIDENT RestConnectorMasterTable
//     WHERE NOT IsNull([__FK_elements]);

// 	DROP TABLE RestConnectorMasterTable;

    Qualtrics_Questions:
    LOAD '$(vSurveyID)'											as Survey_id,
    	ApplyMap('Survey_MAP','$(vSurveyID)')					as [Survey Name],
        QuestionID,
        QuestionText;

    SELECT QuestionID,
        QuestionText
    FROM Questions
    WITH PROPERTIES (
    surveyId='$(vSurveyID)'
    );

Next

STORE Qualtrics_Questions into [$(vQVDLocation)Qualtrics_Questions.qvd] (qvd);
DROP Table Qualtrics_Questions;

//exit script;

//*****************************************************************************************************
//*	Extract Qualtrics Responses
//*
//*	For Customer Satisfaction Survey SV_eXLP1SmIM6zjdXv 
//* Manually match the Questions as follows
//*
//*		QID1 – Intro
//*		QID10 – Customer Satisfaction Score
//*		QID8 – Customer Effort Score
//*		QID2 – Net Promoter Score
//*		QID13 – Resolution Question 
//*		QID14 – Free text Love to Fix that
//*		QID3 – Free text Feedback
//*		QID9 – Marketing disclaimer agreement
//*
//*		Author:	Alex Graydon
//*		Date:	20/10/2021
//*
//*	HISTORY:
//*
//*		Date		Person			Description
//*		20/10/2021	Alex Graydon	Initial Version
//*		30/04/2024	Alex Graydon	Change to Builtin Qualtrics connector
//*
//*****************************************************************************************************

LIB CONNECT TO 'Qualtrics';


Qualtrics_CSAT:
LOAD 'SV_eXLP1SmIM6zjdXv'														as Survey_id,
	 ApplyMap('Survey_MAP','SV_eXLP1SmIM6zjdXv')								as [Survey Name],
	 _recordId																	as ResponseId,
     Date(date#(left(startDate, 10), 'YYYY-MM-DD'))								as StartDate,
     MonthName(date#(left(startDate, 10), 'YYYY-MM-DD'))						as MonthYear,
     Date(date#(left(endDate, 10), 'YYYY-MM-DD'))								as EndDate,
     status																		as Status,
     ipAddress																	as IPAddress,
     Interval(duration/86400)													as Duration,
     recipientFirstName & ' ' & recipientLastName								as Recipient,
     recipientEmail																as Email,
     externalDataReference														as ExternalReference,
     locationLatitude															as LocationLatitude,
     locationLongitude															as LocationLongitude,
     GeoMakePoint(locationLatitude,locationLongitude)							as Location,

// Question Responses   
     If(Len(Trim(QID10_NPS_GROUP))=0,Null(),QID10_NPS_GROUP)					as [Customer Satisfaction Level],
     If(Len(Trim(QID10))=0,Null(),QID10)										as [Customer Satisfaction Score],
     If(Len(Trim(QID8_NPS_GROUP))=0,Null(),QID8_NPS_GROUP)						as [Customer Effort Level],
     If(Len(Trim(QID8))=0,Null(),QID8)											as [Customer Effort Score],
     If(Len(Trim(QID2_NPS_GROUP))=0,Null(),QID2_NPS_GROUP)						as [Net Promoter Level],
     If(Len(Trim(QID2))=0,Null(),QID2)											as [Net Promoter Score],
	 QID13																		as [Resolved Today],
     QID14_TEXT																	as [Fix Support],
     QID3_TEXT																	as Feedback,
     If(Len(Trim(QID9))>0,QID9,'No')											as [Comments for Marketing],
     
// Additional Data
	 Pick(Match(SubField(Interaction,' ',-2),
     	'Eye','Dental','Care','Call','Contact'),
        'Eye Care','Dental','Care Centre','Contact Centre','Contact Centre')	as Interaction,
	 Interaction																as [Provider Group],
     If(Len(Trim(operator))>0,operator,CSRName)									as [Provider/Program/Staff],
     ApplyMap('BranchType_Map',Interaction,'Westfund')							as [Provider Type],
     ApplyMap('BranchAddress_Map',Interaction,Null())							as [Provider Address],
     ApplyMap('BranchSuburb_Map',Interaction,Null())							as [Provider Suburb],
     ApplyMap('BranchPostcode_Map',Interaction,Null())							as [Provider Postcode],
     ApplyMap('BranchState_Map',Interaction,Null())								as [Provider State],
     Age,
     ContactReason																as [Contact Reason],
     //operator																	as Operator,
     //CSRName																	as [CSR Name],
     If(Len(Trim([Hospital Product]))>0,
     	Trim([Hospital Product]),Trim(Extras))									as Product,
     Gender,
     MemberNumber																as [Member Number],
     MemberType																	as [Member Type],
     //No_of_contact_made_on_the_day											as Response_No_of_contact_made_on_the_day,
     Postcode,
     State,
     TenureMonths,
     Region;
     
SELECT startDate,
	endDate,
	status,
	ipAddress,
	progress,
	duration,
	finished,
	recordedDate,
	_recordId,
	recipientLastName,
	recipientFirstName,
	recipientEmail,
	externalDataReference,
	locationLatitude,
	locationLongitude,
	distributionChannel,
	userLanguage,
	QID10_NPS_GROUP,
	QID10,
	QID8_NPS_GROUP,
	QID8,
	QID2_NPS_GROUP,
	QID2,
	QID13,
	QID14_TEXT,
	QID3_TEXT,
	QID9,
	Age,
	ContactDate,
	ContactMethod,
	ContactReason,
	CSRName,
	Extras,
	Gender,
	[Hospital Product],
	MemberName,
	MemberNumber,
	MembershipCommencedDate,
	MemberType,
	No_of_contact_made_on_the_day,
	Postcode,
	State,
	TenureMonths,
	Region,
	Interaction,
	ManagerName,
	operator,
	ticket,
	Score,
	Q_TicketOwner,
	Age_DERIVEDqj2ptpo,
	Member_CEDz7vz5oz,
	Member_DERIVEDttnnovg,
	QID10_DERIVEDbb6a32o,
	QID3_TEXT_8dae439904cb40079cefe611ParTopics,
	QID3_TEXT_8dae439904cb40079cefe611SenPol,
	QID3_TEXT_8dae439904cb40079cefe611SenScore,
	QID3_TEXT_8dae439904cb40079cefe611Sentiment,
	QID3_TEXT_8dae439904cb40079cefe611Topic0,
	QID3_TEXT_8dae439904cb40079cefe611TopicSenLabel,
	QID3_TEXT_8dae439904cb40079cefe611TopicSenScore
FROM Responses
WITH PROPERTIES (
surveyId='SV_eXLP1SmIM6zjdXv',
csvHeaderRow='3',
recordedStartDate='',
recordedEndDate='',
useLabels='true',
maxResults=''
);

//FROM [$(vQwcConnectionName)]
//(URL IS [http://localhost:5555/data?connectorID=QualtricsConnector&table=Responses&surveyId=SV_eXLP1SmIM6zjdXv&csvHeaderRow=3&useLabels=True&appID=], qvx);


STORE Qualtrics_CSAT into [$(vQVDLocation)Qualtrics_CSAT.qvd] (qvd);
DROP Tables Qualtrics_CSAT;

//*****************************************************************************************************
//*	Extract Qualtrics Responses
//*
//*	For POC Survey SV_9GjRYiNTNKsuKkR 
//* Manually match the Questions as follows
//*
//*		QID1 – Intro
//*		QID2 – First Visit to Provider
//*		Q3 = QID3 – How did you hear about
//*		Q4 = QID4 – Satisfaction Score
//*		Q5 = QID5 – Other 
//*		Q6 = QID6 – Net Promoter Score
//*		Q7 = QID7 – Feedback
//*		Q8 = QID8 – Feedback
//*
//*		Author:	Alex Graydon
//*		Date:	22/10/2021
//*
//*	HISTORY:
//*
//*		Date		Person			Description
//*		22/10/2021	Alex Graydon	Initial Version
//*		30/04/2024	Alex Graydon	Change to Builtin Qualtrics connector
//*
//*****************************************************************************************************

LIB CONNECT TO 'Qualtrics';


Qualtrics_POC:
LOAD 'SV_9GjRYiNTNKsuKkR'														as Survey_id,
	 ApplyMap('Survey_MAP','SV_9GjRYiNTNKsuKkR')								as [Survey Name],
	 _recordId																	as ResponseId,
     Date(date#(left(startDate, 10), 'YYYY-MM-DD'))								as StartDate,
     MonthName(date#(left(startDate, 10), 'YYYY-MM-DD'))						as MonthYear,
     Date(date#(left(endDate, 10), 'YYYY-MM-DD'))								as EndDate,
     status																		as Status,
     ipAddress																	as IPAddress,
     Interval(duration/86400)													as Duration,
     recipientFirstName & ' ' & recipientLastName								as Recipient,
     recipientEmail																as Email,
     externalDataReference														as ExternalReference,
     locationLatitude															as LocationLatitude,
     locationLongitude															as LocationLongitude,
     GeoMakePoint(locationLatitude,locationLongitude)							as Location,

// Question Responses   
     QID2	 																	as [POC First Visit],
     QID3																		as [POC How did you hear about],
     QID5_TEXT																	as [POC How did you hear about Other],
     If(Len(Trim(QID4_NPS_GROUP))=0,Null(),QID4_NPS_GROUP)						as [Customer Satisfaction Level],
     If(Len(Trim(QID4))=0,Null(),QID4)											as [Customer Satisfaction Score],
     If(Len(Trim(QID6_NPS_GROUP))=0,Null(),QID6_NPS_GROUP)						as [Net Promoter Level],
     If(Len(Trim(QID6))=0,Null(),QID6)											as [Net Promoter Score],
     QID7_TEXT 																	as Feedback,
     
// Additional Data  
	 'Provider of Choice'														as Interaction,
     PracticeName																as [Provider Group],
     ProviderName																as [Provider/Program/Staff],
     ProviderNo,
     ApplyMap('ProviderType_Map',ProviderNo,Null())								as [Provider Type],
     ApplyMap('ProviderAddress_Map',ProviderNo,Null())							as [Provider Address],
     ApplyMap('ProviderSuburb_Map',ProviderNo,Null())							as [Provider Suburb],
     ApplyMap('ProviderPostcode_Map',ProviderNo,Null())							as [Provider Postcode],
     ApplyMap('ProviderState_Map',ProviderNo,Null())							as [Provider State],
     Agreement,
     ClaimNo,
     Operator,
     Membership_id																as [Member Number],
     Relationship,
     MemberType																	as [Member Type],
     Product,
     State,
     Postcode,
     Age,
     TenureMonths,
     Gender,
     Region;

SELECT startDate,
	endDate,
	status,
	ipAddress,
	progress,
	duration,
	finished,
	recordedDate,
	_recordId,
	recipientLastName,
	recipientFirstName,
	recipientEmail,
	externalDataReference,
	locationLatitude,
	locationLongitude,
	distributionChannel,
	userLanguage,
	QID2,
	QID3,
	QID5_TEXT,
	QID4_NPS_GROUP,
	QID4,
	QID6_NPS_GROUP,
	QID6,
	QID7_TEXT,
	PracticeName,
	ProviderName,
	ProviderNo,
	Agreement,
	ClaimNo,
	Membership_id,
	FirstName,
	LastName,
	Relationship,
	PrimaryEmail,
	Contact_date,
	[Enter Embedded Data Field Name Here...],
	MemberType,
	Product,
	State,
	Postcode,
	Operator,
	Age,
	Membership_Commenced_Date,
	TenureMonths,
	Gender,
	Region,
	Q_TicketOwner
FROM Responses
WITH PROPERTIES (
surveyId='SV_9GjRYiNTNKsuKkR',
csvHeaderRow='3',
recordedStartDate='',
recordedEndDate='',
useLabels='true',
maxResults=''
);


//FROM [$(vQwcConnectionName)]
//(URL IS [http://localhost:5555/data?connectorID=QualtricsConnector&table=Responses&surveyId=SV_9GjRYiNTNKsuKkR&csvHeaderRow=3&useLabels=True&appID=], qvx);


STORE Qualtrics_POC into [$(vQVDLocation)Qualtrics_POC.qvd] (qvd);
DROP Tables Qualtrics_POC;
//*****************************************************************************************************
//*	Extract Qualtrics Responses
//*
//*	For Health Services SV_1Yx80MMG0nDHTAF 
//* Manually match the Questions as follows
//*
//*		QID11 – Intro
//*		QID12 – Which Service
//*		QID3 – How did you hear
//*		QID2 – Net Promoter Score
//*		QID20 – Agree/Disagree Matrix 
//*		QID24 – Likely to choose
//*		QID9 – Free text Feedback
//*		QID18 – Free text Improvements
//*
//*	For Mental Health Program SV_2hm4kwhNudIHB2t 
//* Manually match the Questions as follows
//*
//*		QID11 – Intro
//*		QID22 – Which Service
//*		QID2 – Net Promoter Score
//*		QID20 – Agree/Disagree Matrix 
//*		QID21 – Free text Improvements
//*		QID13 – Did you achieve goals
//*		QID15 – Satisfaction Score
//*		QID18 - Effective tools for management
//*
//*		Author:	Alex Graydon
//*		Date:	26/10/2021
//*
//*	HISTORY:
//*
//*		Date		Person			Description
//*		26/10/2021	Alex Graydon	Initial Version
//*		30/04/2024	Alex Graydon	Change to Builtin Qualtrics connector
//*
//*****************************************************************************************************

LIB CONNECT TO 'Qualtrics';


Qualtrics_HealthServices:
LOAD *,
	 ApplyMap('ProgramProvider_Map',ProviderNo)									as [Provider Group],
	 ApplyMap('ProviderType_Map',ProviderNo,Null())								as [Provider Type],
     ApplyMap('ProviderAddress_Map',ProviderNo,Null())							as [Provider Address],
     ApplyMap('ProviderSuburb_Map',ProviderNo,Null())							as [Provider Suburb],
     ApplyMap('ProviderPostcode_Map',ProviderNo,Null())							as [Provider Postcode],
     ApplyMap('ProviderState_Map',ProviderNo,Null())							as [Provider State];

LOAD 'SV_1Yx80MMG0nDHTAF'														as Survey_id,
	 ApplyMap('Survey_MAP','SV_1Yx80MMG0nDHTAF')								as [Survey Name],
	 _recordId																	as ResponseId,
     Date(date#(left(startDate, 10), 'YYYY-MM-DD'))								as StartDate,
     MonthName(date#(left(startDate, 10), 'YYYY-MM-DD'))						as MonthYear,
     Date(date#(left(endDate, 10), 'YYYY-MM-DD'))								as EndDate,
     status																		as Status,
     ipAddress																	as IPAddress,
     Interval(duration/86400)													as Duration,
     recipientFirstName & ' ' & recipientLastName								as Recipient,
     recipientEmail																as Email,
     externalDataReference														as ExternalReference,
     locationLatitude															as LocationLatitude,
     locationLongitude															as LocationLongitude,
     GeoMakePoint(locationLatitude,locationLongitude)							as Location,

// Question Responses
	 //QID12,
     QID3																		as [How did you hear],
     QID3_6_TEXT																as [How did you hear Other],
     If(Len(Trim(QID2_NPS_GROUP))=0,Null(),QID2_NPS_GROUP)						as [Net Promoter Level],
     If(Len(Trim(QID2))=0,Null(),QID2)											as [Net Promoter Score],
     QID24																		as [Likely to choose],
     QID9_TEXT																	as Feedback,
     QID18_TEXT																	as [Feedback Improvements],
     
// Additional Data
	 'Health Services'															as Interaction,
     ApplyMap('ProgramProviderId_Map',QID12)									as ProviderNo,    
     QID12																		as [Provider/Program/Staff],
     Age,
     If(Len(Trim(HospitalProduct))>0,Trim(HospitalProduct),Trim(Extras))		as Product,
     Gender,
     MemberNumber																as [Member Number],
     MemberType																	as [Member Type],
     Postcode,
     State,
     TenureMonths,
     Region,
	 PreviousFund,
     Promotion;

SELECT startDate,
	endDate,
	status,
	ipAddress,
	progress,
	duration,
	finished,
	recordedDate,
	_recordId,
	recipientLastName,
	recipientFirstName,
	recipientEmail,
	externalDataReference,
	locationLatitude,
	locationLongitude,
	distributionChannel,
	userLanguage,
	QID12,
	QID3,
	QID3_6_TEXT,
	QID2_NPS_GROUP,
	QID2,
	QID20_14,
	QID20_1,
	QID20_3,
	QID20_4,
	QID20_23,
	QID24,
	QID9_TEXT,
	QID18_TEXT,
	Age,
	CoverType,
	Extras,
	Gender,
	HospitalProduct,
	MemberNumber,
	MembershipCommencedDate,
	MemberType,
	Postcode,
	PreviousFund,
	Promotion,
	Region,
	State,
	Survey,
	TenureMonths
FROM Responses
WITH PROPERTIES (
surveyId='SV_1Yx80MMG0nDHTAF',
csvHeaderRow='3',
recordedStartDate='',
recordedEndDate='',
useLabels='true',
maxResults=''
);

//FROM [$(vQwcConnectionName)]
//(URL IS [http://localhost:5555/data?connectorID=QualtricsConnector&table=Responses&surveyId=SV_1Yx80MMG0nDHTAF&csvHeaderRow=3&useLabels=True&appID=], qvx);



STORE Qualtrics_HealthServices into [$(vQVDLocation)Qualtrics_HealthServices.qvd] (qvd);
DROP Tables Qualtrics_HealthServices;
		
    //*****************************************************************************************************
//*	Extract Qualtrics Responses
//*
//*	For Mental Health Program SV_2hm4kwhNudIHB2t 
//* Manually match the Questions as follows
//*
//*		QID11 – Intro
//*		QID22 – Which Service
//*		QID2 – Net Promoter Score
//*		QID20 – Agree/Disagree Matrix 
//*		QID21 – Free text Improvements
//*		QID13 – Did you achieve goals
//*		QID15 – Satisfaction Score
//*		QID18 - Effective tools for management
//*
//*		Author:	Alex Graydon
//*		Date:	26/10/2021
//*
//*	HISTORY:
//*
//*		Date		Person			Description
//*		26/10/2021	Alex Graydon	Initial Version
//*		30/04/2024	Alex Graydon	Change to Builtin Qualtrics connector
//*
//*****************************************************************************************************

LIB CONNECT TO 'Qualtrics';


Qualtrics_MentalHealth:
LOAD *,
	 ApplyMap('ProgramProvider_Map',ProviderNo)									as [Provider Group],
	 ApplyMap('ProviderType_Map',ProviderNo,Null())								as [Provider Type],
     ApplyMap('ProviderAddress_Map',ProviderNo,Null())							as [Provider Address],
     ApplyMap('ProviderSuburb_Map',ProviderNo,Null())							as [Provider Suburb],
     ApplyMap('ProviderPostcode_Map',ProviderNo,Null())							as [Provider Postcode],
     ApplyMap('ProviderState_Map',ProviderNo,Null())							as [Provider State];
     
LOAD 'SV_2hm4kwhNudIHB2t'														as Survey_id,
	 ApplyMap('Survey_MAP','SV_2hm4kwhNudIHB2t')								as [Survey Name],
	 _recordId																	as ResponseId,
     Date(date#(left(startDate, 10), 'YYYY-MM-DD'))								as StartDate,
     MonthName(date#(left(startDate, 10), 'YYYY-MM-DD'))						as MonthYear,
     Date(date#(left(endDate, 10), 'YYYY-MM-DD'))								as EndDate,
     status																		as Status,
     ipAddress																	as IPAddress,
     Interval(duration/86400)													as Duration,
     recipientFirstName & ' ' & recipientLastName								as Recipient,
     recipientEmail																as Email,
     externalDataReference														as ExternalReference,
     locationLatitude															as LocationLatitude,
     locationLongitude															as LocationLongitude,
     GeoMakePoint(locationLatitude,locationLongitude)							as Location,

// Question Responses
	 //If(Len(Trim(QID22))=0,Survey,QID22),
     If(Len(Trim(QID2_NPS_GROUP))=0,Null(),QID2_NPS_GROUP)						as [Net Promoter Level],
     If(Len(Trim(QID2))=0,Null(),QID2)											as [Net Promoter Score],
     If(Len(Trim(QID15_NPS_GROUP))=0,Null(),QID15_NPS_GROUP)					as [Customer Satisfaction Level],
     If(Len(Trim(QID15))=0,Null(),QID15)										as [Customer Satisfaction Score],
     QID13																		as [Achieve Goals],
     QID18																		as [Effective Tools],
     QID21_TEXT																	as [Feedback Improvements],
     
// Additional Data
	 'Health Services'															as Interaction,
     ApplyMap('ProgramProviderId_Map',If(Len(Trim(QID22))=0,Survey,QID22))		as ProviderNo,    
     If(Len(Trim(QID22))=0,Survey,QID22)										as [Provider/Program/Staff],
     Age,
     If(Len(Trim(HospitalProduct))>0,Trim(HospitalProduct),Trim(Extras))		as Product,
     Gender,
     MemberNumber																as [Member Number],
     MemberType																	as [Member Type],
     Postcode,
     State,
     TenureMonths,
     Region,
	 PreviousFund,
     Promotion;
     
SELECT startDate,
	endDate,
	status,
	ipAddress,
	progress,
	duration,
	finished,
	recordedDate,
	_recordId,
	recipientLastName,
	recipientFirstName,
	recipientEmail,
	externalDataReference,
	locationLatitude,
	locationLongitude,
	distributionChannel,
	userLanguage,
	QID22,
	QID2_NPS_GROUP,
	QID2,
	QID20_15,
	QID20_1,
	QID20_3,
	QID20_2,
	QID20_4,
	QID20_14,
	QID21_TEXT,
	QID13,
	QID15_NPS_GROUP,
	QID15,
	QID18,
	Age,
	CoverType,
	Extras,
	Gender,
	HospitalProduct,
	MemberNumber,
	MembershipCommencedDate,
	MemberType,
	Postcode,
	PreviousFund,
	Promotion,
	Region,
	State,
	Survey,
	TenureMonths
FROM Responses
WITH PROPERTIES (
surveyId='SV_2hm4kwhNudIHB2t',
csvHeaderRow='3',
recordedStartDate='',
recordedEndDate='',
useLabels='true',
maxResults=''
);

//FROM [$(vQwcConnectionName)]
//(URL IS [http://localhost:5555/data?connectorID=QualtricsConnector&table=Responses&surveyId=SV_2hm4kwhNudIHB2t&csvHeaderRow=3&useLabels=True&appID=], qvx);


STORE Qualtrics_MentalHealth into [$(vQVDLocation)Qualtrics_MentalHealth.qvd] (qvd);
DROP Tables Qualtrics_MentalHealth;
		
    //*****************************************************************************************************
//*	Extract Qualtrics Responses
//*
//*	For Mental Health Program SV_2hm4kwhNudIHB2t 
//* Manually match the Questions as follows
//*
//*		QID11 – Intro
//*		QID21 – Which Service
//*		QID2 – Net Promoter Score
//*		QID4 – How quickly contacted 
//*		QID18 – Agree/Disagree Matrix 
//*		QID13 – Did you achieve goals
//*		QID15 - Effective tools for management		
//*		QID20 – Satisfaction Score
//*		QID6 – Free text Improvements
//*
//*		Author:	Alex Graydon
//*		Date:	26/10/2021
//*
//*	HISTORY:
//*
//*		Date		Person			Description
//*		26/10/2021	Alex Graydon	Initial Version
//*		30/04/2024	Alex Graydon	Change to Builtin Qualtrics connector
//*
//*****************************************************************************************************

LIB CONNECT TO 'Qualtrics';


Qualtrics_Wellbeing:
LOAD *,
	 ApplyMap('ProgramProvider_Map',ProviderNo)									as [Provider Group],
	 ApplyMap('ProviderType_Map',ProviderNo,Null())								as [Provider Type],
     ApplyMap('ProviderAddress_Map',ProviderNo,Null())							as [Provider Address],
     ApplyMap('ProviderSuburb_Map',ProviderNo,Null())							as [Provider Suburb],
     ApplyMap('ProviderPostcode_Map',ProviderNo,Null())							as [Provider Postcode],
     ApplyMap('ProviderState_Map',ProviderNo,Null())							as [Provider State];
     
LOAD 'SV_6m5bFDluaJjxO8R'														as Survey_id,
	 ApplyMap('Survey_MAP','SV_6m5bFDluaJjxO8R')								as [Survey Name],
	 _recordId																	as ResponseId,
     Date(date#(left(startDate, 10), 'YYYY-MM-DD'))								as StartDate,
     MonthName(date#(left(startDate, 10), 'YYYY-MM-DD'))						as MonthYear,
     Date(date#(left(endDate, 10), 'YYYY-MM-DD'))								as EndDate,
     status																		as Status,
     ipAddress																	as IPAddress,
     Interval(duration/86400)													as Duration,
     recipientFirstName & ' ' & recipientLastName								as Recipient,
     recipientEmail																as Email,
     externalDataReference														as ExternalReference,
     locationLatitude															as LocationLatitude,
     locationLongitude															as LocationLongitude,
     GeoMakePoint(locationLatitude,locationLongitude)							as Location,

// Question Responses
	 //If(Len(Trim(QID21))=0,Survey,QID21),
     If(Len(Trim(QID2_NPS_GROUP))=0,Null(),QID2_NPS_GROUP)						as [Net Promoter Level],
     If(Len(Trim(QID2))=0,Null(),QID2)											as [Net Promoter Score],
     If(Len(Trim(QID20_NPS_GROUP))=0,Null(),QID20_NPS_GROUP)					as [Customer Satisfaction Level],
     If(Len(Trim(QID20))=0,Null(),QID20)										as [Customer Satisfaction Score],
     QID4																		as [How Quickly Contacted],
     QID13																		as [Achieve Goals],
     QID15																		as [Effective Tools],
     QID6_TEXT																	as [Feedback Improvements],
     
// Additional Data
	 'Health Services'															as Interaction,
     ApplyMap('ProgramProviderId_Map',Survey)									as ProviderNo,    
     If(Survey='HWFL','Healthy Weight for Life',Survey)							as [Provider/Program/Staff],
     Age,
     If(Len(Trim(HospitalProduct))>0,Trim(HospitalProduct),Trim(Extras))		as Product,
     Gender,
     MemberNumber																as [Member Number],
     MemberType																	as [Member Type],
     Postcode,
     State,
     TenureMonths,
     Region,
	 PreviousFund,
     Promotion;

SELECT startDate,
	endDate,
	status,
	ipAddress,
	progress,
	duration,
	finished,
	recordedDate,
	_recordId,
	recipientLastName,
	recipientFirstName,
	recipientEmail,
	externalDataReference,
	locationLatitude,
	locationLongitude,
	distributionChannel,
	userLanguage,
	QID21,
	QID2_NPS_GROUP,
	QID2,
	QID4,
	QID18_15,
	QID18_1,
	QID18_3,
	QID18_2,
	QID18_4,
	QID18_14,
	QID13,
	QID15,
	QID20_NPS_GROUP,
	QID20,
	QID6_TEXT,
	Age,
	CoverType,
	Extras,
	Gender,
	HospitalProduct,
	MemberNumber,
	MembershipCommencedDate,
	MemberType,
	Postcode,
	PreviousFund,
	Promotion,
	Region,
	State,
	Survey,
	TenureMonths
FROM Responses
WITH PROPERTIES (
surveyId='SV_6m5bFDluaJjxO8R',
csvHeaderRow='3',
recordedStartDate='',
recordedEndDate='',
useLabels='true',
maxResults=''
);

//FROM [$(vQwcConnectionName)]
//(URL IS [http://localhost:5555/data?connectorID=QualtricsConnector&table=Responses&surveyId=SV_6m5bFDluaJjxO8R&csvHeaderRow=3&useLabels=True&appID=], qvx);


STORE Qualtrics_Wellbeing into [$(vQVDLocation)Qualtrics_Wellbeing.qvd] (qvd);
DROP Tables Qualtrics_Wellbeing;


    //*****************************************************************************************************
//*	Extract Qualtrics Responses
//*
//*	For HCS NPS Questionnaire SV_efX6mORlYWtebXg 
//* Manually match the Questions as follows
//*
//*		QID11 – Intro
//*		QID21 – Which Service
//*		QID2 - Net Promoter Score
//*		QID20 - Satisfaction Score
//*		QID6_TEXT – Free text Improvements
//*
//*		Author:	Monique Rust
//*		Date:	29/12/2025
//*
//*	HISTORY:
//*
//*		Date		Person			Description
//*		29/12/2025	Monique Rust	Initial Version
//*
//*****************************************************************************************************

LIB CONNECT TO 'Qualtrics';


Qualtrics_Wellbeing_V2:
LOAD *,
	 ApplyMap('ProgramProvider_Map',ProviderNo)									as [Provider Group],
	 ApplyMap('ProviderType_Map',ProviderNo,Null())								as [Provider Type],
     ApplyMap('ProviderAddress_Map',ProviderNo,Null())							as [Provider Address],
     ApplyMap('ProviderSuburb_Map',ProviderNo,Null())							as [Provider Suburb],
     ApplyMap('ProviderPostcode_Map',ProviderNo,Null())							as [Provider Postcode],
     ApplyMap('ProviderState_Map',ProviderNo,Null())							as [Provider State];
     
LOAD 'SV_efX6mORlYWtebXg'														as Survey_id,
	 ApplyMap('Survey_MAP','SV_efX6mORlYWtebXg')								as [Survey Name],
	 _recordId																	as ResponseId,
     Date(date#(left(startDate, 10), 'YYYY-MM-DD'))								as StartDate,
     MonthName(date#(left(startDate, 10), 'YYYY-MM-DD'))						as MonthYear,
     Date(date#(left(endDate, 10), 'YYYY-MM-DD'))								as EndDate,
     status																		as Status,
     ipAddress																	as IPAddress,
     Interval(duration/86400)													as Duration,
     recipientFirstName & ' ' & recipientLastName								as Recipient,
     recipientEmail																as Email,
     externalDataReference														as ExternalReference,
     locationLatitude															as LocationLatitude,
     locationLongitude															as LocationLongitude,
     GeoMakePoint(locationLatitude,locationLongitude)							as Location,

// Question Responses
	 If(Len(Trim(QID21))=0,Survey,QID21)										as [Program Type],
     If(Len(Trim(QID2_NPS_GROUP))=0,Null(),QID2_NPS_GROUP)						as [Net Promoter Level],
     If(Len(Trim(QID2))=0,Null(),QID2)											as [Net Promoter Score],
     If(Len(Trim(QID20_NPS_GROUP))=0,Null(),QID20_NPS_GROUP)					as [Customer Satisfaction Level],
     If(Len(Trim(QID20))=0,Null(),QID20)										as [Customer Satisfaction Score],
     QID6_TEXT																	as [Feedback Improvements],
     
// Additional Data
	 'Health Services'															as Interaction,
     ApplyMap('ProgramProviderId_Map',Survey)									as ProviderNo,    
     If(Survey='HWFL','Healthy Weight for Life',Survey)							as [Provider/Program/Staff],
     Age,
     If(Len(Trim(HospitalProduct))>0,Trim(HospitalProduct),Trim(Extras))		as Product,
     Gender,
     MemberNumber																as [Member Number],
     MemberType																	as [Member Type],
     Postcode,
     State,
     TenureMonths,
     Region,
	 PreviousFund,
     Promotion;

SELECT startDate,
	endDate,
	status,
	ipAddress,
	progress,
	duration,
	finished,
	recordedDate,
	_recordId,
	recipientLastName,
	recipientFirstName,
	recipientEmail,
	externalDataReference,
	locationLatitude,
	locationLongitude,
	distributionChannel,
	userLanguage,
    QID21,
	QID2_NPS_GROUP,
	QID2,
	QID20_NPS_GROUP,
	QID20,
	QID6_TEXT,
	Age,
	CoverType,
	Extras,
	Gender,
	HospitalProduct,
	MemberNumber,
	MembershipCommencedDate,
	MemberType,
	Postcode,
	PreviousFund,
	Promotion,
	Region,
	State,
	Survey,
	TenureMonths
FROM Responses
WITH PROPERTIES (
surveyId='SV_efX6mORlYWtebXg',
csvHeaderRow='3',
recordedStartDate='',
recordedEndDate='',
useLabels='true',
maxResults=''
);

//FROM [$(vQwcConnectionName)]
//(URL IS [http://localhost:5555/data?connectorID=QualtricsConnector&table=Responses&surveyId=SV_6m5bFDluaJjxO8R&csvHeaderRow=3&useLabels=True&appID=], qvx);


STORE Qualtrics_Wellbeing_V2 into [$(vQVDLocation)Qualtrics_Wellbeing_V2.qvd] (qvd);
DROP Tables Qualtrics_Wellbeing_V2;
//*****************************************************************************************************
//*	Create QualtricsSurveyData.csv, moved from Qualtrics NPS Score App
//*
//*
//*		Author:	Alex Graydon
//*		Date:	30/06/2026
//*
//*	HISTORY:
//*
//*		Date		Person			Description
//*		30/06/2026	Alex Graydon	Initial Version
//*
//*****************************************************************************************************

NPS_Score:
LOAD *
FROM [$(vQVDLocation)Qualtrics_CSAT.qvd] (qvd)
WHERE Len(Trim("Member Number"))>0;


CONCATENATE (NPS_Score)
LOAD *
FROM [$(vQVDLocation)Qualtrics_POC.qvd] (qvd)
WHERE Len(Trim("Member Number"))>0;


CONCATENATE (NPS_Score)
LOAD *
FROM [$(vQVDLocation)Qualtrics_HealthServices.qvd] (qvd)
WHERE Len(Trim("Member Number"))>0;


CONCATENATE (NPS_Score)
LOAD *
FROM [$(vQVDLocation)Qualtrics_MentalHealth.qvd] (qvd)
WHERE Len(Trim("Member Number"))>0;


CONCATENATE (NPS_Score)
LOAD *
FROM [$(vQVDLocation)Qualtrics_Wellbeing.qvd] (qvd)
WHERE Len(Trim("Member Number"))>0;


CONCATENATE (NPS_Score)
LOAD *
FROM [$(vQVDLocation)Qualtrics_Wellbeing_V2.qvd] (qvd)
WHERE Len(Trim("Member Number"))>0;


DataforBI:
LOAD Survey_id,
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
RESIDENT NPS_Score
WHERE StartDate >= MakeDate(Year(AddYears(today(), -5)), 7, 1)
AND [Survey Name] = 'Customer Satisfaction Survey'
AND match(Interaction, 'Eye Care', 'Dental');


CONCATENATE (DataforBI)
LOAD Survey_id,
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
RESIDENT NPS_Score
WHERE StartDate >= MakeDate(Year(AddYears(today(), -5)), 7, 1)
AND not match([Survey Name], 'Customer Satisfaction Survey');


STORE "DataforBI" INTO [lib://prdqs01_QlikData_Export_Files/InsightActuary/QualtricsSurveyData.csv] (txt);
DROP Table DataforBI;
//*****************************************************************************************************
//*	Create Qualtrics_NPS_HCS_Data.qvd, moved from Qualtrics NPS Score App
//*
//*
//*		Author:	Alex Graydon
//*		Date:	30/06/2026
//*
//*	HISTORY:
//*
//*		Date		Person			Description
//*		30/06/2026	Alex Graydon	Initial Version
//*
//*****************************************************************************************************

DataforScreen:
LOAD Survey_id,
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
RESIDENT NPS_Score
WHERE StartDate >= MakeDate(Year(AddYears(today(), -5)), 7, 1);


CONCATENATE (DataforScreen)
LOAD Survey_id,
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
RESIDENT NPS_Score
WHERE StartDate >= MakeDate(Year(AddYears(today(), -5)), 7, 1);


STORE DataforScreen into [lib://TransformData (prdqs01_atobi)/Business KPIs Display/NPS_Display.qvd] (qvd);
DROP Table DataforScreen;


DataforHCS_NPS_Calcs:
LOAD Survey_id,
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
RESIDENT NPS_Score
WHERE StartDate >= MakeDate(Year(AddYears(today(), -5)), 7, 1);


STORE DataforHCS_NPS_Calcs into [lib://TransformData (prdqs01_atobi)/NPS_HCS_Data/Qualtrics_NPS_HCS_Data.qvd] (qvd);
DROP Table DataforHCS_NPS_Calcs,NPS_Score;
Exit Script;
```

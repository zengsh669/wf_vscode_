USE SILVER;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Load_NPS_Score
AS
BEGIN
    SET NOCOUNT ON;

    TRUNCATE TABLE SILVER.dbo.NPS_Score;

    INSERT INTO SILVER.dbo.NPS_Score (
        Survey_Id, Survey_Name, Response_Id, Start_Date, Month_Year, End_Date,
        Status, IP_Address, Duration, Recipient, Email, External_Reference,
        Location_Latitude, Location_Longitude, Customer_Satisfaction_Level,
        Customer_Satisfaction_Score, Customer_Effort_Level, Customer_Effort_Score,
        Net_Promoter_Level, Net_Promoter_Score, Resolved_Today, Fix_Support,
        Feedback, Comments_For_Marketing, Interaction, Provider_Group,
        Provider_Program_Staff, Age, Contact_Reason, Product, Gender,
        Member_Number, Member_Type, Postcode, State, Tenure_Months, Region,
        POC_First_Visit, POC_How_Did_You_Hear_About, POC_How_Did_You_Hear_About_Other,
        Provider_No, Agreement, Claim_No, Operator, Relationship,
        How_Did_You_Hear, How_Did_You_Hear_Other, Likely_To_Choose,
        Feedback_Improvements, Previous_Fund, Promotion, Achieve_Goals,
        Effective_Tools, How_Quickly_Contacted, Program_Type
    )
    -- Qualtrics_CSAT
    SELECT
        Survey_id, [Survey Name], ResponseId, StartDate, MonthYear, EndDate,
        Status, IPAddress, Duration, Recipient, Email, ExternalReference,
        LocationLatitude, LocationLongitude, [Customer Satisfaction Level],
        [Customer Satisfaction Score], [Customer Effort Level], [Customer Effort Score],
        [Net Promoter Level], [Net Promoter Score], [Resolved Today], [Fix Support],
        Feedback, [Comments for Marketing], Interaction, [Provider Group],
        [Provider/Program/Staff], Age, [Contact Reason], Product, Gender,
        [Member Number], [Member Type], Postcode, State, TenureMonths, Region,
        NULL, NULL, NULL,
        NULL, NULL, NULL, NULL, NULL,
        NULL, NULL, NULL,
        NULL, NULL, NULL, NULL,
        NULL, NULL, NULL
    FROM BRONZE.qua.Qualtrics_CSAT
    WHERE LEN(LTRIM(RTRIM([Member Number]))) > 0

    UNION ALL

    -- Qualtrics_POC
    SELECT
        Survey_id, [Survey Name], ResponseId, StartDate, MonthYear, EndDate,
        Status, IPAddress, Duration, Recipient, Email, ExternalReference,
        LocationLatitude, LocationLongitude, [Customer Satisfaction Level],
        [Customer Satisfaction Score], NULL, NULL,
        [Net Promoter Level], [Net Promoter Score], NULL, NULL,
        Feedback, NULL, Interaction, [Provider Group],
        [Provider/Program/Staff], Age, NULL, Product, Gender,
        [Member Number], [Member Type], Postcode, State, TenureMonths, Region,
        [POC First Visit], [POC How did you hear about], [POC How did you hear about Other],
        ProviderNo, Agreement, ClaimNo, Operator, Relationship,
        NULL, NULL, NULL,
        NULL, NULL, NULL, NULL,
        NULL, NULL, NULL
    FROM BRONZE.qua.Qualtrics_POC
    WHERE LEN(LTRIM(RTRIM([Member Number]))) > 0

    UNION ALL

    -- Qualtrics_HealthServices
    SELECT
        Survey_id, [Survey Name], ResponseId, StartDate, MonthYear, EndDate,
        Status, IPAddress, Duration, Recipient, Email, ExternalReference,
        LocationLatitude, LocationLongitude, NULL, NULL, NULL, NULL,
        [Net Promoter Level], [Net Promoter Score], NULL, NULL,
        Feedback, NULL, Interaction, [Provider Group],
        [Provider/Program/Staff], Age, NULL, Product, Gender,
        [Member Number], [Member Type], Postcode, State, TenureMonths, Region,
        NULL, NULL, NULL,
        ProviderNo, NULL, NULL, NULL, NULL,
        [How did you hear], [How did you hear Other], [Likely to choose],
        [Feedback Improvements], PreviousFund, Promotion, NULL,
        NULL, NULL, NULL
    FROM BRONZE.qua.Qualtrics_HealthServices
    WHERE LEN(LTRIM(RTRIM([Member Number]))) > 0

    UNION ALL

    -- Qualtrics_MentalHealth
    SELECT
        Survey_id, [Survey Name], ResponseId, StartDate, MonthYear, EndDate,
        Status, IPAddress, Duration, Recipient, Email, ExternalReference,
        LocationLatitude, LocationLongitude, [Customer Satisfaction Level],
        [Customer Satisfaction Score], NULL, NULL,
        [Net Promoter Level], [Net Promoter Score], NULL, NULL,
        NULL, NULL, Interaction, [Provider Group],
        [Provider/Program/Staff], Age, NULL, Product, Gender,
        [Member Number], [Member Type], Postcode, State, TenureMonths, Region,
        NULL, NULL, NULL,
        ProviderNo, NULL, NULL, NULL, NULL,
        NULL, NULL, NULL,
        [Feedback Improvements], PreviousFund, Promotion, [Achieve Goals],
        [Effective Tools], NULL, NULL
    FROM BRONZE.qua.Qualtrics_MentalHealth
    WHERE LEN(LTRIM(RTRIM([Member Number]))) > 0

    UNION ALL

    -- Qualtrics_Wellbeing
    SELECT
        Survey_id, [Survey Name], ResponseId, StartDate, MonthYear, EndDate,
        Status, IPAddress, Duration, Recipient, Email, ExternalReference,
        LocationLatitude, LocationLongitude, [Customer Satisfaction Level],
        [Customer Satisfaction Score], NULL, NULL,
        [Net Promoter Level], [Net Promoter Score], NULL, NULL,
        NULL, NULL, Interaction, [Provider Group],
        [Provider/Program/Staff], Age, NULL, Product, Gender,
        [Member Number], [Member Type], Postcode, State, TenureMonths, Region,
        NULL, NULL, NULL,
        ProviderNo, NULL, NULL, NULL, NULL,
        NULL, NULL, NULL,
        [Feedback Improvements], PreviousFund, Promotion, [Achieve Goals],
        [Effective Tools], [How Quickly Contacted], NULL
    FROM BRONZE.qua.Qualtrics_Wellbeing
    WHERE LEN(LTRIM(RTRIM([Member Number]))) > 0

    UNION ALL

    -- Qualtrics_Wellbeing_V2
    SELECT
        Survey_id, [Survey Name], ResponseId, StartDate, MonthYear, EndDate,
        Status, IPAddress, Duration, Recipient, Email, ExternalReference,
        LocationLatitude, LocationLongitude, [Customer Satisfaction Level],
        [Customer Satisfaction Score], NULL, NULL,
        [Net Promoter Level], [Net Promoter Score], NULL, NULL,
        NULL, NULL, Interaction, [Provider Group],
        [Provider/Program/Staff], Age, NULL, Product, Gender,
        [Member Number], [Member Type], Postcode, State, TenureMonths, Region,
        NULL, NULL, NULL,
        ProviderNo, NULL, NULL, NULL, NULL,
        NULL, NULL, NULL,
        [Feedback Improvements], PreviousFund, Promotion, NULL,
        NULL, NULL, [Program Type]
    FROM BRONZE.qua.Qualtrics_Wellbeing_V2
    WHERE LEN(LTRIM(RTRIM([Member Number]))) > 0;

END;
GO

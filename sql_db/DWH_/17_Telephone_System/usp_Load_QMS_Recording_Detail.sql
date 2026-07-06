USE SILVER;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Load_QMS_Recording_Detail
AS
BEGIN
    TRUNCATE TABLE dbo.QMS_Recording_Detail;

    INSERT INTO dbo.QMS_Recording_Detail (
        User_ID,
        Agent_Name,
        Department_Name,
        Media_Type,
        Recording_ID,
        Start_Date,
        Start_Time,
        Stop_Date,
        Stop_Time,
        Duration
    )
    SELECT
        u.User_ID,
        u.First_Name + ' ' + u.Last_Name    AS Agent_Name,
        u.Department_Name,
        r.Media_Type,
        r.Recording_ID,
        r.Start_Date,
        r.Start_Time,
        r.Stop_Date,
        r.Stop_Time,
        r.Duration
    FROM [BRONZE].[qms].[Recording_Details] r
    JOIN [BRONZE].[qms].[User_Details] u
        ON r.User_ID = u.User_ID
    WHERE r.Stop_Date IS NOT NULL
      AND r.Media_Type IN (0, 4)
      AND r.Start_Date >= DATEADD(YEAR, -5, CAST(GETDATE() AS date));
END;

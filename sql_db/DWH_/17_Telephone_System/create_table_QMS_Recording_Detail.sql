USE SILVER;
GO

CREATE TABLE dbo.QMS_Recording_Detail (
    User_ID         uniqueidentifier    NOT NULL,
    Agent_Name      nvarchar(101)       NOT NULL,
    Department_Name nvarchar(255)           NULL,
    Media_Type      smallint            NOT NULL,
    Recording_ID    uniqueidentifier    NOT NULL,
    Start_Date      date                NOT NULL,
    Start_Time      time                NOT NULL,
    Stop_Date       date                NOT NULL,
    Stop_Time       time                NOT NULL,
    Duration        int                     NULL
);

-- ============================================================
-- create_table_RPA_Consolidated.sql
-- Creates the Silver target table for usp_Load_RPA_Consolidated.
-- Run this once before executing the SP for the first time.
--
-- Created:  9/6/2026
-- Author:   Zeng
-- ============================================================

USE SILVER;
GO

CREATE TABLE dbo.RPA_Consolidated (
    execution_id                NVARCHAR(MAX),
    process_time                DATETIME2,
    process_date_sydney         DATE,               -- pre-converted UTC → Sydney
    MonthYear                   VARCHAR(20),
    abbyTransactionID           NVARCHAR(MAX),
    timestampUsername           NVARCHAR(MAX),
    ClaimID                     NVARCHAR(MAX),
    ClaimKey                    VARCHAR(200),       -- stored explicitly; index-friendly for downstream JOINs
    MemberName                  NVARCHAR(MAX),
    lineID                      NVARCHAR(MAX),
    Provider_Number             NVARCHAR(MAX),
    Provider_Name               NVARCHAR(MAX),
    Description                 NVARCHAR(MAX),
    Net_Price                   NVARCHAR(MAX),
    Postcode                    NVARCHAR(MAX),
    Service_Date                NVARCHAR(MAX),
    Reject_Page                 NVARCHAR(MAX),
    Item_Number                 NVARCHAR(MAX),
    Line_Item_Number            NVARCHAR(MAX),
    Hippo_Service_Desc          NVARCHAR(MAX),
    Hippo_Service_Type          NVARCHAR(MAX),
    Source                      VARCHAR(50),
    -- HPC fields (NULL for RPA line rows, populated for ClaimInfo rows)
    Membership_ID_HPC           NVARCHAR(MAX),
    Reasons_HPC                 NVARCHAR(MAX),
    Reasons_Display             NVARCHAR(MAX),
    Sub_Reason                  NVARCHAR(MAX),
    Status_HPC                  NVARCHAR(MAX),
    ProcessStatus_HPC           NVARCHAR(MAX),
    Manual_Reviewer_Username    NVARCHAR(MAX),
    Send_To_Open_AI             NVARCHAR(MAX),
    Flag                        VARCHAR(10),
    -- HIPPO fields
    MaxClaimStatus_HIPPO        NVARCHAR(MAX),
    -- Fee schedule fields
    Red_Lower_Limit             NVARCHAR(MAX),
    Red_Upper_Limit             NVARCHAR(MAX),
    Blue_Lower_Limit            NVARCHAR(MAX),
    Blue_Upper_Limit            NVARCHAR(MAX)
);
GO

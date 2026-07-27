USE SILVER;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Load_Member_Comms_Detail
AS
BEGIN
    SET NOCOUNT ON;

    TRUNCATE TABLE SILVER.dbo.Member_Comms_Detail;

    WITH CommsBase AS (
        -- Qlik CommsDetail block 1: memship LEFT JOIN PersonContact LEFT JOIN memship_app
        SELECT
            m.membership_id,
            pc.first_name,
            pc.surname,
            pc.detailE,
            pc.detailM,
            ma.no_contact
        FROM BRONZE.dbo.memship AS m
        LEFT OUTER JOIN BRONZE.dbo.PersonContact AS pc
            ON m.membership_id = pc.membership_id
        LEFT OUTER JOIN BRONZE.dbo.memship_app AS ma
            ON pc.membership_id = ma.membership_id
        WHERE pc.relationship = '1'
    ),
    WebSecLatest AS (
        -- Qlik CommsDetail block 2: web_security INNER JOIN person_membership, latest record per person
        SELECT
            pm.membership_id,
            ws.postal_preference,
            ws.email_address,
            CASE WHEN ws.account_active IS NOT NULL THEN 'Yes' ELSE 'No' END AS App_Registered
        FROM BRONZE.dbo.web_security AS ws
        INNER JOIN BRONZE.dbo.person_membership AS pm
            ON ws.main_ref_id = pm.person_id
        WHERE ws.main_ref_type = 'P'
            AND ws.create_datetime = (
                SELECT MAX(w.create_datetime)
                FROM BRONZE.dbo.web_security AS w
                WHERE ws.main_ref_id = w.main_ref_id AND w.main_ref_type = 'P'
            )
            AND pm.relationship = '1'
    ),
    CommsDetail AS (
        -- Qlik `join (CommsDetail)` = INNER JOIN — members without a web_security record are dropped here
        SELECT
            cb.membership_id,
            cb.first_name,
            cb.surname,
            cb.detailM,
            cb.detailE,
            cb.no_contact,
            wsl.postal_preference,
            wsl.email_address,
            wsl.App_Registered
        FROM CommsBase AS cb
        INNER JOIN WebSecLatest AS wsl
            ON cb.membership_id = wsl.membership_id
    )
    INSERT INTO SILVER.dbo.Member_Comms_Detail (
        Membership_Id,
        First_Name,
        Surname,
        Detail_Mobile,
        Detail_Email,
        No_Contact,
        Postal_Preference,
        Email_Address,
        App_Registered,
        App_Reg_Flag,
        Email_Flag,
        Mobile_Flag,
        Postal_Pref_Final
    )
    SELECT
        membership_id,
        first_name,
        surname,
        detailM,
        detailE,
        no_contact,
        postal_preference,
        email_address,
        App_Registered,
        -- NOTE: Qlik source tests isnull([App Registered]) but App_Registered is always 'Yes'/'No' (never NULL),
        -- so this branch never triggers and App_Reg_Flag is effectively constant. Preserved as-is per source fidelity.
        CASE WHEN App_Registered IS NULL THEN 'No Not App Registered' ELSE 'App Registered' END,
        -- ISNULL(LEN(...), 0) replicates Qlik's len(NULL) = 0 behaviour (SQL Server's LEN(NULL) = NULL)
        CASE WHEN ISNULL(LEN(detailE), 0) < 3 THEN 'No Email' ELSE 'Email' END,
        CASE WHEN ISNULL(LEN(detailM), 0) < 3 THEN 'No Mobile' ELSE 'Mobile' END,
        CASE
            WHEN postal_preference = 'E' THEN 'Email'
            WHEN no_contact = 'Y' THEN 'Post'
            WHEN ISNULL(LEN(detailE), 0) < 3 THEN 'Post'
            ELSE 'Email'
        END
    FROM CommsDetail;

END;
GO

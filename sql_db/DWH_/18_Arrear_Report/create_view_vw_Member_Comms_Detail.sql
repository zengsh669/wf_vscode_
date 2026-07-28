USE GOLD;
GO

CREATE OR ALTER VIEW dbo.vw_Member_Comms_Detail
AS
-- Dedup: BRONZE.PersonContact can carry >1 relationship='1' row per membership_id
-- (e.g. a name-change leaving an old + new contact record — 2 members affected:
-- 133359, 100718). No create-date column exists to pick the "latest" row, so the
-- tiebreak prefers the row with a non-null Detail_Email (the more complete record).
SELECT
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
FROM (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY Membership_Id
            ORDER BY CASE WHEN Detail_Email IS NOT NULL THEN 0 ELSE 1 END
        ) AS rn
    FROM SILVER.dbo.Member_Comms_Detail
) AS deduped
WHERE rn = 1;
GO

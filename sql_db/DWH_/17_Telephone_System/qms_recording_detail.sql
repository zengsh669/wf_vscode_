-- QMS Recording Detail
-- Granularity: one row per call recording
-- Media_Type: 0 = Phone, 4 = Chat
SELECT
    u.User_ID,
    u.First_Name + ' ' + u.Last_Name           AS Agent_Name,
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
ORDER BY
    u.Department_Name,
    Agent_Name,
    r.Start_Date;

-- QMS Recording Daily Summary
-- Granularity: one row per agent per day per media type
-- Media_Type: 0 = Phone, 4 = Chat
SELECT
    u.User_ID,
    u.First_Name + ' ' + u.Last_Name           AS Agent_Name,
    u.Department_Name,
    r.Media_Type,
    r.Start_Date,

    COUNT(r.Recording_ID)                       AS Total_Calls,

    DATEDIFF(SECOND,
        MIN(CAST(CAST(r.Start_Date AS varchar) + ' ' + CAST(r.Start_Time AS varchar) AS datetime2)),
        MAX(CAST(CAST(r.Stop_Date AS varchar)  + ' ' + CAST(r.Stop_Time  AS varchar) AS datetime2))
    )                                           AS Total_Logged_In_Seconds,

    SUM(r.Duration)                             AS Total_Worktime_Seconds,

    DATEDIFF(SECOND,
        MIN(CAST(CAST(r.Start_Date AS varchar) + ' ' + CAST(r.Start_Time AS varchar) AS datetime2)),
        MAX(CAST(CAST(r.Stop_Date AS varchar)  + ' ' + CAST(r.Stop_Time  AS varchar) AS datetime2))
    ) - SUM(r.Duration)                         AS Total_Break_Seconds,

    AVG(r.Duration)                             AS Avg_Handle_Time_Seconds,

    AVG(r.Duration)                             AS Avg_Talk_Time_Seconds

FROM [BRONZE].[qms].[Recording_Details] r
JOIN [BRONZE].[qms].[User_Details] u
    ON r.User_ID = u.User_ID
WHERE r.Stop_Date IS NOT NULL
  AND r.Media_Type IN (0, 4)
GROUP BY
    u.User_ID,
    u.First_Name + ' ' + u.Last_Name,
    u.Department_Name,
    r.Media_Type,
    r.Start_Date
ORDER BY
    u.Department_Name,
    Agent_Name,
    r.Start_Date;

/*
 Script-to-Sale Conversion — FACT TABLE (draft, not business-approved)
 Grain: visit x purchase, each invoice attributed to exactly ONE visit (most
 recent attended visit on/before the sale date) to avoid double-counting.
*/

-- ============================================================================
-- VARIABLES — change these to switch views without editing the query body.
-- @ScriptFilter affects the fact table itself (filters which visits appear).
-- @DateWindowDays affects nothing until the METRICS section further down —
-- the fact table always carries every purchase regardless of how many days
-- after the visit it happened (see DaysAfterAppointment).
-- ============================================================================
DECLARE @DateWindowDays INT = 14;           -- 0 = same day, 7 = 1 week, 14 = 2 weeks
DECLARE @ScriptFilter   VARCHAR(20) = 'ALL';  -- 'ALL' | 'WITH_SCRIPT' | 'NO_SCRIPT'

IF OBJECT_ID('tempdb..#PurchaseDetail') IS NOT NULL DROP TABLE #PurchaseDetail;

-- Base population: attended appointments, joined to same-day exam and script status.
WITH AttendedAppointments AS (
    SELECT
        a.ID                AS AppointmentID,
        a.PATIENTID         AS PatientID,
        a.BRANCH_IDENTIFIER AS BranchIdentifier,
        a.USER_IDENTIFIER   AS OptometristIdentifier,
        a.STARTDATE         AS AppointmentDate
    FROM APPOINTMENT a
    WHERE a.APP_PROGRESS IN (2, 3, 4, 5, 10)  -- Attended: Waiting/Pre-test/Consulting/Complete/
                                       -- Dilating (business-confirmed, 2026-09-10 — via Optomate
                                       -- front end; 5=Complete alone under-counts patients whose
                                       -- status was never updated to Complete after arriving)
      AND a.IS_BREAK = 0              -- exclude break/blocked-out calendar entries
      AND a.PATIENTID > 0             -- exclude PATIENTID = -1/NULL (break/placeholder rows not
                                       -- fully caught by IS_BREAK — confirmed by colleague, 2026-09-10)
),
ExamForAppointment AS (
    -- Match each attended appointment to its exam on the same day for the same patient.
    -- (No direct FK from APPOINTMENT to EXAMINATION was found — join is by patient + date.)
    SELECT
        aa.AppointmentID,
        aa.PatientID,
        aa.BranchIdentifier,
        aa.OptometristIdentifier,
        aa.AppointmentDate,
        e.ID AS ExamID
    FROM AttendedAppointments aa
    LEFT JOIN EXAMINATION e
        ON e.PATIENT_ID = aa.PatientID
       AND CAST(e.EXAM_DATE AS DATE) = CAST(aa.AppointmentDate AS DATE)
       AND e.COMPLETED = 1
),
ScriptFlag AS (
    SELECT
        efa.*,
        CASE WHEN sr.ID IS NOT NULL OR cr.ID IS NOT NULL THEN 1 ELSE 0 END AS HasScript
    FROM ExamForAppointment efa
    LEFT JOIN SPECTACLE_RX sr ON sr.EXAM_ID = efa.ExamID
    LEFT JOIN CONTACT_RX   cr ON cr.EXAM_ID = efa.ExamID  -- contact lens scripts count too (business-confirmed, 2026-09-11)
),
VisitBase AS (
    SELECT *
    FROM ScriptFlag
    WHERE (@ScriptFilter = 'ALL')
       OR (@ScriptFilter = 'WITH_SCRIPT' AND HasScript = 1)
       OR (@ScriptFilter = 'NO_SCRIPT'   AND HasScript = 0)
),
-- Every genuine-sale invoice line that survives the exclusion rule (business,
-- 2026-09-10: ITEMCATEGORY.IS_CONSULTATION=1 or IDENTIFIER IN REPR/WOFF/~ACC).
QualifyingPurchaseLines AS (
    SELECT
        i.ID                AS InvoiceID,
        i.PATIENTID         AS PatientID,
        i.TYPE              AS InvoiceType,
        i.SALE_DATE         AS PurchaseDate,
        ii.ID               AS InvoiceItemID,
        ii.STOCK_TYPE,
        ii.DESCRIPTION      AS ProductName,
        ii.QTY,
        ii.UNITPRICE,
        ii.DISCOUNT_AMOUNT,
        ii.EXTENDED         AS LineAmount,
        cat.IDENTIFIER      AS ItemCategoryIdentifier,
        cat.NAME            AS ItemCategoryName
    FROM INVOICE i
    JOIN INVOICE_ITEMS ii
        ON ii.INVOICEID = i.ID
       AND (ii.CHARGETO IS NULL OR ii.CHARGETO COLLATE DATABASE_DEFAULT <> 'MEDICARE')  -- business-confirmed exclusion
       AND ii.STOCK_TYPE IN (2, 3, 4, 5, 7, 8, 9)   -- retail product lines (STOCK_TYPE=1 consultation fee always excluded)
       AND NOT EXISTS (
            SELECT 1
            FROM ITEMS itm
            JOIN ITEMCATEGORY cat2 ON cat2.IDENTIFIER = itm.CATEGORY_IDENTIFIER
            WHERE itm.ID = ii.STOCK_ID
              AND (cat2.IS_CONSULTATION = 1 OR cat2.IDENTIFIER IN ('REPR', 'WOFF', '~ACC', '~MIS'))
       )
    LEFT JOIN ITEMS itm2 ON itm2.ID = ii.STOCK_ID
    LEFT JOIN ITEMCATEGORY cat ON cat.IDENTIFIER = itm2.CATEGORY_IDENTIFIER
    WHERE i.TYPE IN (1, 2, 5, 6)                        -- genuine sale invoice types (TYPE 6 returns)
),
-- Attribute each purchase line to exactly ONE visit: the most recent attended
-- visit for that patient on or before the purchase date (no earlier cap).
-- A purchase with no such visit (predates the patient's first attended visit,
-- or the patient has none) gets NULL visit columns — a Walk-In Sale candidate.
AttributedPurchases AS (
    SELECT
        qpl.*,
        va.AppointmentID,
        va.PatientID        AS VisitPatientID,
        va.BranchIdentifier,
        va.OptometristIdentifier,
        va.AppointmentDate,
        va.ExamID,
        va.HasScript
    FROM QualifyingPurchaseLines qpl
    OUTER APPLY (
        -- Priority 1: most recent visit ON OR BEFORE the purchase date that HAS a
        -- script. Priority 2 (only if no priority-1 visit exists for this patient):
        -- most recent visit on or before the purchase date, script or not.
        -- "On or before the purchase date" is the non-negotiable precondition in
        -- both tiers — a later visit can never claim an earlier purchase.
        SELECT TOP 1 vb.*
        FROM VisitBase vb
        WHERE vb.PatientID = qpl.PatientID
          AND CAST(vb.AppointmentDate AS DATE) <= CAST(qpl.PurchaseDate AS DATE)
        ORDER BY
            CASE WHEN vb.HasScript = 1 THEN 0 ELSE 1 END,  -- scripted visits ranked first
            vb.AppointmentDate DESC
    ) va
)

-- Fact table: one row per attended visit x attributed purchase line, PLUS one
-- row per visit with no attributed purchase (purchase columns NULL), PLUS one
-- row per unattributed purchase / Walk-In Sale candidate (visit columns NULL).
SELECT
    vb.AppointmentID,
    vb.PatientID,
    vb.BranchIdentifier,
    vb.OptometristIdentifier,
    vb.AppointmentDate,
    vb.ExamID,
    vb.HasScript,
    @ScriptFilter                                  AS ScriptFilter,
    ap.InvoiceID,
    ap.InvoiceType,
    ap.PurchaseDate,
    DATEDIFF(DAY, vb.AppointmentDate, ap.PurchaseDate) AS DaysAfterAppointment,
    ap.InvoiceItemID,
    ap.STOCK_TYPE,
    CASE ap.STOCK_TYPE
        WHEN 2 THEN 'Spectacle Frame'
        WHEN 3 THEN 'Sunglasses Frame'
        WHEN 4 THEN 'Spectacle Lens'
        WHEN 5 THEN 'Contact Lens'
        WHEN 7 THEN 'Other (retail, non-excluded)'
        WHEN 8 THEN 'Lens Coating'
        WHEN 9 THEN 'Lens Tint'
        ELSE NULL
    END                                              AS StockTypeCategory,
    ap.ItemCategoryIdentifier,
    ap.ItemCategoryName,
    ap.ProductName,
    ap.QTY,
    ap.UNITPRICE,
    ap.DISCOUNT_AMOUNT,
    ap.LineAmount,
    CASE WHEN ap.InvoiceItemID IS NOT NULL THEN 1 ELSE 0 END AS IsPurchaseLine,
    CASE WHEN ap.InvoiceItemID IS NOT NULL THEN 1 ELSE 0 END AS Converted  -- purchase alone = converted; HasScript is a grouping dimension, not a precondition
INTO #PurchaseDetail
FROM AttributedPurchases ap
FULL OUTER JOIN VisitBase vb
    ON vb.AppointmentID = ap.AppointmentID;

-- Output the fact table.
SELECT *
FROM #PurchaseDetail
ORDER BY AppointmentDate DESC, AppointmentID, PurchaseDate;

-- ============================================================================
-- METRICS — rolled up from #PurchaseDetail, one row per AppointmentID first
-- (a visit can appear on multiple rows above if it matched several purchased
-- items, so roll up before counting or the visit/conversion counts will be
-- inflated). Walk-In Sale candidates (AppointmentID IS NULL) are excluded
-- from all three queries below, since they aren't attributed to any visit.
-- Converted here respects @DateWindowDays: a visit only counts as converted
-- if its attributed purchase fell within that many days of the visit
-- (DaysAfterAppointment BETWEEN 0 AND @DateWindowDays). Change @DateWindowDays
-- at the top of this script and re-run to see the rate for a different window.
-- ============================================================================
IF OBJECT_ID('tempdb..#VisitRollup') IS NOT NULL DROP TABLE #VisitRollup;

SELECT
    AppointmentID,
    BranchIdentifier,
    MAX(HasScript) AS HasScript,   -- same for every row of a given AppointmentID
    MAX(CASE WHEN Converted = 1
             AND DaysAfterAppointment BETWEEN 0 AND @DateWindowDays
             THEN 1 ELSE 0 END)   AS Converted
INTO #VisitRollup
FROM #PurchaseDetail
WHERE AppointmentID IS NOT NULL
GROUP BY AppointmentID, BranchIdentifier;

-- 1) Overall conversion rate.
SELECT
    COUNT(*)                                             AS Total_Attended_Visits,
    SUM(HasScript)                                        AS Visits_With_Script,
    SUM(Converted)                                        AS Converted_Visits,
    CAST(SUM(Converted) AS FLOAT) / NULLIF(COUNT(*), 0)   AS Conversion_Rate
FROM #VisitRollup;

-- 2) With-script vs. without-script comparison.
SELECT
    CASE WHEN HasScript = 1 THEN 'With Script' ELSE 'No Script' END AS ScriptStatus,
    COUNT(*)                                             AS Total_Visits,
    SUM(Converted)                                        AS Converted_Visits,
    CAST(SUM(Converted) AS FLOAT) / NULLIF(COUNT(*), 0)   AS Conversion_Rate
FROM #VisitRollup
GROUP BY CASE WHEN HasScript = 1 THEN 'With Script' ELSE 'No Script' END;

-- 3) By branch (location).
SELECT
    BranchIdentifier,
    COUNT(*)                                             AS Total_Attended_Visits,
    SUM(HasScript)                                        AS Visits_With_Script,
    SUM(Converted)                                        AS Converted_Visits,
    CAST(SUM(Converted) AS FLOAT) / NULLIF(COUNT(*), 0)   AS Conversion_Rate
FROM #VisitRollup
GROUP BY BranchIdentifier
ORDER BY BranchIdentifier;

DROP TABLE #PurchaseDetail;
DROP TABLE #VisitRollup;

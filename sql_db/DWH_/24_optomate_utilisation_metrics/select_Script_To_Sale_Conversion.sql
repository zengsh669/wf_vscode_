/*
 Script-to-Sale Conversion — FACT TABLE (draft, not business-approved)
 Grain: visit x every invoice on/after the visit date, no window cutoff —
 filter WHERE DaysAfterAppointment BETWEEN 0 AND DateWindowDays downstream.
 Do not COUNT(*)/SUM(Converted) here: an invoice can match 2+ visits for the
 same patient (attribution rule not yet business-confirmed — see DESIGN.md).
 Purchase matched by PATIENT + DATE, not EXAM_ID (unreliable — see DESIGN.md).
 Exclusion (Kathryn, 2026-09-10): a line is excluded if its ITEMCATEGORY has
 IS_CONSULTATION=1 or IDENTIFIER IN ('REPR','WOFF','~ACC'), resolved via
 STOCK_ID -> ITEMS -> ITEMCATEGORY (~52% coverage, verified safe — see DESIGN.md).
 Full rules and evidence: DESIGN.md.
*/

-- ============================================================================
-- VARIABLES — change these to switch views without editing the query body.
-- @DateWindowDays is not applied as a filter here (see note above) — it's
-- carried through as a column for use in a downstream conversion-rate query.
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
    WHERE a.APP_PROGRESS = 5          -- Attended (inferred, see header)
      AND a.IS_BREAK = 0              -- exclude break/blocked-out calendar entries
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
        CASE WHEN sr.ID IS NOT NULL THEN 1 ELSE 0 END AS HasScript
    FROM ExamForAppointment efa
    LEFT JOIN SPECTACLE_RX sr ON sr.EXAM_ID = efa.ExamID
),
VisitBase AS (
    SELECT *
    FROM ScriptFlag
    WHERE (@ScriptFilter = 'ALL')
       OR (@ScriptFilter = 'WITH_SCRIPT' AND HasScript = 1)
       OR (@ScriptFilter = 'NO_SCRIPT'   AND HasScript = 0)
)

-- Fact table: one row per attended visit x matched purchase line (business-confirmed
-- PATIENT + DATE WINDOW rule, not EXAM_ID — see header). A visit with no matching
-- purchase within the window still appears once, with all purchase columns NULL.
SELECT
    vb.AppointmentID,
    vb.PatientID,
    vb.BranchIdentifier,
    vb.OptometristIdentifier,
    vb.AppointmentDate,
    vb.ExamID,
    vb.HasScript,
    @ScriptFilter                                AS ScriptFilter,
    @DateWindowDays                              AS DateWindowDays,  -- reference value only, not applied as a filter — see header
    i.ID                                          AS InvoiceID,
    i.TYPE                                        AS InvoiceType,
    i.SALE_DATE                                   AS PurchaseDate,
    DATEDIFF(DAY, vb.AppointmentDate, i.SALE_DATE) AS DaysAfterAppointment,
    ii.ID                                          AS InvoiceItemID,
    ii.STOCK_TYPE,
    CASE ii.STOCK_TYPE
        WHEN 2 THEN 'Spectacle Frame'
        WHEN 3 THEN 'Sunglasses Frame'
        WHEN 4 THEN 'Spectacle Lens'
        WHEN 5 THEN 'Contact Lens'
        WHEN 7 THEN 'Other (retail, non-excluded)'
        WHEN 8 THEN 'Lens Coating'
        WHEN 9 THEN 'Lens Tint'
        ELSE NULL
    END                                            AS StockTypeCategory,
    cat.IDENTIFIER                                 AS ItemCategoryIdentifier,
    cat.NAME                                       AS ItemCategoryName,
    ii.DESCRIPTION                                 AS ProductName,
    ii.QTY,
    ii.UNITPRICE,
    ii.DISCOUNT_AMOUNT,
    ii.EXTENDED                                    AS LineAmount,
    CASE WHEN ii.ID IS NOT NULL THEN 1 ELSE 0 END  AS IsPurchaseLine,
    CASE WHEN vb.HasScript = 1 AND ii.ID IS NOT NULL THEN 1 ELSE 0 END AS Converted
INTO #PurchaseDetail
FROM VisitBase vb
LEFT JOIN INVOICE i
    ON i.PATIENTID = vb.PatientID
   AND CAST(i.SALE_DATE AS DATE) >= CAST(vb.AppointmentDate AS DATE)  -- no upper bound: apply a window downstream
   AND i.TYPE IN (1, 2, 5)                         -- genuine sale invoice types (exclude TYPE 6 returns)
LEFT JOIN INVOICE_ITEMS ii
    ON ii.INVOICEID = i.ID
   AND (ii.CHARGETO IS NULL OR ii.CHARGETO COLLATE DATABASE_DEFAULT <> 'MEDICARE')  -- business-confirmed exclusion (Kathryn)
   AND ii.STOCK_TYPE IN (2, 3, 4, 5, 7, 8, 9)       -- retail product lines (STOCK_TYPE=1 consultation fee always excluded)
   -- Resolve item category (see header for the join path and its coverage limits).
   -- No category match => treated as NOT excluded (verified safe, see header).
   AND NOT EXISTS (
        SELECT 1
        FROM ITEMS itm
        JOIN ITEMCATEGORY cat2 ON cat2.IDENTIFIER = itm.CATEGORY_IDENTIFIER
        WHERE itm.ID = ii.STOCK_ID
          AND (cat2.IS_CONSULTATION = 1 OR cat2.IDENTIFIER IN ('REPR', 'WOFF', '~ACC'))
   )
LEFT JOIN ITEMS itm2 ON itm2.ID = ii.STOCK_ID
LEFT JOIN ITEMCATEGORY cat ON cat.IDENTIFIER = itm2.CATEGORY_IDENTIFIER;

-- Output the fact table.
SELECT *
FROM #PurchaseDetail
ORDER BY AppointmentDate DESC, AppointmentID, PurchaseDate;

DROP TABLE #PurchaseDetail;

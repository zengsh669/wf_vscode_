/*
 Script-to-Sale Conversion — FACT TABLE (draft, not business-approved)
 Grain: one row per visit x every INVOICE that patient has ON OR AFTER the visit
 date (unmatched visit = 1 row, NULLs). This is a deliberate cross join of a
 patient's visits x their invoices — NO date-window cutoff is applied here.
 DaysAfterAppointment tells you how many days after the visit each invoice
 landed. @DateWindowDays is declared below but NOT used to filter this fact
 table — it's carried through as a column so a downstream query/pivot can
 filter WHERE DaysAfterAppointment BETWEEN 0 AND DateWindowDays without
 needing to know the value separately or re-run this script with a different
 constant.
 Do not COUNT(*) or naively SUM(Converted) here for a conversion rate — a
 patient with 2 visits can have the same invoice match both (see DESIGN.md /
 conversation history: this needs a business-confirmed rule for which visit
 an invoice should be attributed to before a rollup is calculated).
 Purchase matched by PATIENT + DATE, not EXAM_ID (unreliable — see DESIGN.md).
 @ScriptFilter below controls which visits (by script status) are included.
 STOCK_TYPE=7 exclusion list is a tentative placeholder pending business sign-off.
 Full rules, evidence and decode tables: DESIGN.md.
*/

-- ============================================================================
-- VARIABLES — change these to switch views without editing the query body.
-- @DateWindowDays is not applied as a filter here (see note above) — it's
-- carried through as a column for use in a downstream conversion-rate query.
-- ============================================================================
DECLARE @DateWindowDays INT = 14;           -- 0 = same day, 7 = 1 week, 14 = 2 weeks
DECLARE @ScriptFilter   VARCHAR(20) = 'ALL';  -- 'ALL' | 'WITH_SCRIPT' | 'NO_SCRIPT'

-- PLACEHOLDER: tentative STOCK_TYPE = 7 exclusion list — pending business confirmation.
-- Rows marked "likely exclude" in DESIGN.md's STOCK_TYPE=7 breakdown are included here.
-- Business may add/remove descriptions (e.g. dry-eye care products currently marked TBC).
IF OBJECT_ID('tempdb..#exclude_descriptions') IS NOT NULL DROP TABLE #exclude_descriptions;
CREATE TABLE #exclude_descriptions (DESCRIPTION NVARCHAR(200));
INSERT INTO #exclude_descriptions (DESCRIPTION) VALUES
    ('Eye Health Checks (inc. OCT, CT, RP &/or ODC)'),   -- exam-like, not retail
    ('Xailin Eye Drops 10mL'),                            -- drops
    ('Optimed Xailin Gel'),                               -- drops/gel
    ('Rohto Dry Eye Aid Drops'),                          -- drops
    ('Xailin Gel 10g tube'),                              -- drops/gel
    ('Manuka Eye Drops - 10ml'),                          -- drops
    ('Xailin Hydrate (10mL)'),                            -- drops
    ('Optimed Xailin Night'),                             -- drops/ointment
    ('Optimed Xailin Hydrate'),                           -- drops
    ('Xailin Gel (10g)'),                                 -- drops/gel
    ('Celluvisc Unit Dose (30 x 0.4ml)'),                 -- drops
    ('Write Off Non-Taxable Items'),                      -- financial adjustment
    ('Write Off Taxable Items'),                          -- financial adjustment
    ('Opening Balance (From NetOptic)');                  -- financial adjustment
-- NOT included above (tentatively treated as a genuine purchase/service — TBC with business):
--   Own Frame Fitting Fee, Own Frame, Replacement Part/Repair to Frame, Standard/Express Freight,
--   Optimed Blephadex* / Manuka* / Bruder* / D.E.R.M / Zocular / Avenova dry-eye care products,
--   Zeiss Lens Cleaning Wipes, Nylon Cord, General Accessory Item, Pocket Case, Nose Pads, etc.
--   See DESIGN.md for the full 41-row breakdown with tentative categories.

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
   AND (
         ii.STOCK_TYPE IN (2, 3, 4, 5, 8, 9)        -- unambiguous retail product lines
         OR (ii.STOCK_TYPE = 7
             AND ii.DESCRIPTION COLLATE DATABASE_DEFAULT NOT IN
                 (SELECT DESCRIPTION COLLATE DATABASE_DEFAULT FROM #exclude_descriptions))
       );

-- Output the fact table.
SELECT *
FROM #PurchaseDetail
ORDER BY AppointmentDate DESC, AppointmentID, PurchaseDate;

DROP TABLE #exclude_descriptions;
DROP TABLE #PurchaseDetail;

-- =============================================================================
-- select_Total_QUICKCHECK_TempTable.sql
-- *** ONE-OFF SCRIPT -- NOT the deliverable, NOT a faithful Total translation. ***
--
-- Same logic as select_Total_QUICKCHECK.sql, split into two parts run in the
-- SAME SSMS query window/session:
--   Part 1: materialise the "heavy" 21-BRONZE-table join chain (ClaimStatusMain
--           through WithStringFields) into a local temp table,
--           #WithStringFields.
--   Part 2: Stage 9 onward (Total table's 4 Concatenate branches, 4 self-joins,
--           AdditionalLogic derived flags) reads from #WithStringFields
--           instead of re-deriving it every time.
--
-- WHY THIS IS WORTH DOING HERE (different reason than the equivalent split for
-- select_Claims_QUICKCHECK.sql): Stage 9-10's self-join/derived-flag logic
-- has been the most bug-prone part of this file (VerifiedOperatorCheck,
-- [Final Operator], the 4 self-join keys all needed fixes across multiple
-- rounds). WithStringFields is only referenced ONCE downstream (a single
-- linear CTE chain, not several parallel subqueries), so this does NOT
-- meaningfully speed up a single full run -- the optimiser was already only
-- evaluating WithStringFields once. What it DOES speed up is ITERATING on
-- Stage 9-10 logic (e.g. adding the still-missing Claim Lines Processed
-- measure, or fixing a bug found later): rebuild #WithStringFields once
-- (the slow ~6-27 min part), then re-run just Part 2 in seconds each time you
-- tweak a self-join or derived flag, instead of re-running the full 21-table
-- join for every edit.
--
-- Uses a LOCAL TEMP TABLE (# prefix) because 'paragon' denied CREATE TABLE
-- permission (Msg 262) -- temp tables live in tempdb, which (almost) every
-- login can create objects in regardless of permissions on the user
-- databases, sidestepping that error entirely.
--
-- IMPORTANT: #WithStringFields only exists for the lifetime of THIS SSMS
-- query window/session. Run Part 1 once, then Part 2 as many times as you
-- like in the SAME window -- closing the window or losing the connection
-- clears it, and a different query window will not see it.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Part 1: materialise WithStringFields into #WithStringFields
-- ---------------------------------------------------------------------------

DECLARE @vStartDate DATE = DATEADD(MONTH, -13, DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1));
DECLARE @vToday DATE = CAST(GETDATE() AS DATE);

WITH

ClaimStatusMain AS (
    SELECT
        cs.claim_id                                                            AS [Claim ID],
        ISNULL(cst.description, 'MISSING')                                     AS Status,
        CAST(cs.status_date AS DATE)                                           AS [Date],
        CASE WHEN ISNULL(cst.description, 'MISSING') IN ('Manually Verified', 'Verified') THEN CAST(cs.status_date AS DATE) END AS [Verified Status Date],
        CASE WHEN ISNULL(cst.description, 'MISSING') IN ('Manually Verified', 'Verified') THEN 'Verified' END AS [Verified StatusCheck],
        ISNULL(CAST(c_mem.membership_id AS VARCHAR(20)), 'no member')          AS [Membership ID],
        CASE
            WHEN cs.update_operator LIKE '%-%' THEN 'ECLAIMS'
            ELSE cs.update_operator
        END                                                                    AS [update_operator],
        CASE WHEN ISNUMERIC(
                CASE
                    WHEN ISNULL(cst.description, 'MISSING') = 'Verified'
                        THEN cs.update_operator
                    ELSE cs.create_operator
                END) = 1
            THEN 'Web/Mobile Claim'
            ELSE
                CASE
                    WHEN ISNULL(cst.description, 'MISSING') = 'Verified'
                        THEN cs.update_operator
                    ELSE cs.create_operator
                END
        END                                                                    AS [Claim Operator],
        CAST(NULL AS CHAR(16))                                                 AS [Claim Line]
    FROM dbo.claim_status AS cs
    LEFT JOIN (
        SELECT DISTINCT claim_id, membership_id
        FROM dbo.claim
        WHERE create_datetime > @vStartDate
    ) AS c_mem
        ON c_mem.claim_id = cs.claim_id
    LEFT JOIN dbo.claim_status_type AS cst
        ON cst.claim_status_type = cs.claim_status_type
    WHERE cs.status_date > @vStartDate
),

ProviderClaimStatus AS (
    SELECT
        pcs.provider_claim_id                                                  AS [Claim ID],
        ISNULL(pcst.description, 'Missing')                                    AS Status,
        CAST(pcs.status_date AS DATE)                                          AS [Date],
        CASE WHEN ISNULL(pcst.description, 'MISSING') LIKE '%Sent to Medicare%' THEN CAST(pcs.status_date AS DATE) END AS [Verified Status Date],
        CAST(NULL AS VARCHAR(10))                                              AS [Verified StatusCheck],
        CAST(NULL AS VARCHAR(20))                                              AS [Membership ID],
        CASE
            WHEN pcs.update_operator LIKE '%-%' THEN 'ECLAIMS'
            ELSE pcs.update_operator
        END                                                                    AS [update_operator],
        CASE
            WHEN ISNULL(pcst.description, 'MISSING') = 'Verified'
                THEN pcs.update_operator
            ELSE pcs.create_operator
        END                                                                    AS [Claim Operator],
        CAST(NULL AS CHAR(16))                                                 AS [Claim Line]
    FROM dbo.provider_claim_status AS pcs
    LEFT JOIN dbo.provider_claim_status_type AS pcst
        ON pcst.provider_claim_status_type = pcs.provider_claim_status_type
    WHERE pcs.status_date > @vStartDate
),

ClaimsUnion AS (
    SELECT * FROM ClaimStatusMain
    UNION ALL
    SELECT * FROM ProviderClaimStatus
),

VerifiedClaims AS (
    SELECT
        cs.claim_id                                                            AS [Claim ID],
        ISNULL(CAST(c_mem.membership_id AS VARCHAR(20)), 'no member')          AS [Membership ID],
        ISNULL(cst.description, 'MISSING')                                     AS VerifiedStatus,
        CASE
            WHEN COALESCE(cs.update_operator, cs.create_operator) LIKE '%-%'
                THEN SUBSTRING(COALESCE(cs.update_operator, cs.create_operator), 1, CHARINDEX('-', COALESCE(cs.update_operator, cs.create_operator)) - 1)
            ELSE COALESCE(cs.update_operator, cs.create_operator)
        END                                                                    AS [Verified Operator],
        CASE WHEN ISNULL(cst.description, 'MISSING') IN ('Manually Verified', 'Verified') THEN CAST(cs.status_date AS DATE) END AS [Verified Status Date]
    FROM dbo.claim_status AS cs
    LEFT JOIN dbo.claim_status_type AS cst
        ON cst.claim_status_type = cs.claim_status_type
    LEFT JOIN (
        SELECT DISTINCT claim_id, membership_id
        FROM dbo.claim
        WHERE create_datetime > @vStartDate
    ) AS c_mem
        ON c_mem.claim_id = cs.claim_id
    WHERE cs.status_date > @vStartDate
      AND cs.claim_status_type = 'V'
),

AssessedClaims AS (
    SELECT
        cs.claim_id                                                            AS [Claim ID],
        ISNULL(CAST(c_mem.membership_id AS VARCHAR(20)), 'no member')          AS [Membership ID],
        ISNULL(cst.description, 'MISSING')                                     AS AssessedStatus,
        CASE
            WHEN cs.update_operator LIKE '%-%'
                THEN SUBSTRING(cs.update_operator, 1, CHARINDEX('-', cs.update_operator) - 1)
            ELSE cs.update_operator
        END                                                                    AS [Assessed Operator]
    FROM dbo.claim_status AS cs
    LEFT JOIN dbo.claim_status_type AS cst
        ON cst.claim_status_type = cs.claim_status_type
    LEFT JOIN (
        SELECT DISTINCT claim_id, membership_id
        FROM dbo.claim
        WHERE create_datetime > @vStartDate
    ) AS c_mem
        ON c_mem.claim_id = cs.claim_id
    WHERE cs.status_date > @vStartDate
      AND cs.claim_status_type = 'A'
),

ClaimsWithOperators AS (
    SELECT
        cu.*,
        vc.VerifiedStatus,
        vc.[Verified Operator],
        ac.AssessedStatus,
        ac.[Assessed Operator]
    FROM ClaimsUnion AS cu
    LEFT JOIN VerifiedClaims AS vc
        ON vc.[Claim ID] = cu.[Claim ID]
       AND vc.[Membership ID] = cu.[Membership ID]
       AND vc.[Verified Status Date] = cu.[Verified Status Date]
    LEFT JOIN AssessedClaims AS ac
        ON ac.[Claim ID] = cu.[Claim ID]
       AND ac.[Membership ID] = cu.[Membership ID]
),
ClaimsWithOperators2 AS (
    SELECT
        co.*,
        ISNULL(co.[Verified Operator], 'No Operator')                          AS VerifiedOperator,
        ISNULL(co.[Assessed Operator], 'No Operator')                          AS AssessedOperator,
        co.[update_operator]                                                   AS FinalOperatorLookupCode
    FROM ClaimsWithOperators AS co
),
ClaimsWithOperators3 AS (
    SELECT
        co2.*,
        CASE WHEN co2.VerifiedStatus = 'Verified'
             THEN CASE WHEN op_verified.oper_name IS NULL THEN NULL
                       ELSE CONCAT(op_verified.first_name, ' ', op_verified.surname) END
             ELSE 'No Operator' END                                            AS VerifiedOperatorCheck,
        CASE WHEN co2.Status IN ('Verified', 'Cancelled', 'Assessed but not Verified')
             THEN CASE WHEN op_final.oper_name IS NULL THEN NULL
                       ELSE CONCAT(op_final.first_name, ' ', op_final.surname) END
        END                                                                    AS [Final Operator]
    FROM ClaimsWithOperators2 AS co2
    LEFT JOIN dbo.operator AS op_verified
        ON op_verified.oper_name = co2.VerifiedOperator
    LEFT JOIN dbo.operator AS op_final
        ON op_final.oper_name = co2.FinalOperatorLookupCode
),

MaxStatusProvider AS (
    SELECT DISTINCT
        mg.provider_claim_id                                                   AS [Claim ID],
        pt.description                                                         AS MaxClaimStatusProvider
    FROM dbo.provider_claim_status AS mg
    JOIN dbo.provider_claim_status_type AS pt
        ON mg.provider_claim_status_type = pt.provider_claim_status_type
    WHERE mg.claim_status_version = (
            SELECT MAX(mg2.claim_status_version)
            FROM dbo.provider_claim_status AS mg2
            WHERE mg2.provider_claim_id = mg.provider_claim_id
              AND mg2.status_date <= GETDATE()
          )
      AND mg.status_date > @vStartDate
),

MaxStatusOther AS (
    SELECT DISTINCT
        mg.claim_id                                                            AS [Claim ID],
        pt.description                                                         AS MaxClaimStatusOther
    FROM dbo.claim_status AS mg
    JOIN dbo.claim_status_type AS pt
        ON mg.claim_status_type = pt.claim_status_type
    WHERE mg.claim_status_version = (
            SELECT MAX(mg2.claim_status_version)
            FROM dbo.claim_status AS mg2
            WHERE mg2.claim_id = mg.claim_id
              AND mg2.status_date <= GETDATE()
          )
      AND mg.status_date > @vStartDate
),

BringTogether AS (
    SELECT
        co3.*,
        ISNULL(msp.MaxClaimStatusProvider, mso.MaxClaimStatusOther)            AS MaxStatus
    FROM ClaimsWithOperators3 AS co3
    LEFT JOIN MaxStatusProvider AS msp
        ON msp.[Claim ID] = co3.[Claim ID]
    LEFT JOIN MaxStatusOther AS mso
        ON mso.[Claim ID] = co3.[Claim ID]
),

Adjustments AS (
    SELECT
        cd.claim_id                                                            AS [Claim ID],
        cd.claim_line_id                                                       AS [Claim Line],
        cd.adjustment_flag,
        cd.service_type                                                        AS [Service Type],
        cd.status_date                                                         AS [Adjusted Status Date],
        CASE WHEN op2.oper_name IS NULL THEN cd.update_operator
             ELSE CONCAT(op2.first_name, ' ', op2.surname) END                 AS [Adjusted Update Operator],
        CASE WHEN op1.oper_name IS NULL THEN cd.create_operator
             ELSE CONCAT(op1.first_name, ' ', op1.surname) END                 AS [Adj Create Operator]
    FROM dbo.ClaimDetailGenAndHosp AS cd
    INNER JOIN dbo.ClaimDetailsAtService AS cs
        ON cd.claim_id = cs.claim_id AND cd.claim_line_id = cs.claim_line_id
    LEFT JOIN dbo.operator AS op1
        ON op1.oper_name = cd.create_operator
    LEFT JOIN dbo.operator AS op2
        ON op2.oper_name = cd.update_operator
    WHERE cd.status_date > @vStartDate
),

ClaimsWithAdjustments AS (
    SELECT
        bt.*,
        adj.[Claim Line]                                                       AS [Adj Claim Line],
        adj.adjustment_flag,
        adj.[Service Type],
        adj.[Adjusted Update Operator],
        ISNULL(adj.[Adjusted Update Operator], adj.[Adj Create Operator])      AS [Adjusted Operator]
    FROM BringTogether AS bt
    LEFT JOIN Adjustments AS adj
        ON adj.[Claim ID] = bt.[Claim ID]
       AND adj.[Adjusted Status Date] > @vStartDate
),

WithStringFields AS (
    SELECT
        cwa.*,
        CONCAT(cwa.[Claim ID], cwa.[Adj Claim Line])                            AS [Claim ID/Line ID String]
    FROM ClaimsWithAdjustments AS cwa
)

SELECT DISTINCT *
INTO #WithStringFields
FROM WithStringFields;

-- ---------------------------------------------------------------------------
-- Part 2: Stage 9 onward, reading from #WithStringFields instead of
-- re-deriving it. Same logic/filters as select_Total_QUICKCHECK.sql -- only
-- `FROM WithStringFields` swapped for `FROM #WithStringFields`. Re-run just
-- this part (without Part 1) whenever iterating on Stage 9-10 logic.
-- ---------------------------------------------------------------------------

WITH

TotalProcessed AS (
    SELECT DISTINCT
        [Claim ID]                                                             AS ClaimID,
        [Claim ID/Line ID String]                                              AS [Claim&LineID],
        [Service Type]                                                         AS ServiceType,
        [Final Operator]                                                       AS Op,
        'Claims Processed'                                                     AS Type,
        [Date]                                                                 AS [Count Date],
        CONCAT([Claim ID], '-', [Final Operator])                              AS ClaimKey
    FROM #WithStringFields
    WHERE Status IN ('Assessed but not Verified', 'Batched for Medicare (Batch Created)')
),

TotalVerified AS (
    SELECT DISTINCT
        [Claim ID]                                                             AS ClaimID,
        [Claim ID/Line ID String]                                              AS [Claim&LineID],
        [Service Type]                                                         AS ServiceType,
        VerifiedOperatorCheck                                                  AS Op,
        'Claims Verified'                                                      AS Type,
        [Date]                                                                 AS [Count Date],
        CONCAT([Claim ID], '-', VerifiedOperatorCheck)                         AS ClaimKey
    FROM #WithStringFields
    WHERE [Verified StatusCheck] = 'Verified'
),

TotalAdjusted AS (
    SELECT DISTINCT
        [Claim ID]                                                             AS ClaimID,
        [Claim ID/Line ID String]                                              AS [Claim&LineID],
        [Service Type]                                                         AS ServiceType,
        [Adjusted Update Operator]                                             AS Op,
        'Adjusted/Balanced Claims'                                             AS Type,
        [Date]                                                                 AS [Count Date],
        CONCAT([Claim ID], '-', [Adjusted Update Operator])                    AS ClaimKey
    FROM #WithStringFields
    WHERE adjustment_flag IN ('New Line', 'Reversal Line', 'Original Line')
),

TotalCancelled AS (
    SELECT DISTINCT
        [Claim ID]                                                             AS ClaimID,
        [Claim ID/Line ID String]                                              AS [Claim&LineID],
        [Service Type]                                                         AS ServiceType,
        [Final Operator]                                                       AS Op,
        'Cancelled Claims'                                                     AS Type,
        [Date]                                                                 AS [Count Date],
        CONCAT([Claim ID], '-', [Final Operator])                              AS ClaimKey
    FROM #WithStringFields
    WHERE MaxStatus LIKE '%Cancelled%'
),

TotalAll AS (
    SELECT ClaimID, [Claim&LineID], ServiceType, Op, Type, [Count Date], ClaimKey FROM TotalProcessed
    UNION ALL
    SELECT ClaimID, [Claim&LineID], ServiceType, Op, Type, [Count Date], ClaimKey FROM TotalVerified
    UNION ALL
    SELECT ClaimID, [Claim&LineID], ServiceType, Op, Type, [Count Date], ClaimKey FROM TotalAdjusted
    UNION ALL
    SELECT ClaimID, [Claim&LineID], ServiceType, Op, Type, [Count Date], ClaimKey FROM TotalCancelled
),

VerifiedLookup AS (
    SELECT ClaimID, [Claim&LineID], Op, [Count Date], [Count Date] AS VerifiedDATE, Op AS VerifiedOp
    FROM TotalAll WHERE Type = 'Claims Verified'
),
ProcessedLookup AS (
    SELECT ClaimID, [Claim&LineID], Op, [Count Date] AS ProcessedDATE, Op AS ProcessedOp
    FROM TotalAll WHERE Type = 'Claims Processed'
),
AdjustedLookup AS (
    SELECT DISTINCT ClaimID, Op, [Count Date], [Count Date] AS AdjustedDATE, Op AS AdjustedOp
    FROM TotalAll WHERE Type = 'Adjusted/Balanced Claims'
),
ProcessedLookup2 AS (
    SELECT ClaimID, Op AS ProcessedOpCheck2
    FROM TotalAll WHERE Type = 'Claims Processed'
),

TotalWithLookups AS (
    SELECT
        ta.*,
        vl.VerifiedDATE, vl.VerifiedOp,
        pl.ProcessedDATE, pl.ProcessedOp,
        al.AdjustedDATE, al.AdjustedOp,
        pl2.ProcessedOpCheck2
    FROM TotalAll AS ta
    LEFT JOIN VerifiedLookup AS vl
        ON vl.ClaimID = ta.ClaimID
       AND vl.[Claim&LineID] = ta.[Claim&LineID]
       AND vl.Op = ta.Op
       AND vl.[Count Date] = ta.[Count Date]
    LEFT JOIN ProcessedLookup AS pl
        ON pl.ClaimID = ta.ClaimID
       AND pl.[Claim&LineID] = ta.[Claim&LineID]
       AND pl.Op = ta.Op
    LEFT JOIN AdjustedLookup AS al
        ON al.ClaimID = ta.ClaimID
       AND al.Op = ta.Op
       AND al.[Count Date] = ta.[Count Date]
    LEFT JOIN ProcessedLookup2 AS pl2
        ON pl2.ClaimID = ta.ClaimID
),

Final AS (
    SELECT
        twl.*,
        CASE WHEN twl.[Op] = twl.VerifiedOp AND twl.ProcessedOp IS NULL AND twl.ProcessedOpCheck2 IS NULL THEN 'Processed'
             ELSE 'Verified' END                                               AS ProcessedCheck,
        CASE WHEN twl.[Op] = twl.VerifiedOp AND twl.ProcessedOp IS NULL
                  AND twl.ProcessedOpCheck2 IN ('HICAPS', 'ECLIPSE', 'IBA', 'System Account')
             THEN 'Processed' ELSE 'Verified' END                              AS ProcessedCheck3,
        CASE WHEN twl.AdjustedDATE = twl.VerifiedDATE AND twl.VerifiedOp = twl.AdjustedOp THEN 'Adjusted Only'
             ELSE 'Verified' END                                               AS AdjustedOnlyCheck,
        CASE WHEN twl.VerifiedDATE = twl.ProcessedDATE AND twl.VerifiedOp = twl.ProcessedOp THEN 'Processed Only'
             ELSE 'Verified' END                                               AS ProcessedVerifiedCheck
    FROM TotalWithLookups AS twl
),
Final2 AS (
    SELECT
        f.*,
        CASE WHEN f.Type = 'Claims Processed' OR f.ProcessedCheck = 'Processed' OR f.ProcessedCheck3 = 'Processed'
             THEN 'Processed' ELSE 'Other' END                                 AS ProcessedCheck2
    FROM Final AS f
),
Final3 AS (
    SELECT
        f2.*,
        CASE WHEN f2.ProcessedCheck = 'Verified' AND f2.Type = 'Claims Verified'
             THEN 'Verified' ELSE 'Processed' END                              AS VerifiedOnlyCheck
    FROM Final2 AS f2
)

SELECT
    Op                                                                         AS Operator,
    ClaimID,
    ServiceType,
    ClaimKey,
    [Count Date],
    Type,
    ProcessedCheck2,
    VerifiedOnlyCheck,
    ProcessedVerifiedCheck,
    AdjustedOnlyCheck
FROM Final3;

-- Not dropping #WithStringFields here on purpose -- it disappears
-- automatically when this session/window ends. If you want to rebuild it
-- mid-session, run DROP TABLE #WithStringFields; first, then re-run Part 1.

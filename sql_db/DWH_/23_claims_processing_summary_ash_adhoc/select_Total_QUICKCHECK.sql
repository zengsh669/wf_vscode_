-- =============================================================================
-- select_Total_QUICKCHECK.sql
-- *** VALIDATION-ONLY SCRIPT -- NOT the deliverable, NOT a faithful Total translation. ***
--
-- Purpose: sanity-check the Qlik "Total" table logic (claims_processing.md lines
-- 647-771) against the left-side Operator summary table on the Qlik "Summary"
-- dashboard sheet -- the pivot with Row dimensions Operator/ClaimID/ServiceType/
-- ClaimKey and Measures Processed Claims / Verified Claims / Adjusted-Balanced
-- Claims / Cancelled Claims / Total / Avg No. Claims Processed Per Day /
-- Claim Lines Processed.
--
-- This is a FIRST PASS: only the aggregate "Totals" row is computed (no GROUP BY
-- Operator yet). Once these totals match the dashboard's "Totals" row, add
-- GROUP BY [Op] to break out by Operator and compare against the per-row values.
--
-- Only 6 of the 7 dashboard measures are covered here (Claim Lines Processed's
-- exact Set Analysis expression has not yet been confirmed/supplied -- add once
-- available):
--   Processed Claims, Verified Claims, Adjusted/Balanced Claims, Cancelled Claims,
--   Total, Avg No. Claims Processed Per Day
--
-- Source measures (confirmed from the Qlik app, Edit measure -- 2026-09-08):
--   Processed Claims   = Count({<[ProcessedCheck2]={"*Processed*"},[VerifiedOnlyCheck]=-{'Verified'}>}distinct ClaimKey)
--   Verified Claims    = Count({<Type={"*Verified*"},[ProcessedCheck2]=-{"*Processed*"},[ProcessedVerifiedCheck]={'Verified'},AdjustedOnlyCheck=-{'Adjusted Only'}>}distinct ClaimKey)
--   Adjusted/Balanced  = Count({<Type={"Adjusted*"}>}distinct ClaimKey)
--   Cancelled Claims   = Count({<Type={"*Cancelled*"}>}distinct ClaimKey)
--   Total              = sum of the above 4
--   Avg Claims/Day     = Processed Claims (numerator) / Count(distinct [Count Date]) under the same filter
--
-- Trimmed relative to select_Claims.sql -- this script only builds the fields the
-- Qlik `Total:` block (lines 647-771) actually reads from `Claims`:
--   [Claim ID], [Claim ID/Line ID String], [Service Type], [Final Operator], Status,
--   [Date], [VerifiedOperatorCheck], [Adjusted Update Operator], adjustment_flag,
--   MaxStatus, [Manual Claim] (Manual Claims branch not yet included below -- add if
--   the dashboard measures need it; none of the 6 measures above reference it).
-- Dropped entirely (not read by Total): Till/Attachment/ClaimChannel/Person/Product/
-- Agent/Branch/Audit/cohort-band logic.
--
-- Do NOT hand this to Hippo. Do NOT treat as authoritative beyond "do these 6
-- aggregate numbers look right" -- if select_Total.sql is built later as a real
-- deliverable, it should be reviewed with the same rigour as select_Claims.sql.
-- =============================================================================

DECLARE @vStartDate DATE = DATEADD(MONTH, -13, DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1));
DECLARE @vToday DATE = CAST(GETDATE() AS DATE);

WITH

-- ---------------------------------------------------------------------------
-- Stage 1-3: Claims union (same as select_Claims_QUICKCHECK.sql Stage 1-3)
-- ---------------------------------------------------------------------------
ClaimStatusMain AS (
    SELECT
        cs.claim_id                                                            AS [Claim ID],
        ISNULL(cst.description, 'MISSING')                                     AS Status,
        CAST(cs.status_date AS DATE)                                           AS [Date],
        CASE WHEN ISNULL(cst.description, 'MISSING') IN ('Manually Verified', 'Verified') THEN CAST(cs.status_date AS DATE) END AS [Verified Status Date],
        -- Qlik line 221: [Verified StatusCheck] -- ONLY defined on the main claim_status
        -- branch. The Concatenate'd provider_claim_status branch (lines 236-255) has no such
        -- field, so Qlik leaves it NULL there -- meaning provider-sourced claims can NEVER
        -- match WildMatch([Verified StatusCheck],'Verified') (line 669), even though the
        -- provider branch's OWN [Verified Status Date] (line 249, 'Sent to Medicare' trigger)
        -- can be non-NULL. [Verified Status Date] and [Verified StatusCheck] are NOT
        -- interchangeable across the two branches -- only on the main branch are they the
        -- same condition. See ProviderClaimStatus below for the NULL counterpart.
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
        -- Qlik: the provider_claim_status Concatenate LOAD (lines 236-255) has no
        -- [Verified StatusCheck] field -- always NULL on this branch (see ClaimStatusMain).
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

-- ---------------------------------------------------------------------------
-- Stage 4-5: Verified/Assessed left-joins + OperatorCheck chain
-- (same logic as select_Claims.sql Stages 4-5, trimmed to needed columns)
-- ---------------------------------------------------------------------------
VerifiedClaims AS (
    SELECT
        cs.claim_id                                                            AS [Claim ID],
        ISNULL(CAST(c_mem.membership_id AS VARCHAR(20)), 'no member')          AS [Membership ID],
        ISNULL(cst.description, 'MISSING')                                     AS VerifiedStatus,
        -- Qlik lines 272-277: the Verified LOAD's SQL SELECT pre-processes update_operator
        -- with COALESCE(update_operator, create_operator), then truncates at the first '-'
        -- (NOT a simple 'ECLAIMS' replacement, unlike the main/provider branches' pattern).
        -- Copied verbatim from select_Claims.sql's already-verified VerifiedClaims CTE.
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
        -- Qlik line 294: truncates update_operator at the first '-' (no COALESCE with
        -- create_operator here, unlike VerifiedClaims). Copied from select_Claims.sql.
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
        -- Qlik line 327 len(x>0) always-true bug -- see select_Claims.sql FinalOperatorLookupCode.
        co.[update_operator]                                                   AS FinalOperatorLookupCode
    FROM ClaimsWithOperators AS co
),
ClaimsWithOperators3 AS (
    -- Qlik lines 327/329: applymap('OperatorMap', X) is a 2-arg ApplyMap call in both
    -- [Final Operator] and [VerifiedOperatorCheck] -- no default supplied, so a lookup value
    -- not found in OperatorMap (dbo.operator) resolves to NULL, not the raw lookup value.
    -- Same bug class found and fixed in select_Claims_QUICKCHECK.sql's ClaimsWithOperators3
    -- on 2026-09-09 -- this CTE had the identical mistake, found on a separate re-check of
    -- this file (built independently, never had the fix applied).
    -- NOTE: CONCAT(NULL, ' ', NULL) returns ' ' (a space), not NULL, in T-SQL -- unlike Qlik's
    -- ApplyMap which returns a true NULL on a miss. Guard explicitly with the oper_name IS NULL
    -- check so a miss produces NULL, not a stray space string.
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

-- ---------------------------------------------------------------------------
-- Stage 6: MaxStatus (needed for the Total table's [MaxStatus]-based filters --
-- not directly used by the 6 measures confirmed so far, kept for completeness /
-- in case Claim Lines Processed or other measures need it later)
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- Stage 7: Adjustments -- needed for [Service Type], adjustment_flag,
-- [Adjusted Update Operator] (select_Claims.sql Stage 11, trimmed)
-- ---------------------------------------------------------------------------
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
        -- Raw field (can be NULL) -- needed by Total's Adjusted branch (Qlik line 676),
        -- which reads [Adjusted Update Operator] directly, NOT the ISNULL-fallback below.
        adj.[Adjusted Update Operator],
        ISNULL(adj.[Adjusted Update Operator], adj.[Adj Create Operator])      AS [Adjusted Operator]
    FROM BringTogether AS bt
    LEFT JOIN Adjustments AS adj
        ON adj.[Claim ID] = bt.[Claim ID]
       AND adj.[Adjusted Status Date] > @vStartDate
),

-- ---------------------------------------------------------------------------
-- Stage 8: [Claim ID/Line ID String] (select_Claims.sql Stage 15, CONCAT of
-- [Claim ID] + [Claim Line] -- note: Total's ClaimKey uses [Final Operator],
-- not this string field, but ClaimKey's sibling dimension [Claim&LineID] needs it)
-- ---------------------------------------------------------------------------
WithStringFields AS (
    SELECT
        cwa.*,
        CONCAT(cwa.[Claim ID], cwa.[Adj Claim Line])                            AS [Claim ID/Line ID String]
    FROM ClaimsWithAdjustments AS cwa
)

-- =============================================================================
-- POTENTIAL HANDOFF POINT TO HIPPO: everything above this line (ClaimStatusMain
-- through WithStringFields) is the "heavy" part -- 21 BRONZE table joins, the
-- slow part of this query. Everything below (Stage 9 onward: Total table's 4
-- Concatenate branches, 4 self-joins, AdditionalLogic) is "light" -- pure
-- self-referential logic over WithStringFields, no further BRONZE table access.
--
-- If Hippo materialises WithStringFields as a table, the SELECT below (with
-- WithStringFields swapped for that table) could become a much cheaper VIEW
-- instead of a full 21-table query every time. NOT DECIDED YET -- this needs a
-- scope conversation (does that table serve select_Claims.sql too, or only
-- Total? does DISTINCT belong in the handed-off table or not?) before doing it.
--
-- Uncomment the line below (and comment out the ",\n\n-- ---" + everything
-- from Stage 9 onward) to test JUST the handoff point in isolation:
-- SELECT DISTINCT * FROM WithStringFields
-- =============================================================================
,

-- ---------------------------------------------------------------------------
-- Stage 9: Total table build -- 4 of the 5 Qlik Concatenate branches (Manual
-- Claims branch omitted -- not read by the 6 measures confirmed so far).
-- Each branch's Type/Op/ClaimKey mirror claims_processing.md lines 647-705.
-- ---------------------------------------------------------------------------
TotalProcessed AS (
    SELECT DISTINCT
        [Claim ID]                                                             AS ClaimID,
        [Claim ID/Line ID String]                                              AS [Claim&LineID],
        [Service Type]                                                         AS ServiceType,
        [Final Operator]                                                       AS Op,
        'Claims Processed'                                                     AS Type,
        [Date]                                                                 AS [Count Date],
        CONCAT([Claim ID], '-', [Final Operator])                              AS ClaimKey
    FROM WithStringFields
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
    FROM WithStringFields
    -- Qlik line 669: WildMatch([Verified StatusCheck],'Verified') -- NOT [Verified Status
    -- Date] IS NOT NULL. The two are only interchangeable on the main claim_status branch;
    -- [Verified StatusCheck] is always NULL on the provider branch (see ClaimStatusMain/
    -- ProviderClaimStatus above), so using [Verified Status Date] here would incorrectly
    -- admit provider-sourced 'Sent to Medicare' claims that Qlik's actual filter excludes.
    WHERE [Verified StatusCheck] = 'Verified'
),

TotalAdjusted AS (
    -- Qlik line 676: [Adjusted Update Operator] (raw field, can be NULL) -- NOT [Adjusted
    -- Operator] (the AdjustedOperator stage's ISNULL-fallback-to-[Adj Create Operator]
    -- derived field, line 563). Different fields; using the fallback would wrongly replace
    -- NULLs that Qlik's Total table leaves as NULL here.
    SELECT DISTINCT
        [Claim ID]                                                             AS ClaimID,
        [Claim ID/Line ID String]                                              AS [Claim&LineID],
        [Service Type]                                                         AS ServiceType,
        [Adjusted Update Operator]                                             AS Op,
        'Adjusted/Balanced Claims'                                             AS Type,
        [Date]                                                                 AS [Count Date],
        CONCAT([Claim ID], '-', [Adjusted Update Operator])                    AS ClaimKey
    FROM WithStringFields
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
    FROM WithStringFields
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

-- ---------------------------------------------------------------------------
-- Stage 10: self-joins + AdditionalLogic derived flags (claims_processing.md
-- lines 707-771). ProcessedCheck2/VerifiedOnlyCheck/ProcessedVerifiedCheck/
-- AdjustedOnlyCheck are the flags the 6 target measures actually filter on.
--
-- CRITICAL: Qlik's "Left Join (Total) / LOAD * WHERE <cond>; LOAD <fields>..." auto-joins
-- on ALL identically-named fields between the LOAD's field list and Total's existing
-- columns -- not just [ClaimID]. Each of the 4 joins below has a DIFFERENT set of shared
-- field names (verified by checking which of [ClaimID]/[Claim&LineID]/[Op]/[Count Date]
-- each LOAD block re-emits vs. renames/omits -- claims_processing.md lines 707-750):
--   Join 1 (Verified,  707-717): re-emits ClaimID, Claim&LineID, Op, Count Date unchanged
--                                 -> join key = ClaimID + Claim&LineID + Op + Count Date
--   Join 2 (Processed, 719-728): re-emits ClaimID, Claim&LineID, Op (Count Date renamed to
--                                 ProcessedDATE, so NOT shared) -> join key = ClaimID + Claim&LineID + Op
--   Join 3 (Adjusted,  730-740): Claim&LineID is commented out (line 734); re-emits ClaimID,
--                                 Op, Count Date -> join key = ClaimID + Op + Count Date
--   Join 4 (ProcessedType1, 742-750): Claim&LineID and Count Date both commented out (746-747);
--                                 only ClaimID re-emitted -> join key = ClaimID only
-- ---------------------------------------------------------------------------
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
-- Qlik line 744 is a plain LOAD, NOT "LOAD Distinct" (unlike the Adjusted join at line 732) --
-- if a ClaimID has multiple distinct Op values among its 'Claims Processed' rows, Qlik's
-- Left Join fans out every matching combination. Replicated faithfully (no DISTINCT here).
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
-- Qlik line 757: If([ProcessedCheck]='Verified' and Type='Claims Verified','Verified','Processed')
-- Depends on ProcessedCheck2, which the AdditionalLogic Load chain computes in the SAME
-- statement as this field one step earlier in Qlik's nested Load order -- ProcessedCheck2
-- is a Final2 column, so this has to be a separate CTE layered on top of Final2.
Final3 AS (
    SELECT
        f2.*,
        CASE WHEN f2.ProcessedCheck = 'Verified' AND f2.Type = 'Claims Verified'
             THEN 'Verified' ELSE 'Processed' END                              AS VerifiedOnlyCheck
    FROM Final2 AS f2
)

-- ---------------------------------------------------------------------------
-- Row-level output -- one row per underlying Total-table row (Operator,
-- ClaimID, ServiceType, ClaimKey, Count Date), plus the raw fields each of
-- the 4 Qlik measure expressions filters on (Type / ProcessedCheck2 /
-- VerifiedOnlyCheck / ProcessedVerifiedCheck / AdjustedOnlyCheck) -- NOT
-- pre-computed 0/1 flags. Build each measure downstream (Excel/Power BI) by
-- filtering on these columns exactly as the Qlik expression does, then
-- distinct-counting [ClaimKey]:
--   Processed Claims  = filter ProcessedCheck2='Processed' AND VerifiedOnlyCheck<>'Verified'
--   Verified Claims   = filter Type='Claims Verified' AND ProcessedCheck2<>'Processed'
--                        AND ProcessedVerifiedCheck='Verified' AND AdjustedOnlyCheck<>'Adjusted Only'
--   Adjusted/Balanced = filter Type LIKE 'Adjusted*'
--   Cancelled Claims  = filter Type LIKE '*Cancelled*'
--   Total             = sum of the 4 above
-- [Avg No. Claims Processed Per Day] -- per user decision, also computed
-- downstream: on the Processed Claims filter above, distinct-count [ClaimKey]
-- (numerator) / distinct-count [Count Date] (denominator, day-grain -- NOT
-- MonthYear), grouped by Operator.
-- =-{'x'} in Qlik Set Analysis = exclude x (NOT x). {"*text*"} = wildcard LIKE.
-- ---------------------------------------------------------------------------
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

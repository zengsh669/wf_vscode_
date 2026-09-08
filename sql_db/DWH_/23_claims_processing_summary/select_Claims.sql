-- =============================================================================
-- select_Claims.sql
-- Pure SELECT query replicating the Qlik "Claims" load logic from
-- claims_processing.md. No table is created and no data is persisted --
-- this is a standalone, runnable SELECT.
--
-- Unqualified table names (no BRONZE. prefix) -- run this with the production
-- database (where these tables/views live) set as the current database context.
--
-- Source: sql_db/DWH_/23_claims_processing_summary/claims_processing.md
-- Design: sql_db/DWH_/23_claims_processing_summary/DESIGN.md
--
-- Skipped as dead code (confirmed with user, unused in original Qlik script):
--   ItemMap, PersonMap, ProviderMap, BucketMap, DepartmentMap
--
-- Known Qlik source quirk kept as-is: [Received Year] computes a DATE
-- (same expression as [Received Status Date]), not an actual year --
-- see DESIGN.md for details. Replicated faithfully per user instruction.
--
-- @vStartDate: Qlik = Date(MonthStart(AddYears(today(), -1), -1))
--   = first day of the month, 13 months before today (~13 months of history)
-- =============================================================================

DECLARE @vStartDate DATE = DATEADD(MONTH, -13, DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1));
DECLARE @vToday DATE = CAST(GETDATE() AS DATE);

WITH

-- ---------------------------------------------------------------------------
-- Stage 1: Main claim_status load (Qlik lines 185-229)
-- ---------------------------------------------------------------------------
ClaimStatusMain AS (
    SELECT
        cs.claim_id                                                            AS [Claim ID],
        -- COALESCE, not ISNULL -- same truncation risk as [ClaimChannel]/[Operator Branch]
        -- (grouping.description could be narrower than the 7-char 'No Till' default).
        COALESCE(till_g.description, 'No Till')                                AS [Till Location],
        -- COALESCE, not ISNULL -- same truncation risk as the other default-value fields above
        -- (letter_subject's width isn't documented; a miss here is the common case since most
        -- claims have no correspondence row).
        COALESCE(ca.letter_subject, 'No Attachment')                           AS [Attachment Subject],
        -- COALESCE (not ISNULL) here: ISNULL's return type/width follows its FIRST argument,
        -- so if cbc.category is narrower than the 32-char default literal, ISNULL would
        -- silently truncate it (same class of bug fixed for [Branch] in an earlier pass).
        -- COALESCE resolves to the widest/highest-precedence type across all arguments.
        CASE
            WHEN cs.create_operator LIKE '%-%' THEN 'ECLAIMS'
            ELSE COALESCE(cbc.category, 'Top Up Claims (System Generated)')
        END                                                                    AS [ClaimChannel],
        -- Qlik lines 186-187: outer wrapping LOAD adds [Claim Channel] (note the space --
        -- distinct field from [ClaimChannel] above). Wildmatch with no wildcards = exact match.
        CASE
            WHEN (CASE WHEN cs.create_operator LIKE '%-%' THEN 'ECLAIMS'
                       ELSE COALESCE(cbc.category, 'Top Up Claims (System Generated)') END) IN ('ECLAIMS', 'MOBILE')
                THEN 'Online'
            ELSE (CASE WHEN cs.create_operator LIKE '%-%' THEN 'ECLAIMS'
                       ELSE COALESCE(cbc.category, 'Top Up Claims (System Generated)') END)
        END                                                                    AS [Claim Channel],
        ISNULL(CAST(c_mem.membership_id AS VARCHAR(20)), 'no member')          AS [Membership ID],
        cs.claim_status_version,
        ISNULL(cst.description, 'MISSING')                                     AS Status,
        CAST(cs.status_date AS DATE)                                           AS [Date],
        YEAR(cs.status_date)                                                   AS [Year],
        DATEPART(HOUR, cs.status_date)                                         AS [Hour],
        DAY(cs.status_date)                                                    AS [Day],
        -- FORMAT() infers as NVARCHAR(4000); CAST to a tight width so a naive schema
        -- inference (e.g. by Hippo materialising this into a table) doesn't inherit that.
        -- 'MMM yyyy' is at most 8 chars ('Sep 2026' etc.), matching the provider-side placeholder.
        CAST(FORMAT(cs.status_date, 'MMM yyyy') AS VARCHAR(8))                 AS [MonthYear],
        -- Qlik WeekEnd(): FirstWeekDay=0 (Monday), week ends Sunday
        DATEADD(DAY, 6 - DATEDIFF(DAY, '1900-01-01', cs.status_date) % 7, CAST(cs.status_date AS DATE)) AS [Week End],
        CAST(cs.status_date AS DATE)                                           AS [Status Date],
        CASE
            WHEN cs.create_operator LIKE '%-%' THEN 'ECLAIMS'
            ELSE cs.create_operator
        END                                                                    AS [Create Operator],
        -- [Claim Operator] (Qlik lines 204-211): inner nested IF collapses to Verified+has
        -- update_operator -> update_operator, else create_operator; outer isnum() wraps that
        -- result -- if it looks numeric, output 'Web/Mobile Claim' instead.
        -- Qlik's inner condition is `len(update_operator>0)`, parsed as LEN(boolean) -- always
        -- truthy (1 or 2) -- same source bug as line 327 (see FinalOperatorLookupCode below).
        -- Replicated as always-true here too, for consistency with that deliberate decision:
        -- the branch always resolves to update_operator when Verified, never falls through.
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
        CASE WHEN ISNULL(cst.description, 'MISSING') = 'Received and Logged' THEN CAST(cs.status_date AS DATE) END AS [Received Status Date],
        -- NOTE: [Received Year] is a known Qlik source quirk -- computes a DATE, not YEAR(). Replicated as-is per user instruction.
        CASE WHEN ISNULL(cst.description, 'MISSING') = 'Received and Logged' THEN CAST(cs.status_date AS DATE) END AS [Received Year],
        CASE WHEN ISNULL(cst.description, 'MISSING') = 'Paid' THEN CAST(cs.status_date AS DATE) END AS [Paid Status Date],
        CASE WHEN ISNULL(cst.description, 'MISSING') IN ('Manually Verified', 'Verified') THEN CAST(cs.status_date AS DATE) END AS [Verified Status Date],
        CASE WHEN ISNULL(cst.description, 'MISSING') IN ('Manually Verified', 'Verified') THEN 'Verified' END AS [Verified StatusCheck],
        cs.create_datetime,
        CASE
            WHEN cs.update_operator LIKE '%-%' THEN 'ECLAIMS'
            ELSE cs.update_operator
        END                                                                    AS [update_operator],
        cs.update_operator                                                     AS [Update Operator],
        cs.update_datetime,
        -- Qlik lines 241-242 (Concatenate side) emit bare status_date/create_operator fields;
        -- the main load never sets them, so they are NULL here (matching Qlik Concatenate semantics).
        CAST(NULL AS DATETIME)                                                 AS status_date,
        CAST(NULL AS CHAR(16))                                                 AS create_operator
    FROM dbo.claim_status AS cs
    -- Qlik line 154: TillMap is "LOAD distinct" -- DISTINCT required to match (also keeps
    -- parity with the MembershipIDMap subquery below, which already has it).
    LEFT JOIN (
        SELECT DISTINCT claim_id, till_id
        FROM dbo.claim
        WHERE create_datetime > @vStartDate
    ) AS c_till
        ON c_till.claim_id = cs.claim_id
    LEFT JOIN dbo.till AS tn
        ON tn.till_id = c_till.till_id
    -- Qlik TillNameMap (lines 161-168): till LEFT JOIN grouping ON group_id -- returns
    -- grouping.description, not till.description.
    LEFT JOIN dbo.grouping AS till_g
        ON till_g.group_id = tn.group_id
    OUTER APPLY (
        SELECT TOP 1 mc.letter_subject
        FROM dbo.MemberCorrespondance AS mc
        WHERE mc.form_category = '3'
          AND REPLACE(SUBSTRING(mc.letter_subject, CHARINDEX('# ', mc.letter_subject) + 1, LEN(mc.letter_subject)), ' ', '') = CAST(cs.claim_id AS VARCHAR(20))
        ORDER BY mc.letter_subject
    ) AS ca
    LEFT JOIN dbo.ClaimsByChannel AS cbc
        ON cbc.claim_id = cs.claim_id
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

-- ---------------------------------------------------------------------------
-- Stage 2: Provider claim status load, concatenated into Claims (Qlik lines 236-255)
-- ---------------------------------------------------------------------------
ProviderClaimStatus AS (
    SELECT
        pcs.provider_claim_id                                                  AS [Claim ID],
        CAST(NULL AS VARCHAR(50))                                              AS [Till Location],
        CAST(NULL AS NVARCHAR(MAX))                                            AS [Attachment Subject],
        CAST(NULL AS VARCHAR(50))                                              AS [ClaimChannel],
        CAST(NULL AS VARCHAR(50))                                              AS [Claim Channel],
        CAST(NULL AS VARCHAR(20))                                              AS [Membership ID],
        pcs.claim_status_version,
        ISNULL(pcst.description, 'Missing')                                    AS Status,
        CAST(pcs.status_date AS DATE)                                          AS [Date],
        CAST(NULL AS SMALLINT)                                                 AS [Year],
        CAST(NULL AS TINYINT)                                                  AS [Hour],
        CAST(NULL AS TINYINT)                                                  AS [Day],
        CAST(NULL AS VARCHAR(8))                                               AS [MonthYear],
        CAST(NULL AS DATE)                                                     AS [Week End],
        CAST(NULL AS DATE)                                                     AS [Status Date],
        CAST(NULL AS VARCHAR(16))                                              AS [Create Operator],
        -- Qlik lines 245-246: same len(update_operator>0) always-true source bug as the main
        -- load's [Claim Operator] -- replicated as always-true for consistency.
        CASE
            WHEN ISNULL(pcst.description, 'MISSING') = 'Verified'
                THEN pcs.update_operator
            ELSE pcs.create_operator
        END                                                                    AS [Claim Operator],
        CASE WHEN ISNULL(pcst.description, 'MISSING') = 'Received' THEN CAST(pcs.status_date AS DATE) END AS [Received Status Date],
        CAST(NULL AS DATE)                                                     AS [Received Year],
        CASE WHEN ISNULL(pcst.description, 'MISSING') = 'Paid' THEN CAST(pcs.status_date AS DATE) END AS [Paid Status Date],
        CASE WHEN ISNULL(pcst.description, 'MISSING') LIKE '%Sent to Medicare%' THEN CAST(pcs.status_date AS DATE) END AS [Verified Status Date],
        CAST(NULL AS VARCHAR(10))                                              AS [Verified StatusCheck],
        pcs.create_datetime,
        CASE
            WHEN pcs.update_operator LIKE '%-%' THEN 'ECLAIMS'
            ELSE pcs.update_operator
        END                                                                    AS [update_operator],
        pcs.update_operator                                                    AS [Update Operator],
        pcs.update_datetime,
        pcs.status_date,
        pcs.create_operator
    FROM dbo.provider_claim_status AS pcs
    LEFT JOIN dbo.provider_claim_status_type AS pcst
        ON pcst.provider_claim_status_type = pcs.provider_claim_status_type
    WHERE pcs.status_date > @vStartDate
),

-- ---------------------------------------------------------------------------
-- Stage 3: Concatenate (UNION ALL) of the two claim status paths (Qlik "Concatenate (Claims)")
-- ---------------------------------------------------------------------------
ClaimsUnion AS (
    SELECT * FROM ClaimStatusMain
    UNION ALL
    SELECT * FROM ProviderClaimStatus
),

-- ---------------------------------------------------------------------------
-- Stage 4a: Verified Claims left-join source (Qlik lines 262-283, claim_status_type = 'V')
-- ---------------------------------------------------------------------------
-- Qlik auto-joins Left Join on ALL identically-named fields. The Verified LOAD (lines 262-283)
-- also emits [Membership ID] (line 266) and [Verified Status Date] (line 270) alongside
-- [Claim ID] -- so this join key is a 3-column composite, not [Claim ID] alone.
VerifiedClaims AS (
    SELECT
        cs.claim_id                                                            AS [Claim ID],
        ISNULL(CAST(c_mem.membership_id AS VARCHAR(20)), 'no member')          AS [Membership ID],
        -- update_operator/claim_status_type/status_date are NOT emitted by the Qlik Verified
        -- LOAD (lines 264-271) -- they're preceding-SELECT columns consumed by the LOAD, not
        -- output fields. Omitted here so this CTE's columns match Qlik's actual join-field set.
        ISNULL(cst.description, 'MISSING')                                     AS VerifiedStatus,
        CASE
            WHEN COALESCE(cs.update_operator, cs.create_operator) LIKE '%-%'
                THEN SUBSTRING(COALESCE(cs.update_operator, cs.create_operator), 1, CHARINDEX('-', COALESCE(cs.update_operator, cs.create_operator)) - 1)
            ELSE COALESCE(cs.update_operator, cs.create_operator)
        END                                                                    AS [Verified Operator],
        CASE WHEN ISNULL(cst.description, 'MISSING') IN ('Manually Verified', 'Verified') THEN CAST(cs.status_date AS DATE) END AS [VerifiedStatusDate],
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

-- ---------------------------------------------------------------------------
-- Stage 4b: Assessed (Received) Claims left-join source (Qlik lines 285-300, claim_status_type = 'A')
-- ---------------------------------------------------------------------------
-- Qlik: Assessed LOAD (lines 285-300) also emits [Membership ID] (line 289) -- composite key
-- with [Claim ID], same reasoning as VerifiedClaims above.
AssessedClaims AS (
    SELECT
        cs.claim_id                                                            AS [Claim ID],
        ISNULL(CAST(c_mem.membership_id AS VARCHAR(20)), 'no member')          AS [Membership ID],
        -- update_operator is NOT emitted by the Qlik Assessed LOAD (lines 287-292) -- it's a
        -- preceding-SELECT column consumed by the LOAD, not an output field. Omitted for the
        -- same reason as in VerifiedClaims above.
        ISNULL(cst.description, 'MISSING')                                     AS AssessedStatus,
        CASE
            WHEN cs.update_operator LIKE '%-%'
                THEN SUBSTRING(cs.update_operator, 1, CHARINDEX('-', cs.update_operator) - 1)
            ELSE cs.update_operator
        END                                                                    AS [Assessed Operator],
        CASE WHEN ISNULL(cst.description, 'MISSING') = 'Assessed but not Verified' THEN CAST(cs.status_date AS DATE) END AS [AssessedStatusDate]
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

-- ---------------------------------------------------------------------------
-- Stage 4c: Paid Claims (Online) left-join source (Qlik lines 302-319, claim_status_type = 'P')
-- ---------------------------------------------------------------------------
-- Qlik: Paid LOAD (lines 302-319) also emits [Membership ID] (line 306) -- composite key
-- with [Claim ID], same reasoning as VerifiedClaims above.
PaidClaims AS (
    SELECT
        cs.claim_id                                                            AS [Claim ID],
        ISNULL(CAST(c_mem.membership_id AS VARCHAR(20)), 'no member')          AS [Membership ID],
        ISNULL(cst.description, 'MISSING')                                     AS PaidStatus,
        CASE WHEN ISNUMERIC(
                CASE WHEN cs.update_operator LIKE '%-%'
                    THEN SUBSTRING(cs.update_operator, 1, CHARINDEX('-', cs.update_operator) - 1)
                    ELSE cs.update_operator
                END) = 1
            THEN CASE WHEN cs.update_operator LIKE '%-%'
                    THEN SUBSTRING(cs.update_operator, 1, CHARINDEX('-', cs.update_operator) - 1)
                    ELSE cs.update_operator
                END
            ELSE 'Not Online'
        END                                                                    AS [Paid Operator],
        CASE WHEN ISNULL(cst.description, 'MISSING') LIKE '%Paid%' THEN CAST(cs.status_date AS DATE) END AS [PaidStatusDate],
        CASE WHEN ISNUMERIC(
                CASE WHEN cs.create_operator LIKE '%-%'
                    THEN SUBSTRING(cs.create_operator, 1, CHARINDEX('-', cs.create_operator) - 1)
                    ELSE cs.create_operator
                END) = 1
            THEN CASE WHEN cs.create_operator LIKE '%-%'
                    THEN SUBSTRING(cs.create_operator, 1, CHARINDEX('-', cs.create_operator) - 1)
                    ELSE cs.create_operator
                END
            ELSE 'Not Online'
        END                                                                    AS [PaidCreateOperator]
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
      AND cs.claim_status_type = 'P'
),

-- ---------------------------------------------------------------------------
-- Stage 5: OperatorCheck -- Final/Assessed/Verified operator resolution (Qlik lines 321-339)
-- ---------------------------------------------------------------------------
ClaimsWithOperators AS (
    SELECT
        cu.*,
        vc.VerifiedStatus,
        vc.[Verified Operator],
        vc.[VerifiedStatusDate],
        ac.AssessedStatus,
        ac.[Assessed Operator],
        ac.[AssessedStatusDate],
        pc.PaidStatus,
        pc.[PaidStatusDate],
        pc.[Paid Operator],
        pc.[PaidCreateOperator],
        CASE WHEN cu.[Claim Operator] LIKE '%-%' THEN 'ECLAIMS' ELSE cu.[Claim Operator] END AS [ClaimOperator],
        CASE
            WHEN pc.[PaidCreateOperator] = pc.[Paid Operator]
                 AND pc.[PaidCreateOperator] <> 'Not Online'
                 AND pc.[Paid Operator] <> 'Not Online'
                THEN 'Untouched'
            ELSE 'Touched'
        END                                                                    AS [Online Claim Touched/Untouched]
    FROM ClaimsUnion AS cu
    -- Qlik auto-joins on ALL identically-named fields: [Claim ID] + [Membership ID] + [Verified
    -- Status Date] for the Verified join. See notes on VerifiedClaims/AssessedClaims/PaidClaims.
    -- NOTE: an earlier pass added a "NULL-safe" OR branch here on the premise that Qlik's Join
    -- treats NULL=NULL as a match. That premise was wrong -- Qlik NULLs never match in a join,
    -- same as SQL's "=" semantics -- so plain equality is the correct, faithful translation.
    LEFT JOIN VerifiedClaims AS vc
        ON vc.[Claim ID] = cu.[Claim ID]
       AND vc.[Membership ID] = cu.[Membership ID]
       AND vc.[Verified Status Date] = cu.[Verified Status Date]
    LEFT JOIN AssessedClaims AS ac
        ON ac.[Claim ID] = cu.[Claim ID]
       AND ac.[Membership ID] = cu.[Membership ID]
    LEFT JOIN PaidClaims AS pc
        ON pc.[Claim ID] = cu.[Claim ID]
       AND pc.[Membership ID] = cu.[Membership ID]
),
ClaimsWithOperators2 AS (
    SELECT
        co.*,
        ISNULL(co.[Verified Operator], 'No Operator')                          AS VerifiedOperator,
        ISNULL(co.[Assessed Operator], 'No Operator')                          AS AssessedOperator,
        -- Qlik line 327: len(update_operator>0) is a Qlik source bug -- it parses as
        -- len(update_operator > 0), i.e. LEN() of a boolean, which is always truthy (1 or 2).
        -- So this branch ALWAYS takes update_operator in the original Qlik logic; it never
        -- falls through to [ClaimOperator]. Replicated as-is per user instruction (not "fixed").
        co.[update_operator]                                                   AS FinalOperatorLookupCode
    FROM ClaimsWithOperators AS co
),
-- Single shared lookup of operator full name (first_name & ' ' & surname) by oper_name code,
-- used for [Final Operator], [AssessedOperatorCheck] and [VerifiedOperatorCheck] (Qlik lines
-- 327-329: ApplyMap('OperatorMap', <key>) with NO default argument -- Qlik returns the lookup
-- key itself on a miss, not NULL. A LEFT JOIN miss makes op_x.oper_name NULL, so that's the
-- correct "miss" test (CONCAT of two NULLs returns ' ', not NULL, so testing oper_name directly
-- avoids that trap).
ClaimsWithOperators3 AS (
    SELECT
        co2.*,
        CASE WHEN co2.AssessedStatus = 'Assessed but not Verified'
             THEN CASE WHEN op_assessed.oper_name IS NULL THEN co2.AssessedOperator
                       ELSE CONCAT(op_assessed.first_name, ' ', op_assessed.surname) END
             ELSE 'No Operator' END                                            AS AssessedOperatorCheck,
        CASE WHEN co2.VerifiedStatus = 'Verified'
             THEN CASE WHEN op_verified.oper_name IS NULL THEN co2.VerifiedOperator
                       ELSE CONCAT(op_verified.first_name, ' ', op_verified.surname) END
             ELSE 'No Operator' END                                            AS VerifiedOperatorCheck,
        CASE WHEN co2.Status IN ('Verified', 'Cancelled', 'Assessed but not Verified')
             THEN CASE WHEN op_final.oper_name IS NULL THEN co2.FinalOperatorLookupCode
                       ELSE CONCAT(op_final.first_name, ' ', op_final.surname) END
        END                                                                    AS [Final Operator]
    FROM ClaimsWithOperators2 AS co2
    LEFT JOIN dbo.operator AS op_assessed
        ON op_assessed.oper_name = co2.AssessedOperator
    LEFT JOIN dbo.operator AS op_verified
        ON op_verified.oper_name = co2.VerifiedOperator
    LEFT JOIN dbo.operator AS op_final
        ON op_final.oper_name = co2.FinalOperatorLookupCode
),
-- Qlik lines 322-325: [Verified Check] -- derived from AssessedOperatorCheck/VerifiedOperatorCheck above
ClaimsWithOperators4 AS (
    SELECT
        co3.*,
        CASE WHEN co3.AssessedOperatorCheck <> co3.VerifiedOperatorCheck
                  AND co3.VerifiedOperatorCheck <> 'No Operator'
                  AND co3.AssessedOperatorCheck <> 'No Operator'
             THEN 'Verified By Operator'
        END                                                                    AS [Verified Check]
    FROM ClaimsWithOperators3 AS co3
),

-- ---------------------------------------------------------------------------
-- Stage 6a: MaxStatus (Provider path) -- latest provider_claim_status per claim (Qlik lines 341-356)
-- ---------------------------------------------------------------------------
MaxStatusProvider AS (
    SELECT DISTINCT
        mg.provider_claim_id                                                   AS [Claim ID],
        pt.description                                                         AS MaxClaimStatusProvider,
        mg.create_operator                                                     AS MaxStatusProviderCreateOperator,
        mg.status_date                                                         AS MaxStatusDateProvider
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

-- ---------------------------------------------------------------------------
-- Stage 6b: MaxStatus (Other/claim path) -- latest claim_status per claim (Qlik lines 363-378)
-- ---------------------------------------------------------------------------
MaxStatusOther AS (
    SELECT DISTINCT
        mg.claim_id                                                            AS [Claim ID],
        pt.description                                                         AS MaxClaimStatusOther,
        mg.create_operator                                                     AS MaxStatusCreateOperatorOther,
        mg.status_date                                                         AS MaxStatusDateOther
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

-- ---------------------------------------------------------------------------
-- Stage 7a: Gen/Hosp Bucket allocation (Qlik lines 385-395)
-- ---------------------------------------------------------------------------
GenHospBucket AS (
    SELECT
        ca.claim_id                                                            AS [Claim ID],
        CASE WHEN ISNULL(bt.claim_type_flag, 'Missing') = 'H' THEN 'Hospital' ELSE 'General' END AS [Gen/Hosp Bucket Type],
        CASE WHEN ca.claim_alloc_reason_id = 1 THEN 'Bucket claims' ELSE 'Allocated Claims' END AS [Gen/Hosp Bucket Claims],
        CAST(ca.create_datetime AS DATE)                                       AS [Gen/Hosp Bucket Claims Lodge Date],
        -- Qlik NetWorkDays: inclusive business-day count between two dates (+1 vs the exclusive
        -- formula). Weekday test uses DATEDIFF %7 arithmetic (deterministic, not @@LANGUAGE-dependent),
        -- matching the [Week End] expression above. 1900-01-01 was a Monday, so day 0 = Monday.
        DATEDIFF(DAY, ca.create_datetime, @vToday)
            - (DATEDIFF(WEEK, ca.create_datetime, @vToday) * 2)
            - (CASE WHEN DATEDIFF(DAY, '1900-01-01', ca.create_datetime) % 7 = 6 THEN 1 ELSE 0 END)
            - (CASE WHEN DATEDIFF(DAY, '1900-01-01', @vToday) % 7 = 5 THEN 1 ELSE 0 END)
            + 1                                                                        AS [Gen/Hosp Claim Age in Bucket]
    FROM dbo.claim_alloc AS ca
    -- Qlik lines 101-108: BucketTypeMap is a Mapping table -- Qlik Mapping LOADs implicitly
    -- keep only the first row per key (ApplyMap never returns more than one value), even
    -- without an explicit "distinct". GROUP BY + MIN replicates that one-value-per-key
    -- guarantee (plain DISTINCT would still fan out if claim_type_flag varies per claim_id).
    LEFT JOIN (
        SELECT claim_id, MIN(claim_type_flag) AS claim_type_flag
        FROM dbo.claim
        WHERE create_datetime > @vStartDate
        GROUP BY claim_id
    ) AS bt
        ON bt.claim_id = ca.claim_id
    WHERE ca.create_datetime > @vStartDate
),

-- ---------------------------------------------------------------------------
-- Stage 7b: Provider Bucket allocation (Qlik lines 403-421)
-- ---------------------------------------------------------------------------
ProviderBucket AS (
    SELECT
        pca.provider_claim_id                                                  AS [Claim ID],
        'Medical'                                                              AS [Provider Bucket Type],
        CASE WHEN pca.claim_alloc_reason_id = 2 THEN 'Bucket claims' ELSE 'Allocated Claims' END AS [Provider Bucket Claims],
        CAST(pca.create_datetime AS DATE)                                      AS [Provider Bucket Claims Lodge Date],
        DATEDIFF(DAY, pca.create_datetime, @vToday)
            - (DATEDIFF(WEEK, pca.create_datetime, @vToday) * 2)
            - (CASE WHEN DATEDIFF(DAY, '1900-01-01', pca.create_datetime) % 7 = 6 THEN 1 ELSE 0 END)
            - (CASE WHEN DATEDIFF(DAY, '1900-01-01', @vToday) % 7 = 5 THEN 1 ELSE 0 END)
            + 1                                                                        AS [Provider Claim Age in Bucket]
    FROM dbo.provider_claim_alloc AS pca
    WHERE pca.create_datetime > @vStartDate
),

-- ---------------------------------------------------------------------------
-- Stage 8: BringTogether -- merge bucket/max-status fields, compute Held Days (Qlik lines 429-442)
-- ---------------------------------------------------------------------------
BringTogether AS (
    SELECT
        co3.*,
        ghb.[Gen/Hosp Bucket Type],
        ghb.[Gen/Hosp Bucket Claims],
        ghb.[Gen/Hosp Bucket Claims Lodge Date],
        ghb.[Gen/Hosp Claim Age in Bucket],
        pb.[Provider Bucket Type],
        pb.[Provider Bucket Claims],
        pb.[Provider Bucket Claims Lodge Date],
        pb.[Provider Claim Age in Bucket],
        msp.MaxClaimStatusProvider,
        msp.MaxStatusProviderCreateOperator,
        msp.MaxStatusDateProvider,
        mso.MaxClaimStatusOther,
        mso.MaxStatusCreateOperatorOther,
        mso.MaxStatusDateOther,
        ISNULL(ghb.[Gen/Hosp Bucket Type], pb.[Provider Bucket Type])          AS [Bucket Type],
        ISNULL(ghb.[Gen/Hosp Bucket Claims], pb.[Provider Bucket Claims])      AS [Bucket Claims],
        ISNULL(ghb.[Gen/Hosp Bucket Claims Lodge Date], pb.[Provider Bucket Claims Lodge Date]) AS [Bucket Claims Lodge Date],
        ISNULL(ghb.[Gen/Hosp Claim Age in Bucket], pb.[Provider Claim Age in Bucket]) AS [Claim Age in Bucket],
        ISNULL(msp.MaxClaimStatusProvider, mso.MaxClaimStatusOther)            AS MaxStatus,
        ISNULL(msp.MaxStatusProviderCreateOperator, mso.MaxStatusCreateOperatorOther) AS MaxStatusCreateOperator,
        ISNULL(msp.MaxStatusDateProvider, mso.MaxStatusDateOther)              AS MaxStatusStatusDate
    FROM ClaimsWithOperators4 AS co3
    LEFT JOIN GenHospBucket AS ghb
        ON ghb.[Claim ID] = co3.[Claim ID]
    LEFT JOIN ProviderBucket AS pb
        ON pb.[Claim ID] = co3.[Claim ID]
    LEFT JOIN MaxStatusProvider AS msp
        ON msp.[Claim ID] = co3.[Claim ID]
    LEFT JOIN MaxStatusOther AS mso
        ON mso.[Claim ID] = co3.[Claim ID]
),
BringTogether2 AS (
    SELECT
        bt.*,
        DATEDIFF(DAY, bt.MaxStatusStatusDate, @vToday)
            - (DATEDIFF(WEEK, bt.MaxStatusStatusDate, @vToday) * 2)
            - (CASE WHEN DATEDIFF(DAY, '1900-01-01', bt.MaxStatusStatusDate) % 7 = 6 THEN 1 ELSE 0 END)
            - (CASE WHEN DATEDIFF(DAY, '1900-01-01', @vToday) % 7 = 5 THEN 1 ELSE 0 END)
            + 1                                                                        AS [Held Days]
    FROM BringTogether AS bt
),

-- ---------------------------------------------------------------------------
-- Stage 9: Cohort IntervalMatch -- Age in Bucket / Held Days bands (Qlik lines 444-474)
-- ---------------------------------------------------------------------------
WithCohorts AS (
    SELECT
        bt2.*,
        CASE
            WHEN bt2.[Claim Age in Bucket] BETWEEN -10 AND 2   THEN '0-2'
            WHEN bt2.[Claim Age in Bucket] BETWEEN 3 AND 5     THEN '3-5'
            WHEN bt2.[Claim Age in Bucket] BETWEEN 6 AND 10    THEN '6-10'
            WHEN bt2.[Claim Age in Bucket] BETWEEN 11 AND 14   THEN '11-14'
            WHEN bt2.[Claim Age in Bucket] BETWEEN 15 AND 27   THEN '14-28'
            WHEN bt2.[Claim Age in Bucket] BETWEEN 28 AND 1000 THEN '29+'
        END                                                                    AS BucketAgeCohort,
        CASE
            WHEN bt2.[Held Days] BETWEEN -10 AND 2   THEN '0-2'
            WHEN bt2.[Held Days] BETWEEN 3 AND 5     THEN '3-5'
            WHEN bt2.[Held Days] BETWEEN 6 AND 10    THEN '6-10'
            WHEN bt2.[Held Days] BETWEEN 11 AND 14   THEN '11-14'
            WHEN bt2.[Held Days] BETWEEN 15 AND 28   THEN '15-28'
            WHEN bt2.[Held Days] BETWEEN 29 AND 60   THEN '29-60'
            WHEN bt2.[Held Days] BETWEEN 61 AND 1000 THEN '61+'
        END                                                                    AS HeldAgeCohort
    FROM BringTogether2 AS bt2
),

-- ---------------------------------------------------------------------------
-- Stage 10: DaysTilPaid (Qlik lines 476-483)
-- ---------------------------------------------------------------------------
DaysTilPaid AS (
    SELECT
        wc.*,
        DATEDIFF(DAY, wc.[Bucket Claims Lodge Date], wc.[Paid Status Date])
            - (DATEDIFF(WEEK, wc.[Bucket Claims Lodge Date], wc.[Paid Status Date]) * 2)
            - (CASE WHEN DATEDIFF(DAY, '1900-01-01', wc.[Bucket Claims Lodge Date]) % 7 = 6 THEN 1 ELSE 0 END)
            - (CASE WHEN DATEDIFF(DAY, '1900-01-01', wc.[Paid Status Date]) % 7 = 5 THEN 1 ELSE 0 END)
            + 1                                                                        AS [Days to Pay Claim],
        DATEDIFF(DAY, wc.[Bucket Claims Lodge Date], wc.[Verified Status Date])
            - (DATEDIFF(WEEK, wc.[Bucket Claims Lodge Date], wc.[Verified Status Date]) * 2)
            - (CASE WHEN DATEDIFF(DAY, '1900-01-01', wc.[Bucket Claims Lodge Date]) % 7 = 6 THEN 1 ELSE 0 END)
            - (CASE WHEN DATEDIFF(DAY, '1900-01-01', wc.[Verified Status Date]) % 7 = 5 THEN 1 ELSE 0 END)
            + 1                                                                        AS [Days to Verify Claim],
        CASE WHEN wc.[Date] = @vToday THEN 'Today' ELSE 'Not Today' END        AS [Today Flag]
    FROM WithCohorts AS wc
),

-- ---------------------------------------------------------------------------
-- Stage 11: Adjustments -- claim line detail left join (Qlik lines 487-536)
-- ---------------------------------------------------------------------------
Adjustments AS (
    SELECT
        cd.claim_id                                                            AS [Claim ID],
        cd.claim_line_id                                                       AS [Claim Line],
        -- Qlik line 492: ApplyMap('OperatorMap', create_operator, create_operator) -- explicit
        -- default = the key itself. CONCAT(NULL,' ',NULL) returns ' ' not NULL, so ISNULL(CONCAT(...))
        -- would never fall through -- test op1.oper_name IS NULL directly instead.
        CASE WHEN op1.oper_name IS NULL THEN cd.create_operator
             ELSE CONCAT(op1.first_name, ' ', op1.surname) END                 AS [Adj Create Operator],
        cd.create_datetime                                                     AS [Adjustment Date],
        cd.payee_method                                                        AS [Payee Method],
        cd.adjustment_flag,
        cd.claim_type,
        cd.line_status,
        cd.item_number,
        cd.status_date                                                         AS [Adjusted Status Date],
        i.description                                                         AS [Item Description],
        cd.service_type                                                        AS [Service Type],
        cd.fee,
        cd.benefit,
        cd.membership_id,
        CAST(cd.service_date AS DATE)                                          AS [Service Date],
        cd.provider_number_id                                                  AS [Provider Number],
        p.provider_name,
        cs.Product_Description_at_claim                                        AS [Product Description],
        cd.person_id                                                           AS [Person ID],
        ISNULL(pn.[first_name_surname], 'Unknown Name')                        AS [Person Name],
        cd.Num_services                                                        AS [Number of Services],
        -- Qlik line 513: same ApplyMap-with-key-as-default pattern as above.
        CASE WHEN op2.oper_name IS NULL THEN cd.update_operator
             ELSE CONCAT(op2.first_name, ' ', op2.surname) END                 AS [Adjusted Update Operator]
    FROM dbo.ClaimDetailGenAndHosp AS cd
    LEFT JOIN dbo.provider_number AS pnum
        ON cd.provider_number_id = pnum.provider_number_id
    LEFT JOIN dbo.provider AS p
        ON pnum.provider_id = p.provider_id
    INNER JOIN dbo.ClaimDetailsAtService AS cs
        ON cd.claim_id = cs.claim_id AND cd.claim_line_id = cs.claim_line_id
    LEFT JOIN dbo.item AS i
        ON cd.service_type = i.service_type AND cd.item_number = i.item_number
    LEFT JOIN dbo.operator AS op1
        ON op1.oper_name = cd.create_operator
    LEFT JOIN dbo.operator AS op2
        ON op2.oper_name = cd.update_operator
    OUTER APPLY (
        SELECT TOP 1 CONCAT(per.first_name, ' ', per.surname) AS [first_name_surname]
        FROM dbo.person AS per
        WHERE per.person_id = cd.person_id
        ORDER BY per.person_id
    ) AS pn
    WHERE cd.status_date > @vStartDate
),

-- ---------------------------------------------------------------------------
-- Stage 12: Manual Claim flag (Qlik lines 529-536, QVD)
-- ---------------------------------------------------------------------------
ManualClaimFlag AS (
    SELECT
        cgi.claim_id                                                           AS [Claim ID],
        cgi.claim_line_id                                                      AS [Claim Line ID],
        CASE WHEN cgi.manual_flag = 1 THEN 'Manual Claim' ELSE 'Not Manual Claim' END AS [Manual Claim]
    FROM dbo.claim_generalitem AS cgi
    WHERE cgi.create_datetime > @vStartDate
),

-- ---------------------------------------------------------------------------
-- Stage 13: Current Product / Current Agent (Qlik lines 543-555, QVD)
-- ---------------------------------------------------------------------------
-- [Membership ID] downstream (dtp.[Membership ID]) is VARCHAR(20), commonly the literal
-- 'no member' sentinel. membership_id here is DECIMAL(9,0). SQL Server's numeric type
-- precedence would otherwise coerce the VARCHAR side to numeric on join, raising a hard
-- "Error converting data type varchar to numeric" the first time it hits 'no member' --
-- not a rare case, since c_mem's create_datetime filter and the outer status_date filter
-- don't align, so 'no member' rows are common. Cast here, same pattern as the [Branch]/
-- grouping.group_id fix.
CurrentProduct AS (
    SELECT
        CAST(mc.membership_id AS VARCHAR(20))                                  AS [Membership ID],
        mc.Product_Description                                                 AS [Current Product]
    FROM dbo.MemberCover AS mc
),
CurrentAgent AS (
    SELECT
        CAST(ma.membership_id AS VARCHAR(20))                                  AS [Membership ID],
        ma.description                                                         AS [Current Agent]
    FROM dbo.MemberAgent AS ma
),

-- ---------------------------------------------------------------------------
-- Stage 14: Join adjustments + manual flag + current product/agent onto Claims (Qlik lines 486-555)
-- ---------------------------------------------------------------------------
ClaimsWithAdjustments AS (
    SELECT
        dtp.*,
        adj.[Claim Line],
        adj.[Adj Create Operator],
        adj.[Adjustment Date],
        adj.[Payee Method],
        adj.adjustment_flag,
        adj.claim_type,
        adj.line_status,
        adj.item_number,
        adj.[Adjusted Status Date],
        adj.[Item Description],
        adj.[Service Type],
        adj.fee,
        adj.benefit,
        adj.membership_id,
        adj.[Service Date],
        adj.[Provider Number],
        adj.provider_name,
        adj.[Product Description],
        adj.[Person ID],
        adj.[Person Name],
        adj.[Number of Services],
        adj.[Adjusted Update Operator],
        mcf.[Manual Claim],
        cp.[Current Product],
        cag.[Current Agent],
        ISNULL(adj.[Adjusted Update Operator], adj.[Adj Create Operator])      AS [Adjusted Operator]
    FROM DaysTilPaid AS dtp
    LEFT JOIN Adjustments AS adj
        ON adj.[Claim ID] = dtp.[Claim ID]
       AND adj.[Adjusted Status Date] > @vStartDate
    -- Qlik auto-joins Left Join on ALL same-named fields. The Manual Claim QVD load (lines
    -- 529-536) produces [Claim Line ID], NOT [Claim Line] -- different field name from the
    -- Adjustments join's [Claim Line] (line 491) -- so Qlik only matches on [Claim ID] here,
    -- not on claim line. Confirmed via grep: "Claim Line" only appears as [Claim Line] (491)
    -- and [Claim Line ID] (532) -- distinct field names, no auto-join on line.
    LEFT JOIN ManualClaimFlag AS mcf
        ON mcf.[Claim ID] = dtp.[Claim ID]
    LEFT JOIN CurrentProduct AS cp
        ON cp.[Membership ID] = dtp.[Membership ID]
    LEFT JOIN CurrentAgent AS cag
        ON cag.[Membership ID] = dtp.[Membership ID]
),

-- ---------------------------------------------------------------------------
-- Stage 15: String -- Nprint flag, Claim ID/Line string, HO/Care Centre (Qlik lines 568-599)
-- ---------------------------------------------------------------------------
WithStringFields AS (
    SELECT
        cwa.*,
        CASE WHEN cwa.Status IN ('Verified', 'Assessed but not Verified', 'Till Verify', 'Batched for Medicare (Batch Created)')
             THEN 'Nprint' ELSE 'Not Nprint' END                               AS [For Daily Nprint],
        CONCAT(cwa.[Claim ID], cwa.[Claim Line])                                AS [Claim ID/Line ID String],
        -- Qlik line 588 has a trailing space in 'Jaide Vanneste ' (a source typo). Qlik's
        -- match() is an exact string comparison, so that entry never matches [Final Operator]
        -- (which never carries a trailing space) -- Jaide Vanneste is always 'Care Centres' in
        -- the original Qlik output. T-SQL's default comparison ignores trailing spaces (ANSI
        -- blank-padding), so a plain IN(...) here would make that entry match and silently flip
        -- her classification. COLLATE ...BIN2 restores space-significant (and case-sensitive)
        -- comparison so this list behaves exactly as it does in Qlik, trailing space included.
        CASE WHEN cwa.[Final Operator] COLLATE Latin1_General_BIN2 IN (
                'Sharp Verify','Rebecca Christie','Natalie Howard','Margaret Slaven','Kasandra Anthes',
                'Jazmin Melnyk','Glenice Sharp','Glenda Winterbottom','Elizabeth Burnes','Dianne Garland',
                'Leanne Hawley','Lynn Green','Ashley Drury','Jodie Blackley','Brain Groups','Amanda Pearce',
                'Jaide Vanneste ','Mikayla Newcombe','Rachel Nelson','Jacqueline Page','Kallan Phillips',
                'Madeline Spice','Amanda Robertson'
             ) THEN 'Head Office' ELSE 'Care Centres' END                      AS [HO/Care Centre]
    FROM ClaimsWithAdjustments AS cwa
),

-- ---------------------------------------------------------------------------
-- Stage 16: Branch / Operator Branch (Qlik lines 612-624)
-- ---------------------------------------------------------------------------
-- Qlik line 614: ApplyMap('OperatorMapping',[Final Operator]) has NO default argument.
-- Qlik's ApplyMap with no default returns the lookup key itself (not NULL) on a miss.
-- [Final Operator] = CONCAT(first_name,' ',surname), both VARCHAR(40) => up to 81 chars;
-- VARCHAR(81) avoids silently truncating that fallback value (ISNULL's return type follows
-- its first argument's type/length).
WithBranch AS (
    SELECT
        wsf.*,
        ISNULL(CAST(op.branch_group_id AS VARCHAR(81)), wsf.[Final Operator])  AS [Branch]
    FROM WithStringFields AS wsf
    LEFT JOIN dbo.operator AS op
        ON CONCAT(op.first_name, ' ', op.surname) = wsf.[Final Operator]
),
-- [Branch] can hold either a numeric branch_group_id (as text) or, on an ApplyMap miss, an
-- operator's full name string. Cast the grouping side to match rather than the reverse, to
-- avoid SQL Server attempting (and failing) an implicit string->numeric conversion.
WithOperatorBranch AS (
    SELECT
        wb.*,
        -- COALESCE, not ISNULL -- same truncation risk as [ClaimChannel] above if
        -- grouping.description is narrower than the 18-char default literal.
        COALESCE(g.description, 'No Assigned Branch')                          AS [Operator Branch]
    FROM WithBranch AS wb
    LEFT JOIN dbo.grouping AS g
        ON CAST(g.group_id AS VARCHAR(81)) = wb.[Branch]
)

-- ---------------------------------------------------------------------------
-- Stage 17: Audit -- For Audit flag (Qlik lines 626-636)
-- ---------------------------------------------------------------------------
SELECT
    wob.*,
    CASE
        WHEN wob.MaxStatus NOT IN ('Verified', 'Assessed but not Verified', 'Till Verify', 'Batched for Medicare (Batch Created)') OR wob.MaxStatus IS NULL
            THEN 'Not Records'
        WHEN wob.MaxStatus = 'Cancelled'
            THEN 'Not Records'
        WHEN wob.[Provider Number] = 'SUNGLASS'
            THEN 'Not Records'
        WHEN ISNULL(wob.claim_type, '') <> 'Hospital' AND ISNULL(wob.[Provider Number], '') <> 'TRAVEL'
            THEN 'Not Records'
        WHEN wob.[Final Operator] IN ('Amanda Pearce', 'Dianne Garland', 'Madeline Spice', 'Kallan Phillips')
            THEN 'Not Records'
        WHEN wob.[Final Operator] IN ('Kasandra Anthes', 'Rachel Nelson') AND wob.fee > 0.00
            THEN 'Not Records'
        ELSE 'Records'
    END                                                                        AS [For Audit]
FROM WithOperatorBranch AS wob;

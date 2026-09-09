
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Part 1: materialise Final into #Claims_Final_Snapshot
-- ---------------------------------------------------------------------------

DECLARE @vStartDate DATE = DATEADD(MONTH, -13, DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1));
DECLARE @vToday DATE = CAST(GETDATE() AS DATE);

WITH

ClaimStatusMain AS (
    SELECT
        cs.claim_id                                                            AS [Claim ID],
        ISNULL(CAST(c_mem.membership_id AS VARCHAR(20)), 'no member')          AS [Membership ID],
        cs.claim_status_version,
        ISNULL(cst.description, 'MISSING')                                     AS Status,
        CAST(cs.status_date AS DATE)                                           AS [Date],
        CASE
            WHEN ISNULL(cst.description, 'MISSING') IN ('Manually Verified', 'Verified') THEN CAST(cs.status_date AS DATE) END AS [Verified Status Date],
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
        CAST(NULL AS DATETIME)                                                 AS status_date,
        CAST(NULL AS CHAR(16))                                                 AS create_operator
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
        CAST(NULL AS VARCHAR(20))                                              AS [Membership ID],
        pcs.claim_status_version,
        ISNULL(pcst.description, 'Missing')                                    AS Status,
        CAST(pcs.status_date AS DATE)                                          AS [Date],
        CASE WHEN ISNULL(pcst.description, 'MISSING') LIKE '%Sent to Medicare%' THEN CAST(pcs.status_date AS DATE) END AS [Verified Status Date],
        CASE
            WHEN pcs.update_operator LIKE '%-%' THEN 'ECLAIMS'
            ELSE pcs.update_operator
        END                                                                    AS [update_operator],
        CASE
            WHEN ISNULL(pcst.description, 'MISSING') = 'Verified'
                THEN pcs.update_operator
            ELSE pcs.create_operator
        END                                                                    AS [Claim Operator],
        pcs.status_date,
        pcs.create_operator
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
        ISNULL(cst.description, 'MISSING')                                     AS AssessedStatus
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
        ac.AssessedStatus,
        CASE WHEN cu.[Membership ID] IS NULL THEN NULL ELSE 'x' END AS _dummy
    FROM ClaimsUnion AS cu
    LEFT JOIN VerifiedClaims AS vc
        ON vc.[Claim ID] = cu.[Claim ID]
       AND vc.[Membership ID] = cu.[Membership ID]
       AND vc.[Verified Status Date] = cu.[Verified Status Date]
    LEFT JOIN AssessedClaims AS ac
        ON ac.[Claim ID] = cu.[Claim ID]
       AND ac.[Membership ID] = cu.[Membership ID]
),
ClaimsWithOperators3 AS (
    SELECT
        co.*,
        CASE WHEN co.Status IN ('Verified', 'Cancelled', 'Assessed but not Verified')
             THEN CASE WHEN op_final.oper_name IS NULL THEN NULL
                       ELSE CONCAT(op_final.first_name, ' ', op_final.surname) END
        END                                                                    AS [Final Operator]
    FROM ClaimsWithOperators AS co
    LEFT JOIN dbo.operator AS op_final
        ON op_final.oper_name = co.[update_operator]
),

MaxStatusProvider AS (
    SELECT DISTINCT
        mg.provider_claim_id                                                   AS [Claim ID],
        pt.description                                                         AS MaxClaimStatusProvider,
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

MaxStatusOther AS (
    SELECT DISTINCT
        mg.claim_id                                                            AS [Claim ID],
        pt.description                                                         AS MaxClaimStatusOther,
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

GenHospBucket AS (
    SELECT
        ca.claim_id                                                            AS [Claim ID],
        CASE WHEN ISNULL(bt.claim_type_flag, 'Missing') = 'H' THEN 'Hospital' ELSE 'General' END AS [Gen/Hosp Bucket Type],
        CASE WHEN ca.claim_alloc_reason_id = 1 THEN 'Bucket claims' ELSE 'Allocated Claims' END AS [Gen/Hosp Bucket Claims],
        CAST(ca.create_datetime AS DATE)                                       AS [Gen/Hosp Bucket Claims Lodge Date]
    FROM dbo.claim_alloc AS ca
    LEFT JOIN (
        SELECT claim_id, MIN(claim_type_flag) AS claim_type_flag
        FROM dbo.claim
        WHERE create_datetime > @vStartDate
        GROUP BY claim_id
    ) AS bt
        ON bt.claim_id = ca.claim_id
    WHERE ca.create_datetime > @vStartDate
),

ProviderBucket AS (
    SELECT
        pca.provider_claim_id                                                  AS [Claim ID],
        'Medical'                                                              AS [Provider Bucket Type],
        CASE WHEN pca.claim_alloc_reason_id = 2 THEN 'Bucket claims' ELSE 'Allocated Claims' END AS [Provider Bucket Claims],
        CAST(pca.create_datetime AS DATE)                                      AS [Provider Bucket Claims Lodge Date]
    FROM dbo.provider_claim_alloc AS pca
    WHERE pca.create_datetime > @vStartDate
),

BringTogether AS (
    SELECT
        co3.*,
        ISNULL(ghb.[Gen/Hosp Bucket Type], pb.[Provider Bucket Type])          AS [Bucket Type],
        ISNULL(ghb.[Gen/Hosp Bucket Claims], pb.[Provider Bucket Claims])      AS [Bucket Claims],
        ISNULL(ghb.[Gen/Hosp Bucket Claims Lodge Date], pb.[Provider Bucket Claims Lodge Date]) AS [Bucket Claims Lodge Date],
        ISNULL(msp.MaxClaimStatusProvider, mso.MaxClaimStatusOther)            AS MaxStatus
    FROM ClaimsWithOperators3 AS co3
    LEFT JOIN GenHospBucket AS ghb
        ON ghb.[Claim ID] = co3.[Claim ID]
    LEFT JOIN ProviderBucket AS pb
        ON pb.[Claim ID] = co3.[Claim ID]
    LEFT JOIN MaxStatusProvider AS msp
        ON msp.[Claim ID] = co3.[Claim ID]
    LEFT JOIN MaxStatusOther AS mso
        ON mso.[Claim ID] = co3.[Claim ID]
),

ClaimTypeOnly AS (
    SELECT DISTINCT
        cd.claim_id                                                            AS [Claim ID],
        cd.claim_type
    FROM dbo.ClaimDetailGenAndHosp AS cd
    INNER JOIN dbo.ClaimDetailsAtService AS cs
        ON cd.claim_id = cs.claim_id AND cd.claim_line_id = cs.claim_line_id
    WHERE cd.status_date > @vStartDate
),

Final AS (
    SELECT
        bt.[Claim ID],
        bt.Status,
        bt.[Date],
        bt.[Final Operator],
        bt.[Claim Operator],
        bt.[Bucket Type],
        bt.[Bucket Claims],
        bt.MaxStatus,
        cto.claim_type,
        DATEDIFF(DAY, bt.[Bucket Claims Lodge Date], bt.[Verified Status Date])
            - (DATEDIFF(WEEK, bt.[Bucket Claims Lodge Date], bt.[Verified Status Date]) * 2)
            - (CASE WHEN DATEDIFF(DAY, '1900-01-01', bt.[Bucket Claims Lodge Date]) % 7 = 6 THEN 1 ELSE 0 END)
            - (CASE WHEN DATEDIFF(DAY, '1900-01-01', bt.[Verified Status Date]) % 7 = 5 THEN 1 ELSE 0 END)
            + 1                                                                AS [Days to Verify Claim]
    FROM BringTogether AS bt
    LEFT JOIN ClaimTypeOnly AS cto
        ON cto.[Claim ID] = bt.[Claim ID]
)

SELECT DISTINCT *
INTO #Claims_Final_Snapshot
FROM Final;

-- SELECT * FROM #Claims_Final_Snapshot

-- ---------------------------------------------------------------------------
-- Part 2: below read from temptable #Claims_Final_Snapshot
-- ---------------------------------------------------------------------------

SELECT
    (SELECT COUNT(DISTINCT [Claim ID]) FROM #Claims_Final_Snapshot WHERE [Bucket Claims] = 'Bucket claims' AND [Bucket Type] = 'Hospital')
  + (SELECT COUNT(DISTINCT [Claim ID]) FROM #Claims_Final_Snapshot WHERE [Bucket Claims] = 'Bucket claims' AND [Bucket Type] = 'General')
  + (SELECT COUNT(DISTINCT [Claim ID]) FROM #Claims_Final_Snapshot WHERE MaxStatus IN ('Received','Received and Checked') AND [Bucket Type] = 'Medical')
                                                                                 AS [Total Claims in the Bucket],

    (SELECT COUNT(DISTINCT [Claim ID]) FROM #Claims_Final_Snapshot WHERE MaxStatus IN ('Received','Received and Checked') AND [Bucket Type] = 'Medical')
                                                                                 AS [Medical Claims in the Bucket],

    (SELECT COUNT(DISTINCT [Claim ID]) FROM #Claims_Final_Snapshot WHERE [Bucket Claims] = 'Bucket claims' AND [Bucket Type] = 'Hospital')
                                                                                 AS [Hospital Claims in the Bucket],

    (SELECT COUNT(DISTINCT [Claim ID]) FROM #Claims_Final_Snapshot WHERE [Bucket Claims] = 'Bucket claims' AND [Bucket Type] = 'General')
                                                                                 AS [General Claims in the Bucket],

    (SELECT MIN([Date]) FROM #Claims_Final_Snapshot WHERE MaxStatus IN ('Received','Received and Checked') AND [Bucket Type] = 'Medical')
                                                                                 AS [Date (Medical)],

    (SELECT MIN([Date]) FROM #Claims_Final_Snapshot WHERE [Bucket Claims] = 'Bucket claims' AND [Bucket Type] = 'Hospital')
                                                                                 AS [Date (Hospital)],

    (SELECT MIN([Date]) FROM #Claims_Final_Snapshot WHERE [Bucket Claims] = 'Bucket claims' AND [Bucket Type] = 'General')
                                                                                 AS [Date (General)],

    (SELECT AVG([Days to Verify Claim]) FROM #Claims_Final_Snapshot WHERE claim_type = 'Medical')
                                                                                 AS [Avg Days Til Verified (Medical)],

    (SELECT AVG([Days to Verify Claim]) FROM #Claims_Final_Snapshot WHERE claim_type = 'Hospital')
                                                                                 AS [Avg Days Til Verified (Hospital)],

    (SELECT AVG([Days to Verify Claim]) FROM #Claims_Final_Snapshot WHERE claim_type = 'General')
                                                                                 AS [Avg Days Til Verified (General)],

    (SELECT COUNT(DISTINCT [Claim ID]) FROM #Claims_Final_Snapshot
     WHERE [Bucket Type] = 'Medical'
       AND Status NOT LIKE '%Paid%' AND Status NOT LIKE '%Cancelled%' AND Status NOT LIKE '%Verified%'
       AND Status NOT LIKE '%Assessed but not Verified%' AND Status NOT LIKE '%Till Verify%' AND Status NOT LIKE 'Quot%')
                                                                                 AS [Claims Added to Bucket - Medical],

    (SELECT COUNT(DISTINCT [Claim ID]) FROM #Claims_Final_Snapshot WHERE Status = 'Received and Logged' AND [Bucket Type] = 'Hospital')
                                                                                 AS [Claims Added to Bucket - Hospital],

    (SELECT COUNT(DISTINCT [Claim ID]) FROM #Claims_Final_Snapshot WHERE Status = 'Received and Logged' AND [Bucket Type] = 'General')
                                                                                 AS [General Claims Logged],

    (SELECT COUNT(DISTINCT [Claim ID]) FROM #Claims_Final_Snapshot
     WHERE Status IN ('Verified','Assessed but not Verified','Till Verify')
       AND ([Final Operator] NOT IN ('HICAPS','IBA','WEB','Web/Mobile Claim','System Account') OR [Final Operator] IS NULL)
       AND claim_type = 'Medical')
                                                                                 AS [Medical Claims Processed],

    (SELECT COUNT(DISTINCT [Claim ID]) FROM #Claims_Final_Snapshot
     WHERE Status IN ('Verified','Assessed but not Verified','Till Verify')
       AND ([Final Operator] NOT IN ('HICAPS','IBA','WEB','Web/Mobile Claim','System Account') OR [Final Operator] IS NULL)
       AND [Bucket Type] = 'General')
                                                                                 AS [General Claims Processed],

    (SELECT COUNT(DISTINCT [Claim ID]) FROM #Claims_Final_Snapshot
     WHERE Status IN ('Verified','Assessed but not Verified','Till Verify')
       AND ([Claim Operator] NOT IN ('HICAPS','System Account','IBA','ECLIPSE','Web/Mobile Claims','WEB') OR [Claim Operator] IS NULL)
       AND claim_type = 'Hospital')
                                                                                 AS [Processed excl. Electronic];

-- Not dropping #Claims_Final_Snapshot here on purpose -- it disappears
-- automatically when this session/window ends. If you want to rebuild it
-- mid-session, run DROP TABLE #Claims_Final_Snapshot; first, then re-run
-- Part 1 above.

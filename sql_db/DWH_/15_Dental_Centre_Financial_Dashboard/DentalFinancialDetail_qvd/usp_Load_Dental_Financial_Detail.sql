USE SILVER;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Load_Dental_Financial_Detail
AS
BEGIN
    SET NOCOUNT ON;

    TRUNCATE TABLE SILVER.dbo.Dental_Financial_Detail;

    WITH Journals_Actual AS (
        SELECT
            RTRIM(p.ACCTID)                                                  AS ACCTID,
            CAST(
                LEFT(CAST(p.AUDTDATE AS VARCHAR(8)), 4) + '-' +
                SUBSTRING(CAST(p.AUDTDATE AS VARCHAR(8)), 5, 2) + '-' +
                SUBSTRING(CAST(p.AUDTDATE AS VARCHAR(8)), 7, 2) + ' ' +
                LEFT(RIGHT('00000000' + CAST(p.AUDTTIME AS VARCHAR(20)), 8), 2) + ':' +
                SUBSTRING(RIGHT('00000000' + CAST(p.AUDTTIME AS VARCHAR(20)), 8), 3, 2) + ':' +
                SUBSTRING(RIGHT('00000000' + CAST(p.AUDTTIME AS VARCHAR(20)), 8), 5, 2) + '.' +
                SUBSTRING(RIGHT('00000000' + CAST(p.AUDTTIME AS VARCHAR(20)), 8), 7, 2)
            AS DATETIME2)                                                     AS Create_Date,
            RTRIM(p.AUDTUSER)                                                 AS Create_User,
            CAST(
                LEFT(CAST(p.JRNLDATE AS VARCHAR(8)), 4) + '-' +
                SUBSTRING(CAST(p.JRNLDATE AS VARCHAR(8)), 5, 2) + '-' +
                SUBSTRING(CAST(p.JRNLDATE AS VARCHAR(8)), 7, 2)
            AS DATE)                                                           AS Post_Date,
            CAST(p.FISCALYR AS INT) * 100 + CAST(p.FISCALPERD AS INT)         AS Period,
            p.POSTINGSEQ                                                     AS Journal_ID,
            RTRIM(p.JNLDTLDESC)                                               AS Journal_Detail,
            p.TRANSAMT * -1                                                  AS Amount,
            p.TRANSQTY                                                       AS Quantity,
            RTRIM(p.JNLDTLREF)                                                AS Journal_Ref,
            CAST(p.FISCALYR AS INT)                                          AS Fin_Year,
            CAST(p.FISCALPERD AS INT)                                        AS Fin_Period,
            CASE p.FISCALPERD
                WHEN '01' THEN 7  WHEN '02' THEN 8  WHEN '03' THEN 9
                WHEN '04' THEN 10 WHEN '05' THEN 11 WHEN '06' THEN 12
                WHEN '07' THEN 1  WHEN '08' THEN 2  WHEN '09' THEN 3
                WHEN '10' THEN 4  WHEN '11' THEN 5  WHEN '12' THEN 6
            END                                                               AS [Month],
            'Actual'                                                          AS Source,
            CAST(NULL AS VARCHAR(1))                                          AS Budget_Version
        FROM BRONZE.sag.GLPOST p
        INNER JOIN BRONZE.sag.GLAMF a ON a.ACCTID = p.ACCTID
        WHERE p.FISCALPERD <= '12'
          AND a.ACCTTYPE = 'I'
    ),
    Journals_Budget AS (
        SELECT
            RTRIM(ACCTID)                                                    AS ACCTID,
            RTRIM(FSCSDSG)                                                   AS Budget_Version,
            CAST(FSCSYR AS INT)                                              AS Fin_Year,
            CASE PeriodCol
                WHEN 'NETPERD1' THEN 1   WHEN 'NETPERD2' THEN 2   WHEN 'NETPERD3' THEN 3
                WHEN 'NETPERD4' THEN 4   WHEN 'NETPERD5' THEN 5   WHEN 'NETPERD6' THEN 6
                WHEN 'NETPERD7' THEN 7   WHEN 'NETPERD8' THEN 8   WHEN 'NETPERD9' THEN 9
                WHEN 'NETPERD10' THEN 10 WHEN 'NETPERD11' THEN 11 WHEN 'NETPERD12' THEN 12
            END                                                               AS Fin_Period,
            CAST(FSCSYR AS INT) * 100 +
            CASE PeriodCol
                WHEN 'NETPERD1' THEN 1   WHEN 'NETPERD2' THEN 2   WHEN 'NETPERD3' THEN 3
                WHEN 'NETPERD4' THEN 4   WHEN 'NETPERD5' THEN 5   WHEN 'NETPERD6' THEN 6
                WHEN 'NETPERD7' THEN 7   WHEN 'NETPERD8' THEN 8   WHEN 'NETPERD9' THEN 9
                WHEN 'NETPERD10' THEN 10 WHEN 'NETPERD11' THEN 11 WHEN 'NETPERD12' THEN 12
            END                                                               AS Period,
            BudgetAmt * -1                                                   AS Amount,
            CASE
                WHEN PeriodCol IN ('NETPERD7','NETPERD8','NETPERD9','NETPERD10','NETPERD11','NETPERD12')
                THEN CASE PeriodCol
                        WHEN 'NETPERD7' THEN 1 WHEN 'NETPERD8' THEN 2 WHEN 'NETPERD9' THEN 3
                        WHEN 'NETPERD10' THEN 4 WHEN 'NETPERD11' THEN 5 WHEN 'NETPERD12' THEN 6
                     END
                ELSE CASE PeriodCol
                        WHEN 'NETPERD1' THEN 7 WHEN 'NETPERD2' THEN 8 WHEN 'NETPERD3' THEN 9
                        WHEN 'NETPERD4' THEN 10 WHEN 'NETPERD5' THEN 11 WHEN 'NETPERD6' THEN 12
                     END
            END                                                               AS [Month],
            'Budget'                                                          AS Source
        FROM BRONZE.sag.GLAFS
        UNPIVOT (BudgetAmt FOR PeriodCol IN
            (NETPERD1, NETPERD2, NETPERD3, NETPERD4, NETPERD5, NETPERD6,
             NETPERD7, NETPERD8, NETPERD9, NETPERD10, NETPERD11, NETPERD12)
        ) AS unpvt
        WHERE ACTIVITYSW = 1
    ),
    Journals AS (
        SELECT
            ACCTID, Create_Date, Create_User, Post_Date, Period, Journal_ID,
            Journal_Detail, Amount, Quantity, Journal_Ref, Fin_Year, Fin_Period,
            [Month], Source, Budget_Version
        FROM Journals_Actual
        UNION ALL
        SELECT
            ACCTID,
            CAST(NULL AS DATETIME2)    AS Create_Date,
            CAST(NULL AS VARCHAR(8))   AS Create_User,
            CAST(NULL AS DATE)         AS Post_Date,
            Period,
            CAST(NULL AS DECIMAL(18,0)) AS Journal_ID,
            CAST(NULL AS VARCHAR(60))  AS Journal_Detail,
            Amount,
            CAST(NULL AS DECIMAL(18,0)) AS Quantity,
            CAST(NULL AS VARCHAR(60))  AS Journal_Ref,
            Fin_Year, Fin_Period,
            [Month], Source, Budget_Version
        FROM Journals_Budget
    ),
    GLStructure_Dental AS (
        SELECT
            RTRIM(am.ACCTID)                                                 AS ACCTID,
            RTRIM(am.ACCTFMTTD)                                              AS Account_Display,
            RTRIM(am.ACCTDESC)                                               AS Account_Name,
            RTRIM(am.ACSEGVAL05)                                             AS Loc_Code,
            RTRIM(branch_map.SEGVALDESC)                                     AS Branch,
            RTRIM(am.ACSEGVAL01)                                             AS Account_Num
        FROM BRONZE.sag.GLAMF am
        INNER JOIN BRONZE.sag.GLASV division_map
            ON division_map.IDSEG = '000003'
           AND division_map.SEGVAL = am.ACSEGVAL03
        LEFT JOIN BRONZE.sag.GLASV branch_map
            ON branch_map.IDSEG = '000005'
           AND branch_map.SEGVAL = am.ACSEGVAL05
        WHERE division_map.SEGVALDESC = 'Dental'
    )
    INSERT INTO SILVER.dbo.Dental_Financial_Detail (
        ACCTID, Create_Date, Create_User, Post_Date, Period, Journal_ID,
        Journal_Detail, Amount, Quantity, Journal_Ref, Fin_Year, Fin_Period,
        [Month], Source, Budget_Version, Account_Display, Account_Name,
        Loc_Code, Branch, Account_Num
    )
    SELECT
        j.ACCTID, j.Create_Date, j.Create_User, j.Post_Date, j.Period, j.Journal_ID,
        j.Journal_Detail, j.Amount, j.Quantity, j.Journal_Ref, j.Fin_Year, j.Fin_Period,
        j.[Month], j.Source, j.Budget_Version,
        g.Account_Display, g.Account_Name, g.Loc_Code, g.Branch, g.Account_Num
    FROM Journals j
    INNER JOIN GLStructure_Dental g ON g.ACCTID = j.ACCTID;

END;
GO

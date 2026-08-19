-- Validation: compare two memship_YYYYMMDD snapshots in BRONZE and apply the
-- movement rules (Join / Rejoin / Termination) between them.
-- Pure query, no writes, no stored procedure — just to prove the table-discovery
-- and comparison logic works before it gets wrapped into a SP.
--
-- Usage:
--   Leave @ManualToday / @ManualYday as NULL  -> auto-picks the latest two
--     memship_YYYYMMDD tables that exist in BRONZE.
--   Set @ManualToday / @ManualYday to specific dates ('YYYYMMDD' or 'YYYY-MM-DD')
--     -> compares exactly those two snapshots instead (they don't need to be
--        adjacent calendar days, just two existing snapshot tables).

DECLARE @ManualToday DATE = NULL;   -- e.g. '2026-08-14'
DECLARE @ManualYday  DATE = NULL;   -- e.g. '2026-08-13'

DECLARE @RunDate         DATE;
DECLARE @PreSnapshotDate DATE;
DECLARE @TodayTable      SYSNAME;
DECLARE @YdayTable       SYSNAME;
DECLARE @SQL             NVARCHAR(MAX);

DROP TABLE IF EXISTS #snapshot_tables;

SELECT
    t.name AS table_name,
    TRY_CONVERT(DATE, RIGHT(t.name, 8), 112) AS snapshot_date
INTO #snapshot_tables
FROM sys.tables t
WHERE t.name LIKE 'memship\_________' ESCAPE '\'   -- memship_ + 8 digits
  AND TRY_CONVERT(DATE, RIGHT(t.name, 8), 112) IS NOT NULL;

IF @ManualToday IS NOT NULL AND @ManualYday IS NOT NULL
BEGIN
    -- Manual mode: use the two dates supplied above
    SELECT @TodayTable = table_name, @RunDate = snapshot_date
    FROM #snapshot_tables WHERE snapshot_date = @ManualToday;

    SELECT @YdayTable = table_name, @PreSnapshotDate = snapshot_date
    FROM #snapshot_tables WHERE snapshot_date = @ManualYday;

    IF @TodayTable IS NULL OR @YdayTable IS NULL
    BEGIN
        RAISERROR('One or both manual snapshot dates do not have a matching memship_YYYYMMDD table.', 16, 1);
        RETURN;
    END
END
ELSE
BEGIN
    -- Auto mode: pick the latest two available snapshots
    DROP TABLE IF EXISTS #latest_two;

    SELECT TOP 2
        table_name,
        snapshot_date,
        ROW_NUMBER() OVER (ORDER BY snapshot_date DESC) AS rn
    INTO #latest_two
    FROM #snapshot_tables
    ORDER BY snapshot_date DESC;

    SELECT @TodayTable = table_name, @RunDate = snapshot_date FROM #latest_two WHERE rn = 1;
    SELECT @YdayTable  = table_name, @PreSnapshotDate = snapshot_date FROM #latest_two WHERE rn = 2;

    DROP TABLE IF EXISTS #latest_two;
END

PRINT 'Today table: ' + @TodayTable + '  (run_date = ' + CONVERT(VARCHAR(10), @RunDate, 23) + ')';
PRINT 'Yday table:  ' + @YdayTable  + '  (pre_snapshot_date = ' + CONVERT(VARCHAR(10), @PreSnapshotDate, 23) + ')';

-- Build and run the comparison dynamically against whichever two tables were resolved above
SET @SQL = N'
SELECT
    ''' + CONVERT(VARCHAR(10), @RunDate, 23) + N''' AS run_date,
    ''' + CONVERT(VARCHAR(10), @PreSnapshotDate, 23) + N''' AS pre_snapshot_date,
    ''Join'' AS movement_type,
    today.membership_id,
    NULL AS status_yday,
    today.memship_status AS status_today,
    today.effective_join_date,
    today.effective_rejoin_date,
    today.effective_termination_date
FROM BRONZE.dbo.' + QUOTENAME(@TodayTable) + N' today
LEFT JOIN BRONZE.dbo.' + QUOTENAME(@YdayTable) + N' yday
    ON yday.membership_id = today.membership_id
WHERE yday.membership_id IS NULL

UNION ALL

SELECT
    ''' + CONVERT(VARCHAR(10), @RunDate, 23) + N''',
    ''' + CONVERT(VARCHAR(10), @PreSnapshotDate, 23) + N''',
    ''Rejoin'',
    today.membership_id,
    yday.memship_status,
    today.memship_status,
    today.effective_join_date,
    today.effective_rejoin_date,
    today.effective_termination_date
FROM BRONZE.dbo.' + QUOTENAME(@TodayTable) + N' today
JOIN BRONZE.dbo.' + QUOTENAME(@YdayTable) + N' yday
    ON yday.membership_id = today.membership_id
WHERE yday.memship_status = ''T''
  AND today.memship_status = ''A''

UNION ALL

SELECT
    ''' + CONVERT(VARCHAR(10), @RunDate, 23) + N''',
    ''' + CONVERT(VARCHAR(10), @PreSnapshotDate, 23) + N''',
    ''Termination'',
    today.membership_id,
    yday.memship_status,
    today.memship_status,
    today.effective_join_date,
    today.effective_rejoin_date,
    today.effective_termination_date
FROM BRONZE.dbo.' + QUOTENAME(@TodayTable) + N' today
JOIN BRONZE.dbo.' + QUOTENAME(@YdayTable) + N' yday
    ON yday.membership_id = today.membership_id
WHERE yday.memship_status = ''A''
  AND today.memship_status = ''T''

ORDER BY movement_type, membership_id;
';

EXEC sp_executesql @SQL;

DROP TABLE IF EXISTS #snapshot_tables;

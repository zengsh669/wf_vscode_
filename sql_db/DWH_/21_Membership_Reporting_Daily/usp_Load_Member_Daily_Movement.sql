USE [SILVER]
GO

/****** Object:  StoredProcedure [dbo].[usp_Load_Member_Daily_Movement] ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[usp_Load_Member_Daily_Movement]
	-- Optional: force a specific pair of snapshot dates instead of auto-picking
	-- the latest two memship_YYYYMMDD tables in BRONZE. Useful for backfilling.
	@ManualToday DATE = NULL,
	@ManualYday  DATE = NULL
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @RunDate         DATE;
	DECLARE @PreSnapshotDate DATE;
	DECLARE @TodayTable      SYSNAME;
	DECLARE @YdayTable       SYSNAME;
	DECLARE @SQL             NVARCHAR(MAX);
	DECLARE @ProductFilter   NVARCHAR(MAX);
	DECLARE @ProductInfoColumn NVARCHAR(MAX);

	DROP TABLE IF EXISTS #snapshot_tables;

	SELECT
		t.name AS table_name,
		TRY_CONVERT(DATE, RIGHT(t.name, 8), 112) AS snapshot_date
	INTO #snapshot_tables
	FROM BRONZE.sys.tables t
	WHERE t.name LIKE 'memship\_________' ESCAPE '\'
	  AND TRY_CONVERT(DATE, RIGHT(t.name, 8), 112) IS NOT NULL;

	IF @ManualToday IS NOT NULL AND @ManualYday IS NOT NULL
	BEGIN
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

	-- Idempotency guard: if this run_date has already been loaded, skip instead of
	-- inserting duplicate movement rows (protects against accidental re-runs/retries).
	IF EXISTS (SELECT 1 FROM SILVER.dbo.Member_Daily_Movement WHERE run_date = @RunDate)
	BEGIN
		PRINT 'run_date ' + CONVERT(VARCHAR(10), @RunDate, 23) + ' has already been loaded - skipping.';
		DROP TABLE IF EXISTS #snapshot_tables;
		RETURN;
	END

	PRINT 'Loading movement for run_date = ' + CONVERT(VARCHAR(10), @RunDate, 23)
		+ '  (pre_snapshot_date = ' + CONVERT(VARCHAR(10), @PreSnapshotDate, 23) + ')';

	-- Reusable product filter: keep Hospital ('H') and Extras ('A'), drop Ambulance ('B');
	-- drop Overseas product codes as advised (extended list: OSC/NZO/FCO plus OWEA/OWEB/OWSA/OWSB/OWCA/OWCB).
	-- cover_product holds one row per cover_version, and a member can have many old versions with
	-- different (and possibly overseas) products - only the latest version reflects their current
	-- product, so both this filter and the display column below restrict to MAX(cover_version).
	SET @ProductFilter = N'
	  AND EXISTS (
	        SELECT 1
	        FROM BRONZE.dbo.cover_product cp
	        JOIN BRONZE.dbo.product p ON p.product_id = cp.product_id
	        WHERE cp.membership_id = today.membership_id
	          AND cp.cover_version = (SELECT MAX(cover_version) FROM BRONZE.dbo.cover_product WHERE membership_id = cp.membership_id)
	          AND p.product_type IN (''H'', ''A'')
	          AND p.product_code NOT IN (''OSC'', ''NZO'', ''FCO'', ''OWEA'', ''OWEB'', ''OWSA'', ''OWSB'', ''OWCA'', ''OWCB'')
	      )';

	-- Display/audit column: this member's CURRENT (latest cover_version) product_type/product_code
	-- combos, comma-separated. Uses STRING_AGG (not a JOIN) so it stays one scalar value per row.
	SET @ProductInfoColumn = N'
	    (SELECT STRING_AGG(CONCAT(p.product_type, '':'', p.product_code), '', '')
	     FROM BRONZE.dbo.cover_product cp
	     JOIN BRONZE.dbo.product p ON p.product_id = cp.product_id
	     WHERE cp.membership_id = today.membership_id
	       AND cp.cover_version = (SELECT MAX(cover_version) FROM BRONZE.dbo.cover_product WHERE membership_id = cp.membership_id)) AS product_info';

	SET @SQL = N'
	INSERT INTO SILVER.dbo.Member_Daily_Movement
	    (run_date, pre_snapshot_date, movement_type, membership_id, status_yday, status_today,
	     effective_join_date, effective_rejoin_date, effective_termination_date, product_info)
	SELECT ''' + CONVERT(VARCHAR(10), @RunDate, 23) + N''' AS run_date, ''' + CONVERT(VARCHAR(10), @PreSnapshotDate, 23) + N''' AS pre_snapshot_date,
	    ''Join'' AS movement_type, today.membership_id, NULL AS status_yday, today.memship_status AS status_today,
	    today.effective_join_date, today.effective_rejoin_date, today.effective_termination_date,' + @ProductInfoColumn + N'
	FROM BRONZE.dbo.' + QUOTENAME(@TodayTable) + N' today
	LEFT JOIN BRONZE.dbo.' + QUOTENAME(@YdayTable) + N' yday ON yday.membership_id = today.membership_id
	WHERE yday.membership_id IS NULL
	  AND today.memship_status = ''A''
	  AND LEN(CAST(today.membership_id AS VARCHAR(20))) <= 6' + @ProductFilter + N'

	UNION ALL

	SELECT ''' + CONVERT(VARCHAR(10), @RunDate, 23) + N''', ''' + CONVERT(VARCHAR(10), @PreSnapshotDate, 23) + N''',
	    ''Join'', today.membership_id, yday.memship_status, today.memship_status,
	    today.effective_join_date, today.effective_rejoin_date, today.effective_termination_date,' + @ProductInfoColumn + N'
	FROM BRONZE.dbo.' + QUOTENAME(@TodayTable) + N' today
	JOIN BRONZE.dbo.' + QUOTENAME(@YdayTable) + N' yday ON yday.membership_id = today.membership_id
	WHERE yday.memship_status = ''P''
	  AND today.memship_status = ''A''
	  AND LEN(CAST(today.membership_id AS VARCHAR(20))) <= 6' + @ProductFilter + N'

	UNION ALL

	SELECT ''' + CONVERT(VARCHAR(10), @RunDate, 23) + N''', ''' + CONVERT(VARCHAR(10), @PreSnapshotDate, 23) + N''',
	    ''Rejoin'', today.membership_id, yday.memship_status, today.memship_status,
	    today.effective_join_date, today.effective_rejoin_date, today.effective_termination_date,' + @ProductInfoColumn + N'
	FROM BRONZE.dbo.' + QUOTENAME(@TodayTable) + N' today
	JOIN BRONZE.dbo.' + QUOTENAME(@YdayTable) + N' yday ON yday.membership_id = today.membership_id
	WHERE yday.memship_status = ''T''
	  AND today.memship_status = ''A''
	  AND LEN(CAST(today.membership_id AS VARCHAR(20))) <= 6' + @ProductFilter + N'

	UNION ALL

	SELECT ''' + CONVERT(VARCHAR(10), @RunDate, 23) + N''', ''' + CONVERT(VARCHAR(10), @PreSnapshotDate, 23) + N''',
	    ''Termination'', today.membership_id, yday.memship_status, today.memship_status,
	    today.effective_join_date, today.effective_rejoin_date, today.effective_termination_date,' + @ProductInfoColumn + N'
	FROM BRONZE.dbo.' + QUOTENAME(@TodayTable) + N' today
	JOIN BRONZE.dbo.' + QUOTENAME(@YdayTable) + N' yday ON yday.membership_id = today.membership_id
	WHERE yday.memship_status = ''A''
	  AND today.memship_status = ''T''
	  AND LEN(CAST(today.membership_id AS VARCHAR(20))) <= 6' + @ProductFilter + N';';

	EXEC sp_executesql @SQL;

	PRINT CAST(@@ROWCOUNT AS VARCHAR(10)) + ' movement rows inserted for run_date = ' + CONVERT(VARCHAR(10), @RunDate, 23);

	DROP TABLE IF EXISTS #snapshot_tables;
END
GO

USE SILVER;
GO

CREATE OR ALTER PROCEDURE dbo.LoadAgentMonthlySnapshot
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TargetMonth DATE = DATEADD(MONTH, -1, DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1));

    DELETE FROM SILVER.dbo.Agent_Monthly_Snapshot WHERE SnapshotMonth = @TargetMonth;

    INSERT INTO SILVER.dbo.Agent_Monthly_Snapshot (
        [SnapshotMonth], [Agent ID], [Agent Name], [Commencement Date], [Termination Date],
        [Create Date], [create_operator], [Update Date], [update_operator]
    )
    SELECT
        @TargetMonth                           AS SnapshotMonth,
        g.group_id                             AS [Agent ID],
        g.description                          AS [Agent Name],
        CAST(g.commencement_date AS DATE)      AS [Commencement Date],
        CASE WHEN g.termination_date IS NULL THEN 'Active'
             ELSE CONVERT(VARCHAR(20), CAST(g.termination_date AS DATE), 103) END AS [Termination Date],
        CAST(g.create_datetime AS DATE)        AS [Create Date],
        g.create_operator,
        CAST(g.update_datetime AS DATE)        AS [Update Date],
        g.update_operator
    FROM BRONZE.dbo.grouping g
    WHERE
        g.group_type = 'A'
        AND g.description <> 'No Agency'
        AND (
            DATEFROMPARTS(YEAR(g.create_datetime), MONTH(g.create_datetime), 1) = @TargetMonth
            OR
            DATEFROMPARTS(YEAR(g.update_datetime), MONTH(g.update_datetime), 1) = @TargetMonth
        );

END;
GO

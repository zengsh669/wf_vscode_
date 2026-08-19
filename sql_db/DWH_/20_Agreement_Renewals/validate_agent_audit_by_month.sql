-- Agent Created/Updated in a given month — dynamic month parameter version
-- Reproduces the Power BI "Agents Updated or Added Monthly" sheet output,
-- but sourced directly from BRONZE.dbo.grouping (bypasses SILVER's current-month-only
-- AgentAudit filter, so any past month can be checked, not just the current one).

DECLARE @TargetMonth DATE = '2026-08-01';  -- <-- change this to any month's 1st (e.g. '2026-07-01')

SELECT
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
    )
ORDER BY g.group_id;

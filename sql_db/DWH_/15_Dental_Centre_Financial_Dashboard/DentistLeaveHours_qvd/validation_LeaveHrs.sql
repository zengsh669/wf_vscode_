-- DentistLeaveHours reconstruction — LeaveHrs branch only (validated)
-- Status: VALIDATED — checked against two employees' actual leave records, both matched.
-- Ready to share with Monique for business review.
--
-- Source: ConnX.dbo.q2vEmployeeLeaveHistory (leave transactions)
-- Cost Centre / Default Cost Account Description: sourced from q2vHREmployee_Position,
-- matched to the employee's position held AT THE TIME of the payroll run date
-- (Date_Held_From/Date_Held_To range match — NOT "current position"), since Qlik's own
-- Default Cost Account Description is per-employee, and this range match reduced NULLs
-- from 4,411 to 545 out of 22,842 rows versus a "current position only" match.
--
-- Dentist filter: pos.Role_Name IN (...) — NOT YET CONFIRMED BY BUSINESS.
-- This is the stronger of two candidates considered (Role_Name vs Department), based on
-- matching Qlik's exact-match source value 'Employee Dentists' more precisely than Department
-- ('Lithgow Dentists') and a more plausible team-size cross-check (5 employees vs 3).
-- See DESIGN.md "Open question: how to identify 'dentists' in ConnX" for full reasoning.

SELECT
    h.emp_code + '|' + CONVERT(VARCHAR(10), p_period.pe_date, 112)   AS [Payroll_KEY],
    h.emp_code                                                        AS [Employee ID],
    pos.Department                                                    AS [Cost Centre],
    h.hours                                                           AS [Hrs],
    h.type_desc                                                       AS [Transaction Type],
    h.reason_desc                                                     AS [Leave Reason],
    h.type_desc + '-' + h.reason_desc                                 AS [Leave_Type_Standardised],
    'LeaveHrs'                                                        AS [SourceCalc],
    pos.Department                                                    AS [Default Cost Account Description],
    p_period.pe_date                                                  AS [Payroll Run Date],
    e.emp_code                                                        AS [Employee Code],
    e.surname + ', ' + e.given_name                                   AS [Full Name]
FROM ConnX.dbo.q2vEmployeeLeaveHistory h
LEFT JOIN ConnX.dbo.q2employees e
    ON h.emp_code = e.emp_code
LEFT JOIN ConnX.dbo.q2period_end_dates p_period
    ON h.date_start BETWEEN DATEADD(DAY, -6, p_period.pe_date) AND p_period.pe_date
LEFT JOIN ConnX.dbo.q2vHREmployee_Position pos
    ON h.emp_code = pos.emp_code
    AND p_period.pe_date BETWEEN pos.Date_Held_From AND ISNULL(pos.Date_Held_To, '9999-12-31')
WHERE h.date_start >= DATEADD(YEAR, -5, GETDATE())
  AND pos.Role_Name IN ('Dentist', 'Dentist Casual', 'Dentist Clinical Lead', 'Associate Clinical Dentist Lead')

ORDER BY [Full Name], [Payroll Run Date] DESC;

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
-- Dentist filter: NOT APPLIED (commented out below, deliberately). Returning all employees'
-- leave records so Monique can confirm which Role_Name/Department values actually represent
-- "Employee Dentists" from real data, rather than us pre-filtering on an unconfirmed guess.
-- Candidate filter, for reference: pos.Role_Name IN ('Dentist', 'Dentist Casual',
-- 'Dentist Clinical Lead', 'Associate Clinical Dentist Lead') — see DESIGN.md "Open question:
-- how to identify 'dentists' in ConnX" for full reasoning.

SELECT
    h.emp_code + '|' + CONVERT(VARCHAR(10), p_period.pe_date, 112)   AS [Payroll_KEY],
    h.emp_code                                                        AS [Employee ID],
    pos.Department                                                    AS [Cost Centre],
    h.hours                                                           AS [Hrs],
    h.type_desc                                                       AS [Transaction Type],
    h.reason_desc                                                     AS [Leave Reason],
    h.type_desc + '-' + h.reason_desc                                 AS [Leave Type Standardised],
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
--   AND pos.Role_Name IN ('Dentist', 'Dentist Casual', 'Dentist Clinical Lead', 'Associate Clinical Dentist Lead')

ORDER BY [Full Name], [Payroll Run Date] DESC;

USE [GOLD]
GO

/****** Object:  View [dbo].[Membership_Reporting]    Script Date: 17/08/2026 2:20:37 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




CREATE       VIEW [dbo].[Membership_Reporting]
AS
SELECT [Run Month],
	[Run Month Num],
	CASE WHEN MONTH([Run Month]) > 6 THEN YEAR([Run Month]) + 1 ELSE YEAR([Run Month]) END AS [Fin Year],
	--CONCAT('Q',CEILING(CASE WHEN MONTH([Run Month]) > 6 THEN MONTH([Run Month]) - 6 ELSE MONTH([Run Month]) + 6 END / 3)) AS [Fin Quarter],
	LEFT(DATENAME(month,[Run Month]),3) AS [Fin Month],
	CASE WHEN MONTH([Run Month]) > 6 THEN MONTH([Run Month]) - 6 ELSE MONTH([Run Month]) + 6 END AS [Fin Month Order],
	[MembershipKey],
	[Membership Number],
	[Membership Status],
	[Product Cover],
	[Membership Cover],
	[Hosp Product Id],
	[Hospital Product],
	[Hospital Tier],
	[Hospital Status],
	[Extras Product Id],
	[Extras Product],
	[Extras Tier],
	[Extras Status],
	[Ambuln Product Id],
	[Ambuln Product],
	[Region],
	[Cover State],
	[Cover Type],
	CASE [Cover Type]
		WHEN 'Single' THEN 'Single'
		WHEN 'Couple' THEN 'Couple'
		ELSE 'Family' END AS [Cover Type Group],
	[Sales Channel],
	[Sales Channel Group],
	[Agent],
	[Promotion],
	CASE [Promotion]
		WHEN 'SAVERS24' THEN 'SAVERS24'
		WHEN 'JOIN24' THEN 'JOIN24'
		WHEN 'SKIP24' THEN 'SKIP24'
		WHEN 'THRIVE25' THEN 'THRIVE25'
		WHEN 'SWITCH25' THEN 'SWITCH25'
		WHEN 'SAVERS25' THEN 'SAVERS25'
		WHEN 'Dependants Offer' THEN 'Dependants Offer'
		WHEN 'No Promotion' THEN 'No Promotion'
		ELSE 'OTHER' END AS [Promotion Group],
	CASE [Promotion]
		WHEN 'No Promotion' THEN 'Without Promotion'
		ELSE 'With Promotion' END [Promotion Flag],
	[Date of Birth],
	[Member Age],
	[Member Age Band],
	[Tenure],
	[Tenure Order],
	[Previous Fund Id],
	[Previous Fund],
	[Join Reason],
	[Termination Code],
	[Termination Reason],
	[Transfered Fund Id],
	[Transfered Fund],
	CASE WHEN [Membership Status] IN ('A','J') THEN 1 ELSE 0 END AS [active_count],
	CASE WHEN [Membership Status] = 'J' THEN 1 ELSE 0 END AS [join_count],
	CASE WHEN [Membership Status] = 'S' THEN 1 ELSE 0 END AS [suspended_count],
	CASE WHEN [Membership Status] = 'T' THEN 1 ELSE 0 END AS [terminated_count]

FROM (SELECT CAST([Run Month] AS DATE) AS [Run Month],
	[Run Month Num],
	CONCAT(M.[Membership Number],[Product Cover],CAST([Run Month] AS DATE)) AS [MembershipKey],
	M.[Membership Number],
	CASE WHEN M.[Membership Status] = 'T' AND T.[Termination Code] IN ('4','5','7','9','H','S','W','z') THEN 'S'
		ELSE M.[Membership Status] END AS [Membership Status],
	CASE [Product Cover]
		WHEN 'PK' THEN 'Combined'
		WHEN 'HSA' THEN 'Hospital only'
		WHEN 'ESA' THEN 'Extras only'
		WHEN 'ASA' THEN 'Ambulance'
		WHEN 'OS' THEN 'Overseas'
		ELSE [Product Cover] END AS [Product Cover],
	CASE [Product Cover]
		WHEN 'PK' THEN 'Hosp/Extras'
		WHEN 'HSA' THEN 'Hosp/Extras'
		WHEN 'ESA' THEN 'Hosp/Extras'
		WHEN 'ASA' THEN 'Ambulance'
		WHEN 'OS' THEN 'Overseas'
		ELSE [Product Cover] END AS [Membership Cover],
	ISNULL([Hosp Product Id],0) AS [Hosp Product Id],
	H.[Product Cover Group] AS [Hospital Product],
	H.[Product Cover Tier] AS [Hospital Tier],
	H.[Product Status] AS [Hospital Status],
	ISNULL([Extras Product Id],0) AS [Extras Product Id],
	E.[Product Cover Group] AS [Extras Product],
	E.[Product Cover Tier] AS [Extras Tier],
	E.[Product Status] AS [Extras Status],
	ISNULL([Ambuln Product Id],0) AS [Ambuln Product Id],
	A.[Product Cover Group] AS [Ambuln Product],
	--[Branch Group Id],
	[Branch Description] AS [Region],
	[Cover State],
	[Cover Type],
	[Sales Channel],
	ISNULL([Sales Channel Group],'Other') AS [Sales Channel Group],
	[Agent],
	[Promotion],
	CAST(T.[Date of Birth] AS DATE) AS [Date of Birth],
	DATEDIFF(year, T.[Date of Birth], [Run Month]) - CASE WHEN MONTH(T.[Date of Birth]) > MONTH([Run Month]) OR (MONTH(T.[Date of Birth]) = MONTH([Run Month]) AND DAY(T.[Date of Birth]) > DAY([Run Month])) THEN 1 ELSE 0 END AS [Member Age],
	CASE WHEN DATEDIFF(year, T.[Date of Birth], [Run Month]) - CASE WHEN MONTH(T.[Date of Birth]) > MONTH([Run Month]) OR (MONTH(T.[Date of Birth]) = MONTH([Run Month]) AND DAY(T.[Date of Birth]) > DAY([Run Month])) THEN 1 ELSE 0 END < 20 THEN '15-19'
		WHEN DATEDIFF(year, T.[Date of Birth], [Run Month]) - CASE WHEN MONTH(T.[Date of Birth]) > MONTH([Run Month]) OR (MONTH(T.[Date of Birth]) = MONTH([Run Month]) AND DAY(T.[Date of Birth]) > DAY([Run Month])) THEN 1 ELSE 0 END BETWEEN 20 AND 24 THEN '20-24'
		WHEN DATEDIFF(year, T.[Date of Birth], [Run Month]) - CASE WHEN MONTH(T.[Date of Birth]) > MONTH([Run Month]) OR (MONTH(T.[Date of Birth]) = MONTH([Run Month]) AND DAY(T.[Date of Birth]) > DAY([Run Month])) THEN 1 ELSE 0 END BETWEEN 25 AND 29 THEN '25-29'
		WHEN DATEDIFF(year, T.[Date of Birth], [Run Month]) - CASE WHEN MONTH(T.[Date of Birth]) > MONTH([Run Month]) OR (MONTH(T.[Date of Birth]) = MONTH([Run Month]) AND DAY(T.[Date of Birth]) > DAY([Run Month])) THEN 1 ELSE 0 END BETWEEN 30 AND 34 THEN '30-34'
		WHEN DATEDIFF(year, T.[Date of Birth], [Run Month]) - CASE WHEN MONTH(T.[Date of Birth]) > MONTH([Run Month]) OR (MONTH(T.[Date of Birth]) = MONTH([Run Month]) AND DAY(T.[Date of Birth]) > DAY([Run Month])) THEN 1 ELSE 0 END BETWEEN 35 AND 39 THEN '35-39'
		WHEN DATEDIFF(year, T.[Date of Birth], [Run Month]) - CASE WHEN MONTH(T.[Date of Birth]) > MONTH([Run Month]) OR (MONTH(T.[Date of Birth]) = MONTH([Run Month]) AND DAY(T.[Date of Birth]) > DAY([Run Month])) THEN 1 ELSE 0 END BETWEEN 40 AND 44 THEN '40-44'
		WHEN DATEDIFF(year, T.[Date of Birth], [Run Month]) - CASE WHEN MONTH(T.[Date of Birth]) > MONTH([Run Month]) OR (MONTH(T.[Date of Birth]) = MONTH([Run Month]) AND DAY(T.[Date of Birth]) > DAY([Run Month])) THEN 1 ELSE 0 END BETWEEN 45 AND 49 THEN '45-49'
		WHEN DATEDIFF(year, T.[Date of Birth], [Run Month]) - CASE WHEN MONTH(T.[Date of Birth]) > MONTH([Run Month]) OR (MONTH(T.[Date of Birth]) = MONTH([Run Month]) AND DAY(T.[Date of Birth]) > DAY([Run Month])) THEN 1 ELSE 0 END BETWEEN 50 AND 54 THEN '50-54'
		WHEN DATEDIFF(year, T.[Date of Birth], [Run Month]) - CASE WHEN MONTH(T.[Date of Birth]) > MONTH([Run Month]) OR (MONTH(T.[Date of Birth]) = MONTH([Run Month]) AND DAY(T.[Date of Birth]) > DAY([Run Month])) THEN 1 ELSE 0 END BETWEEN 55 AND 59 THEN '55-59'
		WHEN DATEDIFF(year, T.[Date of Birth], [Run Month]) - CASE WHEN MONTH(T.[Date of Birth]) > MONTH([Run Month]) OR (MONTH(T.[Date of Birth]) = MONTH([Run Month]) AND DAY(T.[Date of Birth]) > DAY([Run Month])) THEN 1 ELSE 0 END BETWEEN 60 AND 64 THEN '60-64'
		WHEN DATEDIFF(year, T.[Date of Birth], [Run Month]) - CASE WHEN MONTH(T.[Date of Birth]) > MONTH([Run Month]) OR (MONTH(T.[Date of Birth]) = MONTH([Run Month]) AND DAY(T.[Date of Birth]) > DAY([Run Month])) THEN 1 ELSE 0 END BETWEEN 65 AND 69 THEN '65-69'
		WHEN DATEDIFF(year, T.[Date of Birth], [Run Month]) - CASE WHEN MONTH(T.[Date of Birth]) > MONTH([Run Month]) OR (MONTH(T.[Date of Birth]) = MONTH([Run Month]) AND DAY(T.[Date of Birth]) > DAY([Run Month])) THEN 1 ELSE 0 END BETWEEN 70 AND 74 THEN '70-74'
		WHEN DATEDIFF(year, T.[Date of Birth], [Run Month]) - CASE WHEN MONTH(T.[Date of Birth]) > MONTH([Run Month]) OR (MONTH(T.[Date of Birth]) = MONTH([Run Month]) AND DAY(T.[Date of Birth]) > DAY([Run Month])) THEN 1 ELSE 0 END BETWEEN 75 AND 79 THEN '75-79'
		WHEN DATEDIFF(year, T.[Date of Birth], [Run Month]) - CASE WHEN MONTH(T.[Date of Birth]) > MONTH([Run Month]) OR (MONTH(T.[Date of Birth]) = MONTH([Run Month]) AND DAY(T.[Date of Birth]) > DAY([Run Month])) THEN 1 ELSE 0 END BETWEEN 80 AND 84 THEN '80-84'
		WHEN DATEDIFF(year, T.[Date of Birth], [Run Month]) - CASE WHEN MONTH(T.[Date of Birth]) > MONTH([Run Month]) OR (MONTH(T.[Date of Birth]) = MONTH([Run Month]) AND DAY(T.[Date of Birth]) > DAY([Run Month])) THEN 1 ELSE 0 END BETWEEN 85 AND 89 THEN '85-89'
		WHEN DATEDIFF(year, T.[Date of Birth], [Run Month]) - CASE WHEN MONTH(T.[Date of Birth]) > MONTH([Run Month]) OR (MONTH(T.[Date of Birth]) = MONTH([Run Month]) AND DAY(T.[Date of Birth]) > DAY([Run Month])) THEN 1 ELSE 0 END BETWEEN 90 AND 94 THEN '90-94'
		ELSE '95+' END AS [Member Age Band],
	CASE WHEN DATEDIFF(year, [Effective Join Date], [Run Month]) < 1 THEN '<1'
		WHEN DATEDIFF(year, [Effective Join Date], [Run Month]) BETWEEN 1 AND 2 THEN '1-2'
		WHEN DATEDIFF(year, [Effective Join Date], [Run Month]) BETWEEN 3 AND 4 THEN '3-4'
		WHEN DATEDIFF(year, [Effective Join Date], [Run Month]) BETWEEN 5 AND 7 THEN '5-7'
		WHEN DATEDIFF(year, [Effective Join Date], [Run Month]) BETWEEN 8 AND 10 THEN '8-10'
		WHEN DATEDIFF(year, [Effective Join Date], [Run Month]) BETWEEN 11 AND 15 THEN '11-15'
		WHEN DATEDIFF(year, [Effective Join Date], [Run Month]) BETWEEN 16 AND 20 THEN '16-20'
		WHEN DATEDIFF(year, [Effective Join Date], [Run Month]) >= 21 THEN '21+'
		ELSE 'NA' END AS [Tenure],
	CASE WHEN DATEDIFF(year, [Effective Join Date], [Run Month]) < 1 THEN 0
		WHEN DATEDIFF(year, [Effective Join Date], [Run Month]) BETWEEN 1 AND 2 THEN 1
		WHEN DATEDIFF(year, [Effective Join Date], [Run Month]) BETWEEN 3 AND 4 THEN 3
		WHEN DATEDIFF(year, [Effective Join Date], [Run Month]) BETWEEN 5 AND 7 THEN 5
		WHEN DATEDIFF(year, [Effective Join Date], [Run Month]) BETWEEN 8 AND 10 THEN 8
		WHEN DATEDIFF(year, [Effective Join Date], [Run Month]) BETWEEN 11 AND 15 THEN 11
		WHEN DATEDIFF(year, [Effective Join Date], [Run Month]) BETWEEN 16 AND 20 THEN 16
		WHEN DATEDIFF(year, [Effective Join Date], [Run Month]) >= 21 THEN 21
		ELSE 99 END AS [Tenure Order],
	[Previous Fund Id],
	[Previous Fund Group] AS [Previous Fund],
	CASE WHEN [Previous Fund Id] = 100 THEN 'New to PHI' ELSE 'Transfer from another fund' END AS [Join Reason],
	T.[Termination Code],
	CASE WHEN M.[Membership Status] = 'T' THEN ISNULL(C.[Termination Group],'Other') END AS [Termination Reason],
	T.[Transfered Fund Id],
	CASE WHEN M.[Membership Status] = 'T' THEN ISNULL([Transfered Fund Group],'Other') END AS [Transfered Fund]

FROM [SILVER].[dbo].[Membership_Group_Key] M
LEFT JOIN [SILVER].[dbo].[Product] H ON M.[Hosp Product Id] = H.[Product Id]
LEFT JOIN [SILVER].[dbo].[Product] E ON M.[Extras Product Id] = E.[Product Id]
LEFT JOIN [SILVER].[dbo].[Product] A ON M.[Ambuln Product Id] = A.[Product Id]
--LEFT JOIN [SILVER].[dbo].[Membership_History] T ON M.[Membership Number] = T.[Membership Number] AND M.[Run Month] = T.[SnapShot Month]
LEFT JOIN [SILVER].[dbo].[Membership_History] T ON M.[Membership Number] = T.[Membership Number] AND M.[Run Month] = EOMONTH(T.[SnapShot Month], -1)
LEFT JOIN [SILVER].[dbo].[Termination_Code] C ON T.[Termination Code] = C.[Termination Code]
LEFT JOIN (SELECT [Run Month] as [Month],ROW_NUMBER() OVER (ORDER BY [Run Month] asc) as [Run Month Num]
			FROM (SELECT Distinct [Run Month] FROM [SILVER].[dbo].[Membership_Group_Key]) AS A) AS N ON N.[Month] = M.[Run Month]

-------added on 27/02/2026 exclude OVHC products
WHERE NOT EXISTS (
    SELECT 1
    FROM [BRONZE].[dbo].[group_key_full_by_branch] B
    WHERE B.membership_id = M.[Membership Number]
    AND B.hosp_product_id IN (191, 192, 193, 194, 195, 196)
    AND B.extras_product_id IS NULL
)

--------------------------------------

) AS membership_reporting;

GO

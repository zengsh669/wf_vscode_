USE [GOLD]
GO

/****** Object:  View [dbo].[vw_Membership_Retention_Rate] ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE VIEW [dbo].[vw_Membership_Retention_Rate]
AS

-- DateParams: [Run Month] is already a month-end date in Membership_Group_Key.
-- YTDate is the LATEST [Run Month] actually present in the table (not a calculated
-- calendar date), so this doesn't break if a month-end extract is delayed by a
-- weekend/public holiday. LYDate is one year before that, LLYDate two years before -
-- LLYDate/LYDate feed retention_rate_ly, the same 12-month retention calc as it
-- stood a year ago.
WITH DateParams AS (
		SELECT
			MAX([Run Month]) AS YTDate,
			DATEADD(YEAR, -1, MAX([Run Month])) AS LYDate,
			DATEADD(YEAR, -2, MAX([Run Month])) AS LLYDate
		FROM [SILVER].[dbo].[Membership_Group_Key]),

	 Base_Mem AS (
		SELECT mgk.[Run Month] AS month_end, mgk.[Membership Number] AS membership_id, mgk.[Cover Type] AS cover_type, mgk.[Cover State] AS cover_state,
		       ISNULL(mgk.[Hosp Product Id],0) AS hosp_product_id, ISNULL(mgk.[Extras Product Id],0) AS extras_product_id, ISNULL(mgk.[Ambuln Product Id],0) AS ambuln_product_id,
		       ISNULL(mgk.[Sales Channel],'Other') AS sales_channel_description, ISNULL(mgk.[Agent],'No Agency') AS agent_description,
			   CASE WHEN ISNULL(mgk.[Hosp Product Id],0) IN (10,34,65,191,192,193,194,195,196) THEN 1
			   ELSE 0 END AS ov_flag,
			   CASE WHEN ISNULL(mgk.[Ambuln Product Id],0) > 0 THEN 1
			   ELSE 0 END AS amb_flag
		FROM [SILVER].[dbo].[Membership_Group_Key] mgk
		CROSS JOIN DateParams dp
		-- Membership Status IN ('A','J') excludes the synthetic 'T' placeholder rows the
		-- load SP generates for members who dropped out of the source that month - without
		-- this, a member who has actually left could still be picked up here.
		WHERE mgk.[Run Month] = dp.LYDate
		  AND mgk.[Membership Status] IN ('A','J')
		  AND mgk.[Join Date] < mgk.[Run Month]),

	 Ret_Mem AS (
		SELECT mgk.[Membership Number] AS membership_id, ISNULL(mgk.[Hosp Product Id],0) AS curr_hosp_product_id, ISNULL(mgk.[Extras Product Id],0) AS curr_extras_product_id, ISNULL(mgk.[Ambuln Product Id],0) AS curr_ambuln_product_id,
		       1 AS active_flag
		FROM [SILVER].[dbo].[Membership_Group_Key] mgk
		CROSS JOIN DateParams dp
		WHERE mgk.[Run Month] = dp.YTDate
		  AND mgk.[Membership Status] IN ('A','J')
		  AND mgk.[Join Date] < mgk.[Run Month]),

	 Comp_Mem AS (
		SELECT bm.*,
               ISNULL(rm.active_flag,0) AS retention_flag,
	           ISNULL(rm.curr_hosp_product_id,0) AS curr_hosp_product_id, ISNULL(rm.curr_extras_product_id,0) AS curr_extras_product_id, ISNULL(rm.curr_ambuln_product_id,0) AS curr_ambuln_product_id,
	           CASE WHEN (bm.hosp_product_id + bm.extras_product_id) > 0 AND rm.curr_ambuln_product_id > 0 THEN 0 ELSE 1 END AS phi_flag,
			   CASE WHEN bm.hosp_product_id > 0 AND rm.curr_hosp_product_id > 0 THEN 1 ELSE 0 END AS hosp_flag,
			   CASE WHEN bm.extras_product_id > 0 AND rm.curr_extras_product_id > 0 THEN 1 ELSE 0 END AS extras_flag,
			   CASE WHEN bm.hosp_product_id = rm.curr_hosp_product_id THEN 1 ELSE 0  END AS hprod_retention_flag,
	           CASE WHEN bm.extras_product_id = rm.curr_extras_product_id THEN 1 ELSE 0  END AS eprod_retention_flag,
	           CASE WHEN bm.ambuln_product_id = rm.curr_ambuln_product_id THEN 1 ELSE 0  END AS a_retention_flag
		FROM Base_Mem bm
		LEFT OUTER JOIN Ret_Mem rm
			ON bm.membership_id = rm.membership_id),

	 -- Same structure as Base_Mem/Ret_Mem/Comp_Mem, shifted back one year:
	 -- base population as of LLYDate, checked for retention at LYDate.
	 Base_Mem_LY AS (
		SELECT mgk.[Run Month] AS month_end, mgk.[Membership Number] AS membership_id, mgk.[Cover Type] AS cover_type, mgk.[Cover State] AS cover_state,
		       ISNULL(mgk.[Hosp Product Id],0) AS hosp_product_id, ISNULL(mgk.[Extras Product Id],0) AS extras_product_id, ISNULL(mgk.[Ambuln Product Id],0) AS ambuln_product_id,
		       ISNULL(mgk.[Sales Channel],'Other') AS sales_channel_description, ISNULL(mgk.[Agent],'No Agency') AS agent_description,
			   CASE WHEN ISNULL(mgk.[Hosp Product Id],0) IN (10,34,65,191,192,193,194,195,196) THEN 1
			   ELSE 0 END AS ov_flag,
			   CASE WHEN ISNULL(mgk.[Ambuln Product Id],0) > 0 THEN 1
			   ELSE 0 END AS amb_flag
		FROM [SILVER].[dbo].[Membership_Group_Key] mgk
		CROSS JOIN DateParams dp
		WHERE mgk.[Run Month] = dp.LLYDate
		  AND mgk.[Membership Status] IN ('A','J')
		  AND mgk.[Join Date] < mgk.[Run Month]),

	 Ret_Mem_LY AS (
		SELECT mgk.[Membership Number] AS membership_id, ISNULL(mgk.[Hosp Product Id],0) AS curr_hosp_product_id, ISNULL(mgk.[Extras Product Id],0) AS curr_extras_product_id, ISNULL(mgk.[Ambuln Product Id],0) AS curr_ambuln_product_id,
		       1 AS active_flag
		FROM [SILVER].[dbo].[Membership_Group_Key] mgk
		CROSS JOIN DateParams dp
		WHERE mgk.[Run Month] = dp.LYDate
		  AND mgk.[Membership Status] IN ('A','J')
		  AND mgk.[Join Date] < mgk.[Run Month]),

	 Comp_Mem_LY AS (
		SELECT bm.*,
               ISNULL(rm.active_flag,0) AS retention_flag,
	           ISNULL(rm.curr_hosp_product_id,0) AS curr_hosp_product_id, ISNULL(rm.curr_extras_product_id,0) AS curr_extras_product_id, ISNULL(rm.curr_ambuln_product_id,0) AS curr_ambuln_product_id,
	           CASE WHEN (bm.hosp_product_id + bm.extras_product_id) > 0 AND rm.curr_ambuln_product_id > 0 THEN 0 ELSE 1 END AS phi_flag,
			   CASE WHEN bm.hosp_product_id > 0 AND rm.curr_hosp_product_id > 0 THEN 1 ELSE 0 END AS hosp_flag,
			   CASE WHEN bm.extras_product_id > 0 AND rm.curr_extras_product_id > 0 THEN 1 ELSE 0 END AS extras_flag,
			   CASE WHEN bm.hosp_product_id = rm.curr_hosp_product_id THEN 1 ELSE 0  END AS hprod_retention_flag,
	           CASE WHEN bm.extras_product_id = rm.curr_extras_product_id THEN 1 ELSE 0  END AS eprod_retention_flag,
	           CASE WHEN bm.ambuln_product_id = rm.curr_ambuln_product_id THEN 1 ELSE 0  END AS a_retention_flag
		FROM Base_Mem_LY bm
		LEFT OUTER JOIN Ret_Mem_LY rm
			ON bm.membership_id = rm.membership_id),

	 Current_Results AS (
		SELECT 'PHI membership' AS ret_metric, CAST( SUM(CASE WHEN phi_flag = 1 THEN retention_flag ELSE 0 END) * 1.0 / COUNT(membership_id) AS DECIMAL (18,6) ) AS retention_rate
		FROM Comp_Mem
		WHERE ov_flag = 0 AND amb_flag = 0

		UNION ALL

		SELECT 'Hospital membership' AS ret_metric, CAST( SUM(hosp_flag) * 1.0 / COUNT(membership_id) AS DECIMAL (18,6) ) AS retention_rate
		FROM Comp_Mem
		WHERE ov_flag = 0 AND amb_flag = 0 AND hosp_product_id > 0

		UNION ALL

		SELECT 'Extras membership' AS ret_metric, CAST( SUM(extras_flag) * 1.0 / COUNT(membership_id) AS DECIMAL (18,6) ) AS retention_rate
		FROM Comp_Mem
		WHERE ov_flag = 0 AND amb_flag = 0 AND extras_product_id > 0

		UNION ALL

		SELECT 'Ambulance membership' AS ret_metric, CAST( SUM(a_retention_flag) * 1.0 / COUNT(membership_id) AS DECIMAL (18,6) ) AS retention_rate
		FROM Comp_Mem
		WHERE amb_flag = 1

		UNION ALL

		SELECT 'Overseas membership' AS ret_metric, CAST( SUM(retention_flag) * 1.0 / COUNT(membership_id) AS DECIMAL (18,6) ) AS retention_rate
		FROM Comp_Mem
		WHERE ov_flag = 1),

	 LY_Results AS (
		SELECT 'PHI membership' AS ret_metric, CAST( SUM(CASE WHEN phi_flag = 1 THEN retention_flag ELSE 0 END) * 1.0 / COUNT(membership_id) AS DECIMAL (18,6) ) AS retention_rate_ly
		FROM Comp_Mem_LY
		WHERE ov_flag = 0 AND amb_flag = 0

		UNION ALL

		SELECT 'Hospital membership' AS ret_metric, CAST( SUM(hosp_flag) * 1.0 / COUNT(membership_id) AS DECIMAL (18,6) ) AS retention_rate_ly
		FROM Comp_Mem_LY
		WHERE ov_flag = 0 AND amb_flag = 0 AND hosp_product_id > 0

		UNION ALL

		SELECT 'Extras membership' AS ret_metric, CAST( SUM(extras_flag) * 1.0 / COUNT(membership_id) AS DECIMAL (18,6) ) AS retention_rate_ly
		FROM Comp_Mem_LY
		WHERE ov_flag = 0 AND amb_flag = 0 AND extras_product_id > 0

		UNION ALL

		SELECT 'Ambulance membership' AS ret_metric, CAST( SUM(a_retention_flag) * 1.0 / COUNT(membership_id) AS DECIMAL (18,6) ) AS retention_rate_ly
		FROM Comp_Mem_LY
		WHERE amb_flag = 1

		UNION ALL

		SELECT 'Overseas membership' AS ret_metric, CAST( SUM(retention_flag) * 1.0 / COUNT(membership_id) AS DECIMAL (18,6) ) AS retention_rate_ly
		FROM Comp_Mem_LY
		WHERE ov_flag = 1)

SELECT cur.ret_metric, cur.retention_rate, ly.retention_rate_ly
FROM Current_Results cur
JOIN LY_Results ly ON ly.ret_metric = cur.ret_metric;

GO

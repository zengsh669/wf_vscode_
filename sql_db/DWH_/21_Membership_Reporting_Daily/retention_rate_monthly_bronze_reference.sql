/***********************************************
DATE PARAMETERS - It's use to filter by rundate
Use the day after month-end
***********************************************/

DECLARE @LYDate DATE
DECLARE @YTDate DATE

SELECT @LYDate = '2025-08-01';
SELECT @YTDate = '2026-08-01';

WITH Base_Mem AS (
		SELECT CAST(rundate-1 AS DATE) AS month_end, membership_id, cover_type, cover_state,
		       ISNULL(hosp_product_id,0) AS hosp_product_id, ISNULL(extras_product_id,0) AS extras_product_id, ISNULL(ambuln_product_id,0) AS ambuln_product_id,
		       ISNULL(sales_channel_description,'Other') AS sales_channel_description, ISNULL(agent_description,'No Agency') AS agent_description,
			   CASE WHEN ISNULL(hosp_product_id,0) IN (10,34,65,191,192,193,194,195,196) THEN 1
			   ELSE 0 END AS ov_flag,
			   CASE WHEN ISNULL(ambuln_product_id,0) > 0 THEN 1
			   ELSE 0 END AS amb_flag
		FROM [BRONZE].[dbo].[group_key_full_by_branch]
		WHERE rundate = @LYDate AND join_date < rundate),

	 Ret_Mem AS (
		SELECT membership_id,  ISNULL(hosp_product_id,0) AS curr_hosp_product_id, ISNULL(extras_product_id,0) AS curr_extras_product_id, ISNULL(ambuln_product_id,0) AS curr_ambuln_product_id,
		       1 AS active_flag
		FROM [BRONZE].[dbo].[group_key_full_by_branch]
		WHERE rundate = @YTDate AND join_date < rundate),

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
			ON bm.membership_id = rm.membership_id)

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
WHERE ov_flag = 1;

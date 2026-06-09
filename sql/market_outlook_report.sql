/*
=========================================================================================================================
Market Outlook Report - 2024
=========================================================================================================================
Purpose:
	- This report consolidates key market metrics for 8 major varietals across 4 Canadian provinces (AB, BC, ON & QC).
	- This report also explores position & performance of Bread & Butter Wines across Market Segments.

Highlights:
	1. Exclusivity: USA Origin only (except Glera - Italy Origin)
	2. Aggregation Levels: Province, Varietal
	3. Market Segments based on volume contribution.
			Tier 1 = Top 50% Volume
			Tier 2 = Middle 30% Volume
			Tier 3 = Bottom 20% Volume
	4. YoY Volume Change Comparison
		- Overall Market
		- Bread & Butter Wines
		- Tier 1, 2 and 3
	5. HHI Index Calculation and Segementation
			HHI <= 1500 THEN 'Competitive'
			1500 < HHI < 2500 THEN 'Moderately concentrated'
			2500 <= HHI < 10000 THEN 'Highly concentrated'
	6. Concentration Ratios (CR3, CR5, and CR10)
	7. Strategic Position Definition
		
=========================================================================================================================
*/


/*-----------------------------------------------------------------------------------------------------------------------
1) Base Query : Retrieves Aggregated Volume Sales From the main View sales.calc_sales
-----------------------------------------------------------------------------------------------------------------------*/

-- Parameters required in Step 1 : Base Table
DECLARE @selected_origin VARCHAR(50) = 'USA';
DECLARE @exception_varietal VARCHAR(20) = 'Glera';
DECLARE @exception_varietal_origin VARCHAR(20) = 'Italy';
DECLARE @last_year_value VARCHAR(3) = 'LRY';
DECLARE @this_year_value VARCHAR(3) = 'TRY';


-- Parameters required in Step 3 : Market Segmentation
DECLARE @tier1_threshold DECIMAL(5,2) = 50.00;
DECLARE @tier2_threshold DECIMAL(5,2) = 80.00;
DECLARE @tier1_value INT = 1;
DECLARE @tier2_value INT = 2;
DECLARE @tier3_value INT = 3;

-- Parameters required in Step 5 : Market performance
DECLARE @selected_brand VARCHAR(100) = 'Bread & Butter';


WITH base_table AS
(
	SELECT
		s.province_code,
		s.varietal,
		s.brand,

		-- Total Volume in 9L cases (Last Year)
		SUM(CASE WHEN a.relative_year = @last_year_value THEN s.sale_9l_case END) AS sale_vol_ly,
		
		-- Total Volume in 9L cases (This Year)
		SUM(CASE WHEN a.relative_year = @this_year_value THEN s.sale_9l_case END) AS sale_vol_ty,

		-- Total Revenue Last Year
		SUM(CASE WHEN a.relative_year = @last_year_value THEN s.revenue END) AS revenue_ly,
		
		-- Total Revenue This Year
		SUM(CASE WHEN a.relative_year = @this_year_value THEN s.revenue END) AS revenue_ty		


	FROM sales.calc_sales AS s
	INNER JOIN dim.period_analogy AS a
		ON s.period_code = a.period_code
	INNER JOIN dim.wine_varietal AS v
		ON v.varietal = s.varietal
	WHERE 
		(v.bb_portfolio = 1 AND UPPER(s.origin) = UPPER(@selected_origin))
		OR
		(s.varietal = @exception_varietal AND s.origin = @exception_varietal_origin)
	GROUP BY
		s.province_code,
		s.varietal,
		s.brand
)

/*-----------------------------------------------------------------------------------------------------------------------
2) CTE - Cumulative Market Share and Rank by Sales : Calculating Market Share and Rank of Each Brand - PARTITION BY Province, Varietal
-----------------------------------------------------------------------------------------------------------------------*/

, market_share_rank_calc AS
(
	SELECT
		-- Categorical Attributes
		t.province_code,
		t.varietal,
		t.brand,

		-- Total Sales & Revenue Attributes
		t.sale_vol_ly,
		t.sale_vol_ty,
		t.revenue_ly,
		t.revenue_ty,

		-- Market Share (Last Year)
		COALESCE(
			t.sale_vol_ly * 100.0 
			/ NULLIF(SUM(t.sale_vol_ly) OVER(PARTITION BY t.province_code, t.varietal),0)
		,0) AS market_share_ly,

		-- Market Share (This Year)
		COALESCE(
		t.sale_vol_ty * 100.0 
			/ NULLIF(SUM(t.sale_vol_ty) OVER(PARTITION BY t.province_code, t.varietal),0)
		,0) AS market_share_ty,

		-- Cumulative Market Share (This Year)
		COALESCE(
			SUM(t.sale_vol_ty) OVER(PARTITION BY t.province_code, t.varietal 
									ORDER BY t.sale_vol_ty DESC, t.revenue_ty DESC 
									ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) * 100.0 
				/ NULLIF(SUM(t.sale_vol_ty) OVER(PARTITION BY t.province_code, t.varietal),0)
		,0) AS cum_market_share_ty,

		-- Rank by Sales
		ROW_NUMBER() OVER(PARTITION BY t.province_code, t.varietal ORDER BY t.sale_vol_ty DESC, t.revenue_ty DESC) AS rank_by_sale

	FROM base_table AS t
)

/*-----------------------------------------------------------------------------------------------------------------------
3) CTE - Market Segmentation into 3 tiers based on Volume Sales Contribution
-----------------------------------------------------------------------------------------------------------------------*/

, market_segmentation AS
(
	SELECT
		-- Categorical Attributes
		t.province_code,
		t.varietal,
		t.brand,

		-- Total Sales & Revenue Attributes
		t.sale_vol_ly,
		t.sale_vol_ty,
		t.revenue_ly,
		t.revenue_ty,

		-- Market Share Attributes
		t.market_share_ly,
		t.market_share_ty,
		(t.market_share_ty - t.market_share_ly ) AS market_share_growth,

		-- Rank by Sales
		t.rank_by_sale,

		-- Market Segmentation
		CASE
			WHEN (t.lag_cum_market_share < @tier1_threshold) OR t.lag_cum_market_share IS NULL THEN @tier1_value
			WHEN (t.lag_cum_market_share < @tier2_threshold) THEN @tier2_value
			ELSE @tier3_value
		END AS tier

	FROM (
		-- Lag Cumulative Market Share Calculation
		SELECT *, LAG(cum_market_share_ty) OVER(PARTITION BY province_code, varietal ORDER BY sale_vol_ty DESC, revenue_ty DESC) AS lag_cum_market_share
		FROM market_share_rank_calc
		) AS t
)


/*-----------------------------------------------------------------------------------------------------------------------
4) CTE - HHI and Concentration Ratio Calculation
-----------------------------------------------------------------------------------------------------------------------*/
, market_concentration AS
(
	SELECT
		t.province_code,
		t.varietal,

		-- HHI Calculation
		CAST(SUM(POWER(t.market_share_ly, 2)) AS DECIMAL(10,0)) AS hhi_ly,
		CAST(SUM(POWER(t.market_share_ty, 2)) AS DECIMAL(10,0)) AS hhi_ty,

		-- Concentration Ratios
		CAST(COALESCE(SUM(CASE WHEN t.rank_by_sale <= 3 THEN t.sale_vol_ty END) * 100.0 / NULLIF(SUM(t.sale_vol_ty),0),0) AS DECIMAL(10,2)) AS cr3,
		CAST(COALESCE(SUM(CASE WHEN t.rank_by_sale <= 5 THEN t.sale_vol_ty END) * 100.0 / NULLIF(SUM(t.sale_vol_ty),0),0) AS DECIMAL(10,2)) AS cr5,
		CAST(COALESCE(SUM(CASE WHEN t.rank_by_sale <= 10 THEN t.sale_vol_ty END) * 100.0 / NULLIF(SUM(t.sale_vol_ty),0),0) AS DECIMAL(10,2)) AS cr10

	FROM market_segmentation AS t
	GROUP BY
		t.province_code,
		t.varietal
)


/*-----------------------------------------------------------------------------------------------------------------------
5) CTE - Market performance - YoY Change in Sales and Revenue
-----------------------------------------------------------------------------------------------------------------------*/
, market_performance AS
(
	SELECT 
		t.province_code,
		t.varietal,

	-- Overall Market KPIs
		-- Total Market Sales (9L Cases)
		SUM(t.sale_vol_ty) AS total_market_sale_ty,
		COUNT(t.brand) AS total_active_brands,
		
		-- Overall Market yoy Change
		CAST(COALESCE((SUM(t.sale_vol_ty) - SUM(t.sale_vol_ly)) * 100.0 /NULLIF(SUM(t.sale_vol_ly),0),0) AS DECIMAL(8,2)) AS market_yoy_change,


	-- Bread & Butter brand performance
		
		-- Bread & Butter Ranking
		COALESCE(MAX(CASE WHEN UPPER(t.brand) = UPPER(@selected_brand) THEN t.rank_by_sale END),0) AS bnb_rank_by_volume,

		-- Bread & Butter tier
		COALESCE(MAX(CASE WHEN UPPER(t.brand) = UPPER(@selected_brand) THEN t.tier END),0) AS bnb_tier_by_volume,
		
		-- Bread & Butter This Year Sales
		COALESCE(SUM(CASE WHEN UPPER(t.brand) = UPPER(@selected_brand) THEN t.sale_vol_ty END),0) AS bnb_total_sale_ty,

		-- YoY %Sale Change
		CAST(COALESCE((SUM(CASE WHEN UPPER(t.brand) = UPPER(@selected_brand) THEN t.sale_vol_ty END) - SUM(CASE WHEN UPPER(t.brand) = UPPER(@selected_brand) THEN t.sale_vol_ly END))*100
			/ NULLIF(SUM(CASE WHEN UPPER(t.brand) = UPPER(@selected_brand) THEN t.sale_vol_ly END),0),0) AS DECIMAL(8,2)) AS bnb_yoy_sale_change,
		
		-- Bread & Butter Market Share
		COALESCE(SUM(CASE WHEN UPPER(t.brand) = UPPER(@selected_brand) THEN t.market_share_ly END),0) AS bnb_market_share_ly,
		COALESCE(SUM(CASE WHEN UPPER(t.brand) = UPPER(@selected_brand) THEN t.market_share_ty END),0) AS bnb_market_share_ty,
		COALESCE(SUM(CASE WHEN UPPER(t.brand) = UPPER(@selected_brand) THEN t.market_share_growth END),0) AS bnb_market_share_growth,


	-- Tier performance (Bread & Butter is excluded)
		
		-- YOY % Change
		-- tier 1 yoy change
		CAST(COALESCE(
			(SUM(CASE WHEN t.tier = @tier1_value AND UPPER(t.brand) <> UPPER(@selected_brand) THEN t.sale_vol_ty END) 
				- SUM(CASE WHEN t.tier = @tier1_value AND UPPER(t.brand) <> UPPER(@selected_brand) THEN t.sale_vol_ly END))*100
					/ NULLIF(SUM(CASE WHEN t.tier = @tier1_value AND UPPER(t.brand) <> UPPER(@selected_brand) THEN t.sale_vol_ly END),0)
			,0) AS DECIMAL(8,2)) AS tier_1_yoy_change,

	
		-- tier 2 yoy change
		CAST(COALESCE(
			(SUM(CASE WHEN t.tier = @tier2_value AND UPPER(t.brand) <> UPPER(@selected_brand) THEN t.sale_vol_ty END) 
				- SUM(CASE WHEN t.tier = @tier2_value AND UPPER(t.brand) <> UPPER(@selected_brand) THEN t.sale_vol_ly END))*100
					/ NULLIF(SUM(CASE WHEN t.tier = @tier2_value AND UPPER(t.brand) <> UPPER(@selected_brand) THEN t.sale_vol_ly END),0)
			,0) AS DECIMAL(8,2)) AS tier_2_yoy_change,
	

		-- tier 3 yoy change
		CAST(COALESCE(
			(SUM(CASE WHEN t.tier = @tier3_value AND UPPER(t.brand) <> UPPER(@selected_brand) THEN t.sale_vol_ty END) 
				- SUM(CASE WHEN t.tier = @tier3_value AND UPPER(t.brand) <> UPPER(@selected_brand) THEN t.sale_vol_ly END)) * 100
					/ NULLIF(SUM(CASE WHEN t.tier = @tier3_value AND UPPER(t.brand) <> UPPER(@selected_brand) THEN t.sale_vol_ly END),0)
			,0) AS DECIMAL(8,2)) AS tier_3_yoy_change,

	-- Market Share Change
		-- Tier 1 - Market Share Change
		(COALESCE(SUM(CASE WHEN t.tier = @tier1_value AND UPPER(t.brand) <> UPPER(@selected_brand) THEN t.market_share_ty END),0) -
			COALESCE(SUM(CASE WHEN t.tier = @tier1_value AND UPPER(t.brand) <> UPPER(@selected_brand) THEN t.market_share_ly END),0)) AS tier_1_market_share_change,

		-- Tier 2 - Market Share Change
		(COALESCE(SUM(CASE WHEN t.tier = @tier2_value AND UPPER(t.brand) <> UPPER(@selected_brand) THEN t.market_share_ty END),0) -
			COALESCE(SUM(CASE WHEN t.tier = @tier2_value AND UPPER(t.brand) <> UPPER(@selected_brand) THEN t.market_share_ly END),0)) AS tier_2_market_share_change,

		-- Tier 3 - Market Share Change
		(COALESCE(SUM(CASE WHEN t.tier = @tier3_value AND UPPER(t.brand) <> UPPER(@selected_brand) THEN t.market_share_ty END),0) -
			COALESCE(SUM(CASE WHEN t.tier = @tier3_value AND UPPER(t.brand) <> UPPER(@selected_brand) THEN t.market_share_ly END),0)) AS tier_3_market_share_change,


		-- tier 1 no. of brands
		COUNT(CASE WHEN t.tier = @tier1_value AND UPPER(t.brand) <> UPPER(@selected_brand) THEN t.sale_vol_ty END) AS tier_1_brands_count,
		-- tier 2 no. of brands
		COUNT(CASE WHEN t.tier = @tier2_value AND UPPER(t.brand) <> UPPER(@selected_brand) THEN t.sale_vol_ty END) AS tier_2_brands_count,
		-- tier 3 no. of brands
		COUNT(CASE WHEN t.tier = @tier3_value AND UPPER(t.brand) <> UPPER(@selected_brand) THEN t.sale_vol_ty END) AS tier_3_brands_count


	FROM market_segmentation AS t
	GROUP BY 
		t.province_code, 
		t.varietal
)


/*-----------------------------------------------------------------------------------------------------------------------
6) CTE - HHI Segmentation and Strategic Position Definition based on YoY Growth and Market Share Change
-----------------------------------------------------------------------------------------------------------------------*/
, strategic_position_definition AS
(
SELECT 
		c.province_code,
		c.varietal,
		c.hhi_ly,
		c.hhi_ty,

		-- Market Segmentation Based on This Year's HHI Value
		CASE
			WHEN c.hhi_ty IS NULL THEN 'Unknown'
			WHEN c.hhi_ty <= 1500.0 THEN 'Competitive'
			WHEN c.hhi_ty < 2500.0 THEN 'Moderately concentrated'
			WHEN c.hhi_ty < 10000.0 THEN 'Highly concentrated'
			ELSE 'Monopoly'
		END AS hhi_segment,
		c.cr3,
		c.cr5,
		c.cr10,
		p.total_market_sale_ty,
		p.total_active_brands,
		p.market_yoy_change,
		p.bnb_rank_by_volume,
		p.bnb_tier_by_volume,

		-- Position Definition Logic
		CONCAT(
			CASE
				WHEN (p.bnb_yoy_sale_change > p.market_yoy_change) AND p.bnb_market_share_growth > 0 THEN 'Expanding'
				WHEN (p.bnb_yoy_sale_change < p.market_yoy_change) AND p.bnb_market_share_growth < 0 THEN 'Contracting'
				WHEN p.bnb_yoy_sale_change = 0 AND p.bnb_market_share_growth = 0 THEN ''
				ELSE 'Steady'
			END,

			CASE
				WHEN p.bnb_yoy_sale_change = 0 AND p.bnb_market_share_growth = 0 THEN ''
				ELSE ' '
			END,

			CASE
				WHEN (p.bnb_rank_by_volume = 1 OR p.bnb_rank_by_volume = 2) THEN 'Leader'
				WHEN p.bnb_tier_by_volume = 1 THEN 'Core'
				WHEN p.bnb_tier_by_volume = 2 THEN 'Challenger'
				WHEN p.bnb_tier_by_volume = 3 THEN 'Niche'
				ELSE 'Pipeline'
			END
		) AS bnb_archetype_position,

		CASE
			WHEN (p.bnb_yoy_sale_change > p.market_yoy_change) AND p.bnb_market_share_growth > 0 THEN 'Expanding'
			WHEN (p.bnb_yoy_sale_change < p.market_yoy_change) AND p.bnb_market_share_growth < 0 THEN 'Contracting'
			WHEN p.bnb_yoy_sale_change = 0 AND p.bnb_market_share_growth = 0 THEN NULL
			ELSE 'Steady'
		END AS bnb_archetype_1st_part,

		CASE
			WHEN (p.bnb_rank_by_volume = 1 OR p.bnb_rank_by_volume = 2) THEN 'Leader'
			WHEN p.bnb_tier_by_volume = 1 THEN 'Core'
			WHEN p.bnb_tier_by_volume = 2 THEN 'Challenger'
			WHEN p.bnb_tier_by_volume = 3 THEN 'Niche'
			ELSE 'Pipeline'
		END AS bnb_archetype_2nd_part,


		p.bnb_total_sale_ty,
		p.bnb_yoy_sale_change,
		p.bnb_market_share_ly,
		p.bnb_market_share_ty,
		p.bnb_market_share_growth,
		p.tier_1_yoy_change,
		p.tier_2_yoy_change,
		p.tier_3_yoy_change,
		p.tier_1_market_share_change,
		p.tier_2_market_share_change,
		p.tier_3_market_share_change,
		p.tier_1_brands_count,
		p.tier_2_brands_count,
		p.tier_3_brands_count

	FROM market_concentration AS c
	JOIN market_performance AS p
		ON c.province_code = p.province_code AND c.varietal = p.varietal
)


/*-----------------------------------------------------------------------------------------------------------------------
7) Execution Query
-----------------------------------------------------------------------------------------------------------------------*/
SELECT * FROM strategic_position_definition;
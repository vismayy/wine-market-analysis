/*------------------------------------
Purpose: 
Varietal position in the province.
- Performace (Growth vs. Volume)
- Market Leader (All origion)
- USA-Origin Leader
- Bread & Butter Presence

This Query
	Aggregate sales to varietal level,
	Calculate growth and market share,
	Identify leading origin,
	Identify leading brand,
	Identify leading brand of USA-origin,
	Benchmark Bread & Butter against category leaders

Filters:
- Unit Size: 750 ml
------------------------------------*/


/*--------------------------------------------------------------------------
1) : Sale Volume in 9L cases summarized by (Province -> Varietal -> Origin -> Brand -> Sale)
--------------------------------------------------------------------------*/
WITH base_table_cte AS
(
	SELECT
		s.province_code,
		s.varietal,
		s.origin,
		s.brand,
		SUM(CASE WHEN UPPER(a.relative_year) = 'LRY' THEN s.sale_9l_case END) AS sale_ly,
		SUM(CASE WHEN UPPER(a.relative_year) = 'TRY' THEN s.sale_9l_case END) AS sale_ty
	FROM sales.calc_sales AS s
	JOIN dim.period_analogy AS a
		ON a.period_code = s.period_code

	-- Filter: Only 750 ml unit size in considered due to its overwhelming share compared to other size
	WHERE s.unit_size = 750
	GROUP BY 
		s.province_code,
		s.varietal,
		s.origin,
		s.brand
)

/*--------------------------------------------------------------------------
2) Original Table furthur summurized to the level of origin (Province -> Varietal -> Origin -> Sale). 
Dependency: base_table_cte
--------------------------------------------------------------------------*/
, origin_level_summarized_cte AS
(
	SELECT
		province_code,
		varietal,
		origin,
		SUM(sale_ly) AS total_sale_ly,
		SUM(sale_ty) AS total_sale_ty
	FROM base_table_cte
	GROUP BY
		province_code,
		varietal,
		origin
)

/*--------------------------------------------------------------------------
3) Varietal Volume Growth, Market Share and Ranking in the Province. 
Dependency: origin_level_summarized_cte
--------------------------------------------------------------------------*/
, varietal_performance AS
(
	SELECT
		t.province_code,
		t.varietal,
		t.total_sale_ty,
		
		-- Varietal Volume Growth YoY
		COALESCE((t.total_sale_ty - t.total_sale_ly) * 1.0/NULLIF(t.total_sale_ly,0),0) AS varietal_volume_growth_yoy,

		-- Market Share based on Volume of Varietal
		COALESCE((t.total_sale_ty) * 1.0/NULLIF(SUM(t.total_sale_ty) OVER(PARTITION BY t.province_code),0),0) AS varietal_market_share_ty,

		-- Varietal Ranking based on Volume
		ROW_NUMBER() OVER(
						PARTITION BY t.province_code 
						ORDER BY t.total_sale_ty DESC, t.total_sale_ly DESC, t.varietal ASC
		) AS varietal_rank_by_volume

	FROM
	(
		-- Summarized table for varietal in order to calculate yoy_growth, market_share and volume based ranking
		SELECT
			province_code,
			varietal,
			SUM(total_sale_ly) AS total_sale_ly,
			SUM(total_sale_ty) AS total_sale_ty
		FROM origin_level_summarized_cte
		GROUP BY
			province_code,
			varietal
	) AS t
)


/*--------------------------------------------------------------------------
4) Top Origin by volume and its growth.
Dependency: origin_level_summarized_cte
--------------------------------------------------------------------------*/
, top_country_of_origin AS 
(
	SELECT
		t.province_code,
		t.varietal,
		
		-- Top Origin Statistics
		MAX(CASE WHEN t.origin_rank_by_volume = 1 THEN t.origin END) AS top_origin,
		MAX(CASE WHEN t.origin_rank_by_volume = 1 THEN t.total_sale_ty END) AS top_origin_volume_sale,
		MAX(CASE WHEN t.origin_rank_by_volume = 1 THEN t.origin_volume_growth_yoy END) AS top_origin_volume_growth_yoy,
		MAX(CASE WHEN t.origin_rank_by_volume = 1 THEN t.origin_market_share_ty END) AS top_origin_market_share,

		-- USA-Origin Statistics
		COALESCE(MAX(CASE WHEN UPPER(t.origin) = 'USA' THEN t.total_sale_ty END),0) AS usa_origin_volume_sale,
		COALESCE(MAX(CASE WHEN UPPER(t.origin) = 'USA' THEN t.origin_volume_growth_yoy END),0) AS usa_origin_volume_growth_yoy,
		COALESCE(MAX(CASE WHEN UPPER(t.origin) = 'USA' THEN t.origin_market_share_ty END),0) AS usa_origin_market_share

	FROM
	(
		SELECT
			t.province_code,
			t.varietal,
			t.origin,
			t.total_sale_ly,
			t.total_sale_ty,

			-- Origin Volume Growth YoY
			COALESCE((t.total_sale_ty - t.total_sale_ly) * 1.0/NULLIF(t.total_sale_ly,0),0) AS origin_volume_growth_yoy,

			-- Market Share of Origin in a varietal based on Volume 
			COALESCE((t.total_sale_ty) * 1.0/NULLIF(SUM(t.total_sale_ty) OVER(PARTITION BY t.province_code, t.varietal),0),0) AS origin_market_share_ty,

			-- Ranking origins in the varietal
			ROW_NUMBER() OVER(PARTITION BY t.province_code, t.varietal ORDER BY t.total_sale_ty DESC, t.total_sale_ly DESC, t.origin ASC) AS origin_rank_by_volume

		FROM origin_level_summarized_cte AS t
	) AS t
	GROUP BY
		t.province_code,
		t.varietal
)


/*--------------------------------------------------------------------------
5) Market Leader (All Origins)
Dependency: base_table_cte
--------------------------------------------------------------------------*/
, global_market_leader_cte AS
(
	SELECT
		t.province_code,
		t.varietal,
		t.origin AS market_leader_origin,
		t.brand AS market_leader_brand,
		t.sale_ty AS market_leader_volume,
		t.brand_volume_growth_yoy AS market_leader_volume_growth_yoy,

		-- Market Share of Brand for that particular varietal (between all origins)
		t.brand_market_share_ty AS market_leader_market_share_ty
	FROM
	(
		SELECT 
			province_code,
			varietal,
			origin,
			brand,
			sale_ly,
			sale_ty,

			-- Brand Volume Growth YoY
			COALESCE((sale_ty - sale_ly) * 1.0/NULLIF(sale_ly,0),0) AS brand_volume_growth_yoy,

			-- Market Share of Brand for that particular varietal (between all origins)
			COALESCE((sale_ty) * 1.0/NULLIF(SUM(sale_ty) OVER(PARTITION BY province_code, varietal),0),0) AS brand_market_share_ty,

			-- Ranking of Brand for the varietal
			ROW_NUMBER() OVER(PARTITION BY province_code, varietal ORDER BY sale_ty DESC, sale_ly DESC, brand ASC) AS brand_rank_by_volume
		FROM base_table_cte
	) AS t
	WHERE t.brand_rank_by_volume = 1
)

/*--------------------------------------------------------------------------
6) Market Leader (USA Origin)
Dependency: base_table_cte
--------------------------------------------------------------------------*/
, usa_origin_top_brand_cte AS
(
	SELECT
		t.province_code,
		t.varietal,

		-- Top Brand Statistics
		MAX(CASE WHEN t.brand_rank_by_volume = 1 THEN t.brand END) AS usa_origin_top_brand,
		MAX(CASE WHEN t.brand_rank_by_volume = 1 THEN t.sale_ty END) AS usa_origin_top_brand_volume,
		MAX(CASE WHEN t.brand_rank_by_volume = 1 THEN t.brand_volume_growth_yoy END) AS usa_origin_top_brand_volume_growth_yoy,
		MAX(CASE WHEN t.brand_rank_by_volume = 1 THEN t.brand_market_share_ty END) AS usa_origin_top_brand_market_share_ty,

		-- Bread & Butter Statistics
		COALESCE(MAX(CASE WHEN UPPER(t.brand) = 'BREAD & BUTTER' THEN t.sale_ty END),0) AS bnb_volume,
		COALESCE(MAX(CASE WHEN UPPER(t.brand) = 'BREAD & BUTTER' THEN t.brand_volume_growth_yoy END),0) AS bnb_volume_growth_yoy,
		COALESCE(MAX(CASE WHEN UPPER(t.brand) = 'BREAD & BUTTER' THEN t.brand_market_share_ty END),0) AS bnb_market_share_ty
		

	FROM
	(
		SELECT 
			province_code,
			varietal,
			origin,
			brand,
			sale_ty,

			-- Brand Volume Growth YoY
			COALESCE((sale_ty - sale_ly) * 1.0/NULLIF(sale_ly,0),0) AS brand_volume_growth_yoy,

			-- Market Share of Brand for that particular varietal (between all origins)
			COALESCE((sale_ty) * 1.0/NULLIF(SUM(sale_ty) OVER(PARTITION BY province_code, varietal),0),0) AS brand_market_share_ty,

			-- Ranking of Brand for the varietal
			ROW_NUMBER() OVER(PARTITION BY province_code, varietal ORDER BY sale_ty DESC, sale_ly DESC, brand ASC) AS brand_rank_by_volume
		FROM base_table_cte
		WHERE UPPER(origin) = 'USA'
	) AS t
	GROUP BY
		t.province_code,
		t.varietal
)


/*--------------------------------------------------------------------------
Final Table
Main Table - varietal_performace
SELECT * FROM top_country_of_origin
--------------------------------------------------------------------------*/
, final_table AS
(
SELECT 
	-- dimention table: dim.province
	p.province_name AS [Province],

	-- cte: varietal_performace
	v.varietal AS [Varietal],
	v.total_sale_ty AS [Varietal - Total Volume],
	v.varietal_volume_growth_yoy AS [Varietal - YoY Volume Growth %],
	v.varietal_market_share_ty AS [Varietal - Market Share in Province %],
	v.varietal_rank_by_volume AS [Varietal - Rank by Volume in Province],

	-- cte: top_country_of_origin
		-- Top Origin Statistics
	o.top_origin AS [Top Origin],
	o.top_origin_volume_sale AS [Top Origin - Total Volume],
	o.top_origin_volume_growth_yoy AS [Top Origin - YoY Volume Growth %],
	o.top_origin_market_share AS [Top Origin - Market Share %],
		-- USA Origin Statistics
	o.usa_origin_volume_sale AS [USA Origin - Total Volume],
	o.usa_origin_volume_growth_yoy AS [USA Origin - YoY Volume Growth %],
	o.usa_origin_market_share AS [USA Origin - Market Share %],


	-- cte: global_market_leader_cte
	l.market_leader_origin AS [Market Leader Brand - Origin],
	l.market_leader_brand AS [Market Leader Brand],
	l.market_leader_volume AS [Market Leader Brand - Total Volume],
	l.market_leader_volume_growth_yoy AS [Market Leader Brand - YoY Volume Growth %],
	l.market_leader_market_share_ty AS [Market Leader Brand - Market Share %],


	-- cte: usa_origin_top_brand_cte
		-- USA Origin Top brand Statistics
	u.usa_origin_top_brand AS [USA Origin Top Brand],
	u.usa_origin_top_brand_volume AS [USA Origin Top Brand - Total Volume],
	u.usa_origin_top_brand_volume_growth_yoy AS [USA Origin Top Brand - YoY Volume Growth %],
	u.usa_origin_top_brand_market_share_ty * o.usa_origin_market_share AS [USA Origin Top Brand - Market Share %],
		-- Bread & Butter Statistics
	u.bnb_volume AS [Bread & Butter - Total Volume],
	u.bnb_volume_growth_yoy AS [Bread & Butter - YoY Volume Growth %],
	u.bnb_market_share_ty * o.usa_origin_market_share AS [Bread & Butter - Market Share %],
	CASE WHEN u.bnb_volume > 0 THEN 1 ELSE 0 END AS [Bread & Butter - Presence]


FROM varietal_performance AS v
LEFT JOIN dim.province AS p
	ON v.province_code = p.province_code
LEFT JOIN top_country_of_origin AS o
	ON (v.province_code = o.province_code) AND (v.varietal = o.varietal)
LEFT JOIN global_market_leader_cte AS l
	ON (v.province_code = l.province_code) AND (v.varietal = l.varietal)
LEFT JOIN usa_origin_top_brand_cte AS u
	ON (v.province_code = u.province_code) AND (v.varietal = u.varietal)
)

SELECT * FROM final_table;
/*------------------------------------
Pinot Noir - Top 3 brands - Province Wise
------------------------------------*/


WITH base_table_cte AS
(
	SELECT
		s.province_code,
		s.origin,
		s.brand,
		s.product_code,
		s.price_segment,
		p.retail_price_this_year,
		SUM(CASE WHEN UPPER(a.relative_year) = 'LRY' THEN s.sale_9l_case END) AS sale_ly,
		SUM(CASE WHEN UPPER(a.relative_year) = 'TRY' THEN s.sale_9l_case END) AS sale_ty
	FROM sales.calc_sales AS s
	LEFT JOIN dim.period_analogy AS a
		ON s.period_code = a.period_code 
	LEFT JOIN dim.products AS p
		ON s.product_code = p.global_code
	WHERE 
		s.unit_size = 750 
		AND s.varietal = 'Pinot Noir'
	GROUP BY
		s.province_code,
		s.origin,
		s.brand,
		s.product_code,
		s.price_segment,
		p.retail_price_this_year
)


, final_table AS
(
	SELECT
		*,
		COALESCE((sale_ty - sale_ly)*1.0/NULLIF(sale_ly,0),0) AS [Volume Growth %],
		sale_ty * 100.0 / SUM(sale_ty) OVER(PARTITION BY province_code) AS [Market Share %],
		ROW_NUMBER() OVER(PARTITION BY province_code ORDER BY sale_ty DESC, sale_ly DESC, brand ASC) AS rank_by_volume
	FROM base_table_cte
)


SELECT * FROM final_table
WHERE rank_by_volume <= 3;

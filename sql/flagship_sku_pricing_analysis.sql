/*-----------------------------------------------------------------------------------------------
Purpose: Identifies the flagship SKU for each brand within every province, varietal, and unit size.

Grouping Sequence :
	Province
	Varietal
	Size
	Brand
	SKU (Product_Code)
	Price
	Price Segment
	Sale (LY + TY)
	Revenue (LY + TY)
-----------------------------------------------------------------------------------------------*/




/*-----------------------------------------------------------------------------------------------
Variables
-----------------------------------------------------------------------------------------------*/
DECLARE @origin VARCHAR(100) = 'USA';
DECLARE @exception_varietal VARCHAR(100) = 'Glera';
DECLARE @exception_varietal_origin VARCHAR(100) = 'Italy';
DECLARE @cum_market_share_cut_off DECIMAL(5,2) = 95.0;


/*-----------------------------------------------------------------------------------------------
1) Base Query : Retrieves Aggregated Volume Sales From the main View sales.calc_sales
-----------------------------------------------------------------------------------------------*/

WITH base_table AS
(
	SELECT
		s.province_code,
		s.varietal,
		s.unit_size,
		s.brand,
		s.product_code,
		s.product_name,
		p.retail_price_this_year AS retail_price,
		s.price_segment,
		SUM(CASE WHEN a.relative_year = 'LRY' THEN s.sale_9l_case END) AS sale_ly,
		SUM(CASE WHEN a.relative_year = 'TRY' THEN s.sale_9l_case END) AS sale_ty,
		SUM(CASE WHEN a.relative_year = 'LRY' THEN s.revenue END) AS revenue_ly,
		SUM(CASE WHEN a.relative_year = 'TRY' THEN s.revenue END) AS revenue_ty
	FROM sales.calc_sales AS s
	JOIN dim.period_analogy AS a
		ON a.period_code = s.period_code
	JOIN dim.products AS p
		ON p.global_code = s.product_code
	WHERE 
		s.origin = @origin
		OR
		(s.varietal = @exception_varietal AND s.origin = @exception_varietal_origin)
	GROUP BY 
		s.province_code,
		s.varietal,
		s.unit_size,
		s.brand,
		s.product_code,
		s.product_name,
		p.retail_price_this_year,
		s.price_segment
)

/*-----------------------------------------------------------------------------------------------
2) Flagship SKU Identification for Each Brand, Varietal, and Unit Size
-----------------------------------------------------------------------------------------------*/
, flagship_sku_identification AS
(
	SELECT
		*,

		-- SKU Ranking Based on Volume Sale for each Brand
		RANK() OVER(
			PARTITION BY province_code, varietal, unit_size, brand
			ORDER BY sale_ty DESC, revenue_ty DESC, sale_ly DESC, revenue_ly DESC 
		) AS sku_rank_by_volume,

		-- SKU Volume Share Within the Brand
		COALESCE((sale_ty * 100.0 / NULLIF(SUM(sale_ty) OVER(PARTITION BY province_code, varietal, unit_size, brand),0)), 0) AS sku_volume_share_for_brand_per,

		-- Cumulative Brand Volume Sales in the Segment
		SUM(sale_ty) OVER(PARTITION BY province_code, varietal, unit_size, brand) AS brand_total_sale_ty,

		-- Brand Market Share in the Segment
		SUM(sale_ty) OVER(PARTITION BY province_code, varietal, unit_size, brand) * 100.0 / NULLIF(SUM(sale_ty) OVER(PARTITION BY province_code, varietal, unit_size),0) AS brand_market_share

		
		

	FROM base_table

)


/*-----------------------------------------------------------------------------------------------
Cummulative Market Share and Its Lag Effect Calculation
-----------------------------------------------------------------------------------------------*/
, cum_market_share_calc AS
(
SELECT
	*,
	COALESCE(
		LAG(brand_cum_market_share) 
			OVER(
				PARTITION BY province_code, varietal, unit_size 
				ORDER BY brand_market_share DESC, retail_price DESC, sale_ty DESC, revenue_ty DESC, sale_ly DESC, revenue_ly DESC
				)
		,0) AS lag_brand_cum_market_share
FROM
	(
	SELECT 
		*,

		-- Brand Cummulative Market Share in the Segment
		SUM(brand_market_share) 
			OVER(
				PARTITION BY province_code, varietal, unit_size 
				ORDER BY brand_market_share DESC, retail_price DESC, sale_ty DESC, revenue_ty DESC, sale_ly DESC, revenue_ly DESC 
				ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
				) AS brand_cum_market_share
	FROM flagship_sku_identification
	WHERE sku_rank_by_volume = 1 --AND brand_market_share IS NOT NULL
	) AS t
)



/*-----------------------------------------------------------------------------------------------
Final Query
-----------------------------------------------------------------------------------------------*/

SELECT 
	province_code,
	varietal,
	unit_size,
	brand,
	product_code,
	retail_price,
	price_segment,
	sale_ly,
	sale_ty,
	COALESCE((sale_ty - sale_ly)/NULLIF(sale_ly,0),0) AS sku_yoy_volume_change_per,
	revenue_ly,
	revenue_ty,
	sku_volume_share_for_brand_per,
	brand_total_sale_ty,
	brand_market_share / 100.0 AS brand_market_share,
	CASE
		WHEN lag_brand_cum_market_share <= 50.0 THEN 1
		WHEN lag_brand_cum_market_share <= 80.0 THEN 2
		ELSE 3
	END AS brand_tier,
	ROW_NUMBER() OVER(PARTITION BY province_code, varietal, unit_size ORDER BY brand_total_sale_ty DESC, sale_ty DESC, revenue_ty DESC, sale_ly DESC, revenue_ly DESC) AS brand_rank_by_volume
FROM cum_market_share_calc
WHERE lag_brand_cum_market_share <= @cum_market_share_cut_off;

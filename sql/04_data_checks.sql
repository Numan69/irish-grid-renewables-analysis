USE irish_grid;

-- 1. Rows per year (expect 35040 / 35040 / 35136 / 35040)
SELECT d.year, COUNT(*) AS intervals
FROM fact_grid_15min f
JOIN dim_date d ON f.date_key = d.date_key
GROUP BY d.year
ORDER BY d.year;

-- 2. Annual totals (should match the Python quality report)
SELECT
    d.year,
    ROUND(SUM(f.demand_mw) * 0.25 / 1e6, 2)                          AS demand_twh,
    ROUND(SUM(f.wind_mw)   * 0.25 / 1e6, 2)                          AS wind_twh,
    ROUND(100 * SUM(f.wind_mw)  / SUM(f.demand_mw), 1)               AS wind_share_pct,
    ROUND(100 * SUM(f.solar_mw) / SUM(f.demand_mw), 1)               AS solar_share_pct,
    ROUND(MAX(f.demand_mw), 0)                                       AS peak_demand_mw,
    ROUND(SUM(f.wind_dispatch_down_mw) * 0.25 / 1e6, 2)              AS wind_dispatch_down_twh
FROM fact_grid_15min f
JOIN dim_date d ON f.date_key = d.date_key
GROUP BY d.year
ORDER BY d.year;

-- 3. NULL check on EWIC (expect 35040 NULLs, all in 2022)
SELECT d.year, SUM(f.ewic_mw IS NULL) AS ewic_nulls
FROM fact_grid_15min f
JOIN dim_date d ON f.date_key = d.date_key
GROUP BY d.year;

-- 4. Daylight saving check: repeated October hour (expect 32 rows = 4 timestamps x 2 copies x 4 years)
SELECT COUNT(*) AS dst_repeat_rows FROM fact_grid_15min WHERE is_dst_repeat_hour = 1;

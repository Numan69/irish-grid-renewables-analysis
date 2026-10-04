USE irish_grid;

-- ---------------------------------------------------------------------
-- Q1. How has wind's share of demand changed month by month,
--     and how does each month compare with the same month last year?
--     (window function: LAG)
-- ---------------------------------------------------------------------
WITH monthly AS (
    SELECT
        d.year,
        d.month_num,
        d.month_short,
        SUM(f.demand_mw) * 0.25 / 1000  AS demand_gwh,
        SUM(f.wind_mw)   * 0.25 / 1000  AS wind_gwh,
        SUM(f.solar_mw)  * 0.25 / 1000  AS solar_gwh
    FROM fact_grid_15min f
    JOIN dim_date d ON f.date_key = d.date_key
    GROUP BY d.year, d.month_num, d.month_short
)
SELECT
    year,
    month_short,
    ROUND(demand_gwh, 0)                        AS demand_gwh,
    ROUND(100 * wind_gwh  / demand_gwh, 1)      AS wind_share_pct,
    ROUND(100 * solar_gwh / demand_gwh, 1)      AS solar_share_pct,
    ROUND(100 * wind_gwh / demand_gwh
          - LAG(100 * wind_gwh / demand_gwh, 12) OVER (ORDER BY year, month_num), 1)
                                                AS wind_share_change_vs_ly_pts
FROM monthly
ORDER BY year, month_num;

-- Finding: Wind share is highly seasonal, from about 20% in summer months
-- to over 50% in windy winter months, and changes by up to 17 points
-- year-on-year. Monthly demand grew from 2,882 GWh (Jan 2022) to 3,225 GWh
-- (Jan 2025), an increase of about 12%.

-- ---------------------------------------------------------------------
-- Q2. What does a typical day look like? Average demand, wind and solar
--     by hour of day, winter vs summer.
-- ---------------------------------------------------------------------
SELECT
    t.hour_of_day,
    ROUND(AVG(CASE WHEN d.season = 'Winter' THEN f.demand_mw END), 0) AS winter_demand_mw,
    ROUND(AVG(CASE WHEN d.season = 'Summer' THEN f.demand_mw END), 0) AS summer_demand_mw,
    ROUND(AVG(CASE WHEN d.season = 'Winter' THEN f.wind_mw   END), 0) AS winter_wind_mw,
    ROUND(AVG(CASE WHEN d.season = 'Summer' THEN f.wind_mw   END), 0) AS summer_wind_mw,
    ROUND(AVG(CASE WHEN d.season = 'Summer' THEN f.solar_mw  END), 0) AS summer_solar_mw
FROM fact_grid_15min f
JOIN dim_date d ON f.date_key = d.date_key
JOIN dim_time t ON f.time_key = t.time_key
WHERE d.year >= 2024                        -- recent years, solar is meaningful
GROUP BY t.hour_of_day
ORDER BY t.hour_of_day;
-- Finding: Winter demand peaks at around 17:00-18:00 (about 5,000 MW),
-- roughly 50% higher than the overnight low at 04:00 (3,360 MW). Wind output
-- stays almost flat through the day (1,580-1,730 MW), so it does not rise to
-- meet the evening peak. Solar peaks at midday (~410 MW in summer) and has
-- largely faded by the evening peak, meaning the 5pm winter peak must be met
-- mainly by gas, imports or storage.


-- ---------------------------------------------------------------------
-- Q3. When did each year's peak demand happen?
--     (window function: ROW_NUMBER)
-- ---------------------------------------------------------------------
WITH ranked AS (
    SELECT
        d.year,
        f.datetime_local,
        d.day_name,
        f.demand_mw,
        f.wind_mw,
        ROW_NUMBER() OVER (PARTITION BY d.year ORDER BY f.demand_mw DESC) AS rn
    FROM fact_grid_15min f
    JOIN dim_date d ON f.date_key = d.date_key
)
SELECT
    year,
    datetime_local         AS peak_time,
    day_name,
    ROUND(demand_mw, 0)    AS peak_demand_mw,
    ROUND(wind_mw, 0)      AS wind_at_peak_mw,
    ROUND(100 * wind_mw / demand_mw, 1) AS wind_share_at_peak_pct
FROM ranked
WHERE rn = 1
ORDER BY year;
-- Finding: Annual peak demand always occurred on a winter weekday between
-- 17:15 and 17:45, and grew from 5,523 MW (2022) to 6,012 MW (2025), up 8.9%.
-- In 2024 and 2025 wind supplied only 8-12% of demand at the peak moment,
-- far below its ~33% annual average, showing that peaks tend to happen on
-- cold, calm evenings when wind cannot be relied on.


-- ---------------------------------------------------------------------
-- Q4. What were the 10 windiest and 10 least windy days (2022-2025)?
-- ---------------------------------------------------------------------
WITH daily AS (
    SELECT
        d.full_date,
        d.day_name,
        100 * SUM(f.wind_mw) / SUM(f.demand_mw) AS wind_share_pct,
        SUM(f.demand_mw) * 0.25 / 1000          AS demand_gwh
    FROM fact_grid_15min f
    JOIN dim_date d ON f.date_key = d.date_key
    GROUP BY d.full_date, d.day_name
),
ranked AS (
    SELECT *,
        RANK() OVER (ORDER BY wind_share_pct DESC) AS rank_windiest,
        RANK() OVER (ORDER BY wind_share_pct ASC)  AS rank_calmest
    FROM daily
)
SELECT
    CASE WHEN rank_windiest <= 10 THEN 'Windiest' ELSE 'Calmest' END AS category,
    full_date,
    day_name,
    ROUND(wind_share_pct, 1) AS wind_share_pct,
    ROUND(demand_gwh, 1)     AS demand_gwh
FROM ranked
WHERE rank_windiest <= 10 OR rank_calmest <= 10
ORDER BY category DESC, wind_share_pct DESC;
-- Finding: All 10 windiest days fell between October and February, with half
-- in February; the record was 84.6% of demand on 23 Feb 2025. The calmest days
-- dropped to 0.9-1.9% wind share and were mostly in August (5 of 10), but calm
-- days also occur in winter: on 12 Nov 2024 wind supplied only 1.6% while daily
-- demand was 103.9 GWh, the highest of any day in this list. Wind can fall to
-- almost zero for whole days in any season, so backup supply is always needed.


-- ---------------------------------------------------------------------
-- Q5. How many hours per year did wind supply more than half of demand,
--     and how many hours did it supply less than 10%?
-- ---------------------------------------------------------------------
SELECT
    d.year,
    ROUND(SUM(f.wind_mw >= 0.5 * f.demand_mw) / 4, 0) AS hours_wind_over_50pct,
    ROUND(SUM(f.wind_mw <  0.1 * f.demand_mw) / 4, 0) AS hours_wind_under_10pct,
    ROUND(100 * SUM(f.wind_mw >= 0.5 * f.demand_mw) / COUNT(*), 1) AS pct_of_year_over_50
FROM fact_grid_15min f
JOIN dim_date d ON f.date_key = d.date_key
GROUP BY d.year
ORDER BY d.year;
-- Finding: Wind supplied more than half of demand for 31% of the year in
-- 2022-2023, but only about 25% in 2024-2025 (around 520 fewer hours, -19%),
-- because demand grew while wind output stayed flat. Low-wind periods did not
-- improve: wind supplied under 10% of demand for 1,600-2,000 hours every year,
-- equal to 70-80 full days.


-- ---------------------------------------------------------------------
-- Q6. How much available wind energy was wasted (dispatched down),
--     and is it getting worse?
--     Dispatch-down rate = wasted wind / available wind
-- ---------------------------------------------------------------------
SELECT
    d.year,
    ROUND(SUM(f.wind_available_mw)     * 0.25 / 1e6, 2) AS wind_available_twh,
    ROUND(SUM(f.wind_mw)               * 0.25 / 1e6, 2) AS wind_used_twh,
    ROUND(SUM(f.wind_dispatch_down_mw) * 0.25 / 1e6, 2) AS wind_wasted_twh,
    ROUND(100 * SUM(f.wind_dispatch_down_mw) / SUM(f.wind_available_mw), 1)
                                                         AS dispatch_down_rate_pct
FROM fact_grid_15min f
JOIN dim_date d ON f.date_key = d.date_key
GROUP BY d.year
ORDER BY d.year;
-- Finding: The share of available wind energy that was wasted (dispatched down)
-- rose every year, from 9.7% in 2022 to 13.1% in 2025. Wasted wind grew 46%
-- (1.17 to 1.71 TWh) while available wind grew only 8%, meaning new wind capacity
-- is increasingly not being used. Q7 shows waste is high both at midday (solar
-- overlap) and overnight (low demand), pointing to grid constraints and
-- curtailment as the main drivers rather than solar alone.


-- ---------------------------------------------------------------------
-- Q7. At what time of day is wind most often wasted? (2025)
-- ---------------------------------------------------------------------
SELECT
    t.hour_of_day,
    ROUND(AVG(f.wind_dispatch_down_mw), 0) AS avg_wind_wasted_mw,
    ROUND(AVG(f.demand_mw), 0)             AS avg_demand_mw,
    ROUND(100 * SUM(f.wind_dispatch_down_mw) / SUM(f.wind_available_mw), 1)
                                           AS dispatch_down_rate_pct
FROM fact_grid_15min f
JOIN dim_date d ON f.date_key = d.date_key
JOIN dim_time t ON f.time_key = t.time_key
WHERE d.year = 2025
GROUP BY t.hour_of_day
ORDER BY dispatch_down_rate_pct DESC;
-- Finding: In 2025, wind waste was highest at 13:00-14:00 (16.5%), when wind
-- overlaps with peak solar, and at 03:00-04:00 (15.7%), when demand is lowest.
-- It was lowest at 19:00-21:00 (9.6%), during the evening demand peak. Wind
-- is wasted when the system does not need it, so battery storage and shifting
-- demand (e.g. night-time EV charging) could move surplus wind to the evening peak.


-- ---------------------------------------------------------------------
-- Q8. Wind droughts: what were the longest unbroken periods when wind
--     supplied less than 10% of demand?
--     (gaps-and-islands technique with ROW_NUMBER)
-- ---------------------------------------------------------------------
WITH flagged AS (
    SELECT
        datetime_utc,
        datetime_local,
        ROW_NUMBER() OVER (ORDER BY datetime_utc) AS rn_all
    FROM fact_grid_15min
    WHERE wind_mw < 0.1 * demand_mw
),
islands AS (
    SELECT
        datetime_local,
        -- consecutive 15-min intervals share the same group value
        TIMESTAMPDIFF(MINUTE, '2022-01-01', datetime_utc) / 15 - rn_all AS grp
    FROM flagged
)
SELECT
    MIN(datetime_local)          AS drought_start,
    MAX(datetime_local)          AS drought_end,
    ROUND(COUNT(*) / 4, 1)       AS duration_hours
FROM islands
GROUP BY grp
ORDER BY duration_hours DESC
LIMIT 10;
-- Finding: The longest wind drought (wind below 10% of demand) lasted 125 hours
-- (5.2 days), from 7 to 12 Aug 2022. All top 10 droughts lasted 70+ hours (about
-- 3 days or more) and occurred in every season, including winter (10-13 Nov 2024
-- and 19-22 Jan 2025) when demand is high. Short-duration batteries cannot cover
-- multi-day droughts, so Ireland still needs interconnectors, long-duration storage
-- or dispatchable backup generation.


-- ---------------------------------------------------------------------
-- Q9. Is Ireland a net importer or exporter of electricity via its
--     interconnectors to Great Britain? (2023+, EWIC not published for 2022)
--     Positive = import into Ireland
-- ---------------------------------------------------------------------
SELECT
    d.year,
    ROUND(SUM(f.interconnector_net_mw) * 0.25 / 1e6, 2)                        AS net_import_twh,
    ROUND(SUM(GREATEST(f.interconnector_net_mw, 0)) * 0.25 / 1e6, 2)           AS imports_twh,
    ROUND(SUM(LEAST(f.interconnector_net_mw, 0)) * -0.25 / 1e6, 2)             AS exports_twh,
    ROUND(100 * SUM(f.interconnector_net_mw > 0) / COUNT(*), 1)                AS pct_time_importing
FROM fact_grid_15min f
JOIN dim_date d ON f.date_key = d.date_key
WHERE f.interconnector_net_mw IS NOT NULL
GROUP BY d.year
ORDER BY d.year;
-- Finding: Ireland is a strong net importer of electricity from Great Britain,
-- importing 79-87% of the time. Net imports rose from 1.7 TWh in 2023 to 4.5 TWh
-- in 2025 (about 2.6x), growing from 5% to 13% of Irish demand. Exports remained
-- very small (0.1-0.3 TWh). The rise reflects demand growing faster than domestic
-- wind output, plus new import capacity from the Greenlink interconnector (Jan 2025).


-- ---------------------------------------------------------------------
-- Q10. Does Ireland import more when the wind is low?
--      Average net import grouped by wind-share band (2023+)
-- ---------------------------------------------------------------------
SELECT
    CASE
        WHEN f.wind_mw < 0.1 * f.demand_mw THEN '1. Under 10%'
        WHEN f.wind_mw < 0.3 * f.demand_mw THEN '2. 10-30%'
        WHEN f.wind_mw < 0.5 * f.demand_mw THEN '3. 30-50%'
        ELSE                                    '4. Over 50%'
    END                                          AS wind_share_band,
    COUNT(*)                                     AS intervals,
    ROUND(AVG(f.interconnector_net_mw), 0)       AS avg_net_import_mw,
    ROUND(AVG(f.demand_mw), 0)                   AS avg_demand_mw
FROM fact_grid_15min f
WHERE f.interconnector_net_mw IS NOT NULL
GROUP BY wind_share_band
ORDER BY wind_share_band;
-- Finding: Ireland imports more electricity when wind is low. When wind supplied
-- under 10% of demand, average net imports were 564 MW, falling steadily to almost
-- zero (7 MW) when wind supplied over 50%. Average demand stayed almost constant
-- (3,815-3,884 MW) across all groups, confirming wind, not demand, drives imports.
-- Interconnectors act as Ireland's backup during calm periods, but even in high-wind
-- periods Ireland does not export much, while wind is being wasted (Q6-Q7).
USE irish_grid;

CREATE OR REPLACE VIEW vw_wind_droughts AS
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
        TIMESTAMPDIFF(MINUTE, '2022-01-01', datetime_utc) / 15 - rn_all AS grp
    FROM flagged
)
SELECT
    MIN(datetime_local)        AS drought_start,
    MAX(datetime_local)        AS drought_end,
    ROUND(COUNT(*) / 4, 1)     AS duration_hours,
    ROUND(COUNT(*) / 96, 1)    AS duration_days,
    YEAR(MIN(datetime_local))  AS drought_year
FROM islands
GROUP BY grp
HAVING COUNT(*) >= 96;          -- droughts lasting at least 24 hours

-- Check: number of 24h+ droughts per year
SELECT drought_year, COUNT(*) AS droughts, MAX(duration_hours) AS longest_hours
FROM vw_wind_droughts
GROUP BY drought_year
ORDER BY drought_year;

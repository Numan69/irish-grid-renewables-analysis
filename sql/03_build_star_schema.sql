USE irish_grid;

DROP TABLE IF EXISTS fact_grid_15min;
DROP TABLE IF EXISTS dim_date;
DROP TABLE IF EXISTS dim_time;

-- ---------- dim_date ----------
CREATE TABLE dim_date (
    date_key      INT PRIMARY KEY,          -- e.g. 20250115
    full_date     DATE NOT NULL,
    year          SMALLINT,
    quarter       TINYINT,
    month_num     TINYINT,
    month_name    VARCHAR(10),
    month_short   CHAR(3),
    day_of_month  TINYINT,
    day_of_week   TINYINT,                  -- 1 = Monday ... 7 = Sunday
    day_name      VARCHAR(10),
    is_weekend    BOOLEAN,
    season        VARCHAR(10)
);

INSERT INTO dim_date
SELECT DISTINCT
    CAST(DATE_FORMAT(date_local, '%Y%m%d') AS UNSIGNED),
    date_local,
    YEAR(date_local),
    QUARTER(date_local),
    MONTH(date_local),
    MONTHNAME(date_local),
    LEFT(MONTHNAME(date_local), 3),
    DAY(date_local),
    WEEKDAY(date_local) + 1,
    DAYNAME(date_local),
    WEEKDAY(date_local) >= 5,
    CASE
        WHEN MONTH(date_local) IN (12, 1, 2) THEN 'Winter'
        WHEN MONTH(date_local) IN (3, 4, 5)  THEN 'Spring'
        WHEN MONTH(date_local) IN (6, 7, 8)  THEN 'Summer'
        ELSE 'Autumn'
    END
FROM stg_grid_15min;

-- ---------- dim_time ----------
CREATE TABLE dim_time (
    time_key      TINYINT PRIMARY KEY,      -- 0 to 95
    time_of_day   TIME,
    hour_of_day   TINYINT,
    period_label  VARCHAR(20)
);

INSERT INTO dim_time
SELECT DISTINCT
    HOUR(datetime_local) * 4 + MINUTE(datetime_local) DIV 15,
    TIME(datetime_local),
    HOUR(datetime_local),
    CASE
        WHEN HOUR(datetime_local) BETWEEN 0  AND 6  THEN 'Night'
        WHEN HOUR(datetime_local) BETWEEN 7  AND 16 THEN 'Day'
        WHEN HOUR(datetime_local) BETWEEN 17 AND 19 THEN 'Evening Peak'
        ELSE 'Late Evening'
    END
FROM stg_grid_15min;

-- ---------- fact_grid_15min ----------
CREATE TABLE fact_grid_15min (
    datetime_utc            DATETIME PRIMARY KEY,
    datetime_local          DATETIME NOT NULL,
    date_key                INT NOT NULL,
    time_key                TINYINT NOT NULL,
    demand_mw               DECIMAL(10,3),
    generation_mw           DECIMAL(10,3),
    wind_mw                 DECIMAL(10,3),
    wind_available_mw       DECIMAL(10,3),
    wind_dispatch_down_mw   DECIMAL(10,3),
    solar_mw                DECIMAL(10,3),
    solar_available_mw      DECIMAL(10,3),
    hydro_mw                DECIMAL(10,3),
    renewable_mw            DECIMAL(10,3),
    ewic_mw                 DECIMAL(10,3) NULL,
    greenlink_mw            DECIMAL(10,3),
    interconnector_net_mw   DECIMAL(10,3) NULL,
    snsp_all_island         DECIMAL(8,5),
    is_dst_repeat_hour      BOOLEAN,
    FOREIGN KEY (date_key) REFERENCES dim_date(date_key),
    FOREIGN KEY (time_key) REFERENCES dim_time(time_key),
    INDEX idx_date (date_key),
    INDEX idx_time (time_key)
);

INSERT INTO fact_grid_15min
SELECT
    datetime_utc,
    datetime_local,
    CAST(DATE_FORMAT(date_local, '%Y%m%d') AS UNSIGNED),
    HOUR(datetime_local) * 4 + MINUTE(datetime_local) DIV 15,
    demand_mw, generation_mw,
    wind_mw, wind_available_mw, wind_dispatch_down_mw,
    solar_mw, solar_available_mw, hydro_mw, renewable_mw,
    ewic_mw, greenlink_mw, interconnector_net_mw,
    snsp_all_island, is_dst_repeat_hour
FROM stg_grid_15min;

-- Expected: dim_date 1461, dim_time 96, fact 140256
SELECT 'dim_date' AS table_name, COUNT(*) AS row_count FROM dim_date
UNION ALL SELECT 'dim_time', COUNT(*) FROM dim_time
UNION ALL SELECT 'fact_grid_15min', COUNT(*) FROM fact_grid_15min;

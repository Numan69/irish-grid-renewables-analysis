CREATE DATABASE IF NOT EXISTS irish_grid;
USE irish_grid;

DROP TABLE IF EXISTS stg_grid_15min;

CREATE TABLE stg_grid_15min (
    datetime_utc            DATETIME      NOT NULL,
    datetime_local          DATETIME      NOT NULL,
    gmt_offset              TINYINT       NOT NULL,
    date_local              DATE          NOT NULL,
    year                    SMALLINT      NOT NULL,
    demand_mw               DECIMAL(10,3),
    generation_mw           DECIMAL(10,3),
    wind_mw                 DECIMAL(10,3),
    wind_available_mw       DECIMAL(10,3),
    wind_dispatch_down_mw   DECIMAL(10,3),
    solar_mw                DECIMAL(10,3),
    solar_available_mw      DECIMAL(10,3),
    hydro_mw                DECIMAL(10,3),
    renewable_mw            DECIMAL(10,3),
    ewic_mw                 DECIMAL(10,3) NULL,   -- NULL for 2022 (not published)
    greenlink_mw            DECIMAL(10,3),
    interconnector_net_mw   DECIMAL(10,3) NULL,
    ewic_data_available     BOOLEAN,
    snsp_all_island         DECIMAL(8,5),
    demand_mwh              DECIMAL(12,4),
    wind_mwh                DECIMAL(12,4),
    solar_mwh               DECIMAL(12,4),
    hydro_mwh               DECIMAL(12,4),
    renewable_mwh           DECIMAL(12,4),
    wind_dispatch_down_mwh  DECIMAL(12,4),
    is_dst_repeat_hour      BOOLEAN,
    source_file             VARCHAR(100),
    PRIMARY KEY (datetime_utc)
);

USE irish_grid;

TRUNCATE TABLE stg_grid_15min;

LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/ie_grid_15min_2022_2025.csv'
INTO TABLE stg_grid_15min
FIELDS TERMINATED BY ','
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(datetime_utc, datetime_local, gmt_offset, date_local, year,
 demand_mw, generation_mw, wind_mw, wind_available_mw, wind_dispatch_down_mw,
 solar_mw, solar_available_mw, hydro_mw, renewable_mw,
 @ewic_mw, greenlink_mw, @interconnector_net_mw, @ewic_data_available,
 snsp_all_island,
 demand_mwh, wind_mwh, solar_mwh, hydro_mwh, renewable_mwh, wind_dispatch_down_mwh,
 @is_dst_repeat_hour, @source_file)
SET
    -- Empty cells must become NULL (otherwise MySQL would store 0 or fail)
    ewic_mw               = NULLIF(@ewic_mw, ''),
    interconnector_net_mw = NULLIF(@interconnector_net_mw, ''),
    -- Python writes True/False; MySQL needs 1/0
    ewic_data_available   = (@ewic_data_available = 'True'),
    is_dst_repeat_hour    = (@is_dst_repeat_hour = 'True'),
    -- Remove Windows line-ending character if present
    source_file           = TRIM(TRAILING '\r' FROM @source_file);

-- Should return 140256
SELECT COUNT(*) AS rows_loaded FROM stg_grid_15min;

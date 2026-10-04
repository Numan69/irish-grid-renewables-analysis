"""
clean_eirgrid_data.py
---------------------
Step 2 of the Irish Grid Renewables project.

Reads the raw EirGrid quarter-hourly Excel files (2022-2025), keeps the
Ireland (IE) columns, fixes daylight-saving-time issues, handles missing
interconnector data, adds useful derived columns, runs data quality checks,
and saves ONE clean CSV ready for SQL / Power BI.

Run from the project root folder:
    python python/clean_eirgrid_data.py
"""

from pathlib import Path

import numpy as np
import pandas as pd

RAW_DIR = Path("data/raw")
OUT_DIR = Path("data/processed")
OUT_FILE = OUT_DIR / "ie_grid_15min_2022_2025.csv"

# Raw EirGrid column name  ->  clean snake_case name
COLUMNS = {
    "DateTime": "datetime_local",
    "GMT Offset": "gmt_offset",
    "IE Demand": "demand_mw",
    "IE Generation": "generation_mw",
    "IE Wind Availability": "wind_available_mw",
    "IE Wind Generation": "wind_mw",
    "IE Solar Availability": "solar_available_mw",
    "IE Solar Generation": "solar_mw",
    "IE Hydro": "hydro_mw",
    "EWIC I/C": "ewic_mw",
    "Greenlink I/C": "greenlink_mw",
    "SNSP": "snsp_all_island",
}

GREENLINK_START = pd.Timestamp("2025-01-29")  # Greenlink began operating


# ---------------------------------------------------------------------------
# 1. LOAD
# ---------------------------------------------------------------------------
def load_raw_files() -> pd.DataFrame:
    files = sorted(RAW_DIR.glob("*.xlsx"))
    if not files:
        raise FileNotFoundError(f"No .xlsx files found in {RAW_DIR.resolve()}")

    frames = []
    for f in files:
        df = pd.read_excel(f, sheet_name="System Data")
        # Keep only the columns we need (ignores the notes column at the end)
        keep = [c for c in COLUMNS if c in df.columns]
        df = df[keep].rename(columns=COLUMNS)
        # The 2022-2024 files have no Greenlink column -> add it as empty
        if "greenlink_mw" not in df.columns:
            df["greenlink_mw"] = np.nan
        df["source_file"] = f.name
        print(f"Loaded {f.name}: {len(df):,} rows")
        frames.append(df)

    combined = pd.concat(frames, ignore_index=True)
    # Drop any fully blank rows (e.g. trailing empty Excel rows)
    combined = combined.dropna(subset=["datetime_local"])
    return combined


# ---------------------------------------------------------------------------
# 2. CLEAN
# ---------------------------------------------------------------------------
def clean(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    df["datetime_local"] = pd.to_datetime(df["datetime_local"])
    df["gmt_offset"] = df["gmt_offset"].astype(int)

    # --- Daylight saving time fix -----------------------------------------
    # Local (Irish) time has a missing hour in March and a repeated hour in
    # October. Converting to UTC using the GMT Offset column gives a clean,
    # unique timeline with no gaps and no duplicates.
    df["datetime_utc"] = df["datetime_local"] - pd.to_timedelta(df["gmt_offset"], unit="h")

    # Remove exact duplicate intervals (in case files overlap)
    before = len(df)
    df = df.drop_duplicates(subset="datetime_utc", keep="last")
    if len(df) != before:
        print(f"Removed {before - len(df)} overlapping duplicate rows")

    # --- Interconnectors ----------------------------------------------------
    # Greenlink did not exist before 29 Jan 2025 -> true value is 0, not missing
    pre_greenlink = df["datetime_local"] < GREENLINK_START
    df.loc[pre_greenlink & df["greenlink_mw"].isna(), "greenlink_mw"] = 0
    # EWIC existed in 2022 but EirGrid did not publish the data -> keep as NULL
    df["ewic_data_available"] = df["ewic_mw"].notna()
    # Net interconnector flow (positive = import into Ireland), NULL if EWIC unknown
    df["interconnector_net_mw"] = df["ewic_mw"] + df["greenlink_mw"]

    # --- Solar --------------------------------------------------------------
    # Solar reporting began April 2023; earlier values are 0 by definition
    df[["solar_mw", "solar_available_mw"]] = df[["solar_mw", "solar_available_mw"]].fillna(0)

    # --- Derived columns ----------------------------------------------------
    # Wind dispatch-down (curtailment + constraints): available but not used
    df["wind_dispatch_down_mw"] = (df["wind_available_mw"] - df["wind_mw"]).clip(lower=0)
    df["renewable_mw"] = df["wind_mw"] + df["solar_mw"] + df["hydro_mw"]

    # Energy: each row is 15 minutes, so MWh = MW x 0.25
    for col in ["demand_mw", "wind_mw", "solar_mw", "hydro_mw",
                "renewable_mw", "wind_dispatch_down_mw"]:
        df[col.replace("_mw", "_mwh")] = df[col] * 0.25

    # Date parts (local time, which is what people use for reporting)
    df["date"] = df["datetime_local"].dt.date
    df["year"] = df["datetime_local"].dt.year
    df["is_dst_repeat_hour"] = df.duplicated(subset="datetime_local", keep=False)

    df = df.sort_values("datetime_utc").reset_index(drop=True)

    ordered = [
        "datetime_utc", "datetime_local", "gmt_offset", "date", "year",
        "demand_mw", "generation_mw",
        "wind_mw", "wind_available_mw", "wind_dispatch_down_mw",
        "solar_mw", "solar_available_mw", "hydro_mw", "renewable_mw",
        "ewic_mw", "greenlink_mw", "interconnector_net_mw", "ewic_data_available",
        "snsp_all_island",
        "demand_mwh", "wind_mwh", "solar_mwh", "hydro_mwh",
        "renewable_mwh", "wind_dispatch_down_mwh",
        "is_dst_repeat_hour", "source_file",
    ]
    df = df[ordered]

    # Round to sensible precision (removes floating-point noise such as
    # 1126.3700000000002, keeps the CSV smaller and loads cleanly into SQL)
    mw_cols = [c for c in df.columns if c.endswith("_mw")]
    mwh_cols = [c for c in df.columns if c.endswith("_mwh")]
    df[mw_cols] = df[mw_cols].round(3)
    df[mwh_cols] = df[mwh_cols].round(4)
    df["snsp_all_island"] = df["snsp_all_island"].round(5)
    return df


# ---------------------------------------------------------------------------
# 3. DATA QUALITY CHECKS
# ---------------------------------------------------------------------------
def quality_report(df: pd.DataFrame) -> None:
    print("\n========== DATA QUALITY REPORT ==========")

    # Completeness: every 15-minute UTC interval should exist exactly once
    start, end = df["datetime_utc"].min(), df["datetime_utc"].max()
    expected = pd.date_range(start, end, freq="15min")
    missing = expected.difference(df["datetime_utc"])
    print(f"Date range (UTC): {start}  ->  {end}")
    print(f"Rows: {len(df):,}   Expected: {len(expected):,}   Missing intervals: {len(missing)}")
    print(f"Duplicate UTC timestamps: {df['datetime_utc'].duplicated().sum()}")

    # Rows per year
    print("\nRows per year:")
    print(df.groupby("year").size().to_string())

    # Null values
    nulls = df.isna().sum()
    nulls = nulls[nulls > 0]
    print("\nColumns with NULL values:")
    print(nulls.to_string() if len(nulls) else "  none")

    # Sanity checks
    print("\nSanity checks (count of rows failing):")
    checks = {
        "demand <= 0": (df["demand_mw"] <= 0).sum(),
        "wind < 0": (df["wind_mw"] < 0).sum(),
        "solar < 0": (df["solar_mw"] < 0).sum(),
        "wind > wind available (+5 MW tolerance)":
            (df["wind_mw"] > df["wind_available_mw"] + 5).sum(),
    }
    for name, n in checks.items():
        print(f"  {name}: {n}")

    # Annual summary - compare these against EirGrid's System & Renewable Summary Report
    annual = df.groupby("year").agg(
        demand_twh=("demand_mwh", lambda s: s.sum() / 1e6),
        wind_twh=("wind_mwh", lambda s: s.sum() / 1e6),
        solar_twh=("solar_mwh", lambda s: s.sum() / 1e6),
        peak_demand_mw=("demand_mw", "max"),
        wind_dispatch_down_twh=("wind_dispatch_down_mwh", lambda s: s.sum() / 1e6),
    )
    annual["wind_share_pct"] = 100 * annual["wind_twh"] / annual["demand_twh"]
    annual["solar_share_pct"] = 100 * annual["solar_twh"] / annual["demand_twh"]
    print("\nAnnual summary:")
    print(annual.round(2).to_string())
    print("=========================================\n")


# ---------------------------------------------------------------------------
def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    raw = load_raw_files()
    clean_df = clean(raw)
    quality_report(clean_df)
    clean_df.to_csv(OUT_FILE, index=False)
    print(f"Saved clean dataset: {OUT_FILE}  ({len(clean_df):,} rows, {clean_df.shape[1]} columns)")


if __name__ == "__main__":
    main()

"""
Run this script once to pull data from BigQuery and write data.js.
Usage: python3 export_data.py
"""
import json
from google.cloud import bigquery

PROJECT = "m2-dataset-study"
LOCATION = "EU"
client = bigquery.Client(project=PROJECT)

def q(sql):
    return client.query(sql, location=LOCATION).to_dataframe()

print("Exporting Chapter 1 — demand patterns...")
demand = q("""
    SELECT hour_of_day, day_type, SUM(departures) AS total_departures
    FROM `m2-dataset-study.london_bicycles_dev_marts.mart_station_demand`
    GROUP BY hour_of_day, day_type
    ORDER BY hour_of_day
""")

print("Exporting Chapter 2 — station flow...")
stations = q("""
    SELECT
        station_name, latitude, longitude,
        total_departures, total_arrivals, net_outflow,
        ROUND(imbalance_pct, 1) AS imbalance_pct,
        flow_role, docks_count
    FROM `m2-dataset-study.london_bicycles_dev_dimensions.dim_station`
    WHERE latitude IS NOT NULL AND longitude IS NOT NULL
""")

print("Exporting Chapter 3 — seasonality...")
monthly = q("""
    SELECT
        FORMAT_DATE('%Y-%m', month_start) AS month,
        total_rentals, avg_duration_min,
        is_disrupted_month, disruption_type, duration_anomaly_flag,
        mom_rental_change_pct
    FROM `m2-dataset-study.london_bicycles_dev_marts.mart_monthly_trends`
    ORDER BY month_start
""")

print("Exporting Chapter 4 — nightlife...")
nightlife_dow = q("""
    SELECT
        CASE EXTRACT(DAYOFWEEK FROM start_date)
            WHEN 1 THEN 'Sunday'   WHEN 2 THEN 'Monday'
            WHEN 3 THEN 'Tuesday'  WHEN 4 THEN 'Wednesday'
            WHEN 5 THEN 'Thursday' WHEN 6 THEN 'Friday'
            WHEN 7 THEN 'Saturday' END AS day_name,
        EXTRACT(DAYOFWEEK FROM start_date) AS dow_num,
        SUM(CASE WHEN EXTRACT(HOUR FROM start_date) = 0 THEN 1 ELSE 0 END) AS midnight_rentals
    FROM `m2-dataset-study.london_bicycles_dev_facts.fact_rentals`
    GROUP BY day_name, dow_num
    ORDER BY dow_num
""")

nightlife_stations = q("""
    SELECT
        station_name, latitude, longitude,
        SUM(departures) AS total_nightlife_departures,
        ROUND(AVG(avg_duration_min), 1) AS avg_duration_min
    FROM `m2-dataset-study.london_bicycles_dev_marts.mart_nightlife_demand`
    WHERE station_name IS NOT NULL AND latitude IS NOT NULL
    GROUP BY station_name, latitude, longitude
    ORDER BY total_nightlife_departures DESC
    LIMIT 15
""")

print("Exporting Chapter 5 — bike utilisation...")
bikes = q("""
    SELECT
        bike_id, total_rentals, total_hours_ridden,
        avg_rentals_per_day, active_lifespan_days,
        has_workshop_record, exceeds_retirement_threshold,
        is_high_risk_no_maintenance, model_category
    FROM `m2-dataset-study.london_bicycles_dev_marts.mart_bike_utilisation`
    WHERE bike_id IS NOT NULL
""")

data = {
    "demand": demand.to_dict(orient="records"),
    "stations": stations.to_dict(orient="records"),
    "monthly": monthly.to_dict(orient="records"),
    "nightlife_dow": nightlife_dow.to_dict(orient="records"),
    "nightlife_stations": nightlife_stations.to_dict(orient="records"),
    "bikes": bikes.to_dict(orient="records"),
}

with open("data.js", "w") as f:
    f.write("const DATA = ")
    f.write(json.dumps(data, default=str))
    f.write(";")

print("Done — data.js written.")

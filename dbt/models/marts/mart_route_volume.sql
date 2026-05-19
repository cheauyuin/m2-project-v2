{{
  config(materialized='table')
}}

/*
  Top routes by trip count, split by trip_segment.
  Excludes round trips, maintenance trips, and missing-end-station records
  for clean origin-destination analysis.
*/

with fact as (
    select
        start_station_id,
        start_station_name,
        end_station_id,
        end_station_name,
        duration_min,
        trip_segment,
        season,
        is_weekend
    from {{ ref('fact_rentals') }}
    where not is_round_trip
      and not is_missing_end_id
      and not is_anomalous_duration
      and start_station_id is not null
      and end_station_id is not null
),

route_stats as (
    select
        start_station_id,
        start_station_name,
        end_station_id,
        end_station_name,
        trip_segment,
        count(*)                        as trip_count,
        round(avg(duration_min), 1)     as avg_duration_min,
        round(approx_quantiles(duration_min, 100)[offset(50)], 1) as median_duration_min,
        countif(season = 'Summer')      as summer_trips,
        countif(season = 'Winter')      as winter_trips,
        countif(is_weekend)             as weekend_trips
    from fact
    group by
        start_station_id, start_station_name,
        end_station_id, end_station_name,
        trip_segment
)

select
    r.*,
    ss.latitude   as start_lat,
    ss.longitude  as start_lon,
    es.latitude   as end_lat,
    es.longitude  as end_lon,

    -- Approximate straight-line distance (km) using Haversine approximation
    -- BigQuery lacks degrees()/radians(); use inline: radians(x) = x*pi/180, degrees(x) = x*180/pi
    round(
        111.045 * (180 / ACOS(-1)) * acos(least(1.0,
            cos(ss.latitude * ACOS(-1) / 180) * cos(es.latitude * ACOS(-1) / 180) *
            cos((es.longitude - ss.longitude) * ACOS(-1) / 180) +
            sin(ss.latitude * ACOS(-1) / 180) * sin(es.latitude * ACOS(-1) / 180)
        )), 2
    )                                   as straight_line_km

from route_stats r
left join {{ ref('dim_station') }} ss on r.start_station_id = ss.station_id
left join {{ ref('dim_station') }} es on r.end_station_id   = es.station_id

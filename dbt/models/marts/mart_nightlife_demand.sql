{{
  config(materialized='table')
}}

/*
  Nightlife segment mart (Surprise Finding §3.2).
  Friday/Saturday nights 00:00–04:00. Saturday midnight alone: 210k rentals.
  Used to identify stations to pre-position bikes for nightlife demand.
*/

with nightlife_trips as (
    select
        start_station_id,
        start_station_name,
        end_station_id,
        end_station_name,
        extract(hour from start_date)   as hour_of_day,
        extract(dayofweek from start_date) as day_of_week,  -- 6=Fri, 7=Sat
        duration_min,
        is_round_trip,
        season
    from {{ ref('fact_rentals') }}
    where trip_segment = 'nightlife'
),

station_demand as (
    select
        start_station_id                as station_id,
        start_station_name              as station_name,
        hour_of_day,
        day_of_week,
        case day_of_week when 6 then 'Friday Night' else 'Saturday Night' end as night_label,
        season,
        count(*)                        as departures,
        round(avg(duration_min), 1)     as avg_duration_min,
        countif(is_round_trip)          as round_trips
    from nightlife_trips
    where start_station_id is not null
    group by station_id, station_name, hour_of_day, day_of_week, season
),

top_routes as (
    select
        start_station_name,
        end_station_name,
        count(*)                        as trip_count,
        round(avg(duration_min), 1)     as avg_duration_min
    from nightlife_trips
    where start_station_id is not null
      and end_station_id is not null
      and not is_round_trip
    group by start_station_name, end_station_name
)

select
    sd.*,
    ds.latitude,
    ds.longitude,
    ds.docks_count,
    ds.is_structural_imbalance
from station_demand sd
left join {{ ref('dim_station') }} ds on sd.station_id = ds.station_id

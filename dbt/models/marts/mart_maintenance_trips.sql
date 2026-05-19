{{
  config(materialized='table')
}}

/*
  Separates maintenance trips from customer journeys (Surprise Finding §3.1).
  Workshop-destination records: avg duration 131–178 hrs, max 65.3 days.
  Useful for fleet maintenance tracking.
*/

with maintenance as (
    select *
    from {{ ref('stg_cycle_hire') }}
    where is_maintenance_trip
)

select
    rental_id,
    bike_id,
    start_date,
    end_date,
    start_station_name,
    end_station_name,
    duration_sec,
    round(duration_sec / 3600.0, 1)     as duration_hours,
    round(duration_sec / 86400.0, 1)    as duration_days,

    case
        when lower(end_station_name) like '%clapham%'    then 'Clapham Workshop'
        when lower(end_station_name) like '%penton%'     then 'Penton Workshop'
        when lower(end_station_name) like '%electrical%' then 'Electrical Workshop'
        else 'Other Workshop'
    end                                 as workshop_name,

    -- Categorise by workshop duration
    case
        when duration_sec > 86400 * 30  then 'long_term_30d+'
        when duration_sec > 86400 * 7   then 'medium_term_7d+'
        when duration_sec > 86400       then 'short_term_1d+'
        else 'same_day'
    end                                 as maintenance_duration_bucket

from maintenance

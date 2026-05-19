{{
  config(
    materialized='incremental',
    incremental_strategy='insert_overwrite',
    partition_by={
      'field': 'start_date',
      'data_type': 'timestamp',
      'granularity': 'month'
    },
    cluster_by=['start_station_id', 'end_station_id'],
    on_schema_change='fail'
  )
}}

/*
  Central fact table. One row per clean customer rental.

  Excluded (routed to dedicated marts):
    - is_invalid_duration  : zero/negative durations (system error)
    - is_end_before_start  : end_date precedes start_date (source data error, 388 records)
    - is_incomplete_trip   : bike never returned (→ mart_incomplete_trips)
    - is_maintenance_trip  : workshop destinations (→ mart_maintenance_trips)
    - is_ghost_end         : end_date but no station (203 records)

  Retained with flags:
    - is_anomalous_duration : > 24hrs but valid customer trip context
    - is_missing_end_id    : ID null but name present (still has route value)
    - is_unknown_bike      : bike_id null (15 records)
*/

with hire as (
    select * from {{ ref('stg_cycle_hire') }}
    where not is_invalid_duration
      and not is_end_before_start
      and not is_incomplete_trip
      and not is_maintenance_trip
      and not is_ghost_end

    {% if is_incremental() %}
      -- Only process new monthly partitions
      and start_date >= (select max(start_date) from {{ this }})
    {% endif %}
),

dim_date as (
    select date_id, date, is_weekend, is_uk_bank_holiday,
           is_disrupted_period, disruption_type, season, is_nightlife_day
    from {{ ref('dim_date') }}
),

enriched as (
    select
        h.rental_id,
        h.bike_id,
        h.start_station_id,
        h.end_station_id,
        cast(format_timestamp('%Y%m%d', h.start_date) as int64) as date_id,

        h.start_date,
        h.end_date,
        h.start_station_name,
        h.end_station_name,

        h.duration_sec,
        h.duration_min,

        -- Round trip: same station start and end
        h.start_station_id = h.end_station_id                  as is_round_trip,

        -- Trip segment — the key analytical dimension
        case
            when extract(dayofweek from h.start_date) in (6, 7)  -- Fri/Sat
             and extract(hour from h.start_date) between 0 and 4
            then 'nightlife'

            when extract(dayofweek from h.start_date) not in (1, 7) -- Mon–Fri
             and extract(hour from h.start_date) between 6 and 9
            then 'commute_am'

            when extract(dayofweek from h.start_date) not in (1, 7)
             and extract(hour from h.start_date) between 16 and 19
            then 'commute_pm'

            when extract(dayofweek from h.start_date) in (1, 7)  -- Sat/Sun
             and extract(hour from h.start_date) between 9 and 18
            then 'leisure'

            when extract(hour from h.start_date) between 0 and 5
            then 'night'

            else 'daytime'
        end                                                     as trip_segment,

        -- Cleaning flags carried forward for transparency
        h.is_anomalous_duration,
        h.is_missing_end_id,
        h.is_unknown_bike,
        h.start_id_was_resolved,
        h.bike_model

    from hire h
)

select
    e.*,
    d.is_weekend,
    d.is_uk_bank_holiday,
    d.is_disrupted_period,
    d.disruption_type,
    d.season
from enriched e
left join dim_date d on e.date_id = d.date_id

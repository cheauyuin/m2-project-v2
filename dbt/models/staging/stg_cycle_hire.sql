{{
  config(materialized='view')
}}

/*
  Staging model for cycle_hire.

  Cleaning decisions (see report §4):
  - duration_ms DROPPED  : fully redundant (= duration × 1000, always co-null)
  - terminal columns DROPPED : 99.7% NULL, never populated
  - end_station_priority_id DROPPED : 99.7% NULL, never populated
  - bike_model '' → NULL  : empty string treated the same as NULL
  - All anomalies FLAGGED, never silently dropped
*/

with source as (
    select * from {{ source('london_bicycles', 'cycle_hire') }}
),

-- Resolve ~95% of NULL start_station_ids (2016 Aug–Sep window)
-- by joining names back to known id mapping from the full dataset
station_name_map as (
    select distinct
        start_station_name as station_name,
        first_value(start_station_id ignore nulls)
            over (partition by start_station_name order by start_date) as resolved_id
    from source
    where start_station_id is not null
),

cleaned as (
    select
        s.rental_id,
        s.bike_id,
        nullif(trim(s.bike_model), '')                             as bike_model,

        s.start_date,
        s.end_date,

        coalesce(s.start_station_id, m.resolved_id)               as start_station_id,
        s.start_station_name,
        s.start_station_id is null and s.start_station_name is not null
            and m.resolved_id is not null                          as start_id_was_resolved,

        s.end_station_id,
        s.end_station_name,

        s.duration                                                 as duration_sec,
        round(s.duration / 60.0, 2)                               as duration_min,

        -- ── Cleaning flags ───────────────────────────────────────────────────
        -- Incomplete trip: bike never returned (no end_date, no end_station)
        (s.duration is null and s.end_date is null)                as is_incomplete_trip,

        -- Invalid duration: system error (zero or negative)
        (s.duration is not null and s.duration <= 0)               as is_invalid_duration,

        -- Inverted timestamps: end_date precedes start_date (source data error)
        (s.end_date is not null and s.end_date < s.start_date)     as is_end_before_start,

        -- Maintenance trip: bike sent to workshop (not a customer journey)
        lower(s.end_station_name) like '%workshop%'                as is_maintenance_trip,

        -- Extreme outlier: > 24 hrs (domain-driven cap; see report §4.4)
        (s.duration > {{ var('duration_cap_sec') }}
            and not lower(coalesce(s.end_station_name,'')) like '%workshop%')
                                                                   as is_anomalous_duration,

        -- Missing end station ID but name available (resolvable via lookup)
        (s.end_station_id is null
            and s.end_station_name is not null)                    as is_missing_end_id,

        -- Ghost record: end_date exists but no station info at all
        (s.end_station_id is null
            and s.end_station_name is null
            and s.end_date is not null)                            as is_ghost_end,

        -- Unknown bike: bike_id not recorded (15 records, Jun 2017)
        (s.bike_id is null)                                        as is_unknown_bike

    from source s
    left join station_name_map m
        on s.start_station_name = m.station_name
        and s.start_station_id is null
)

select * from cleaned

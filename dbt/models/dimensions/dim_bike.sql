{{
  config(materialized='table')
}}

/*
  dim_bike builds one row per bike from the hire history.
  Computes cumulative usage and flags bikes exceeding retirement thresholds.
  bike_model tagging only exists from 2022 — unknown model mapped to 'Unknown'.
*/

with hire as (
    select * from {{ ref('stg_cycle_hire') }}
    -- Exclude maintenance trips and incomplete trips from usage metrics
    where not is_maintenance_trip
      and not is_incomplete_trip
      and not is_invalid_duration
      and not is_ghost_end
      and bike_id is not null
),

bike_stats as (
    select
        bike_id,
        -- Most-recent non-null model wins (NULL model = pre-2022, before tagging)
        max(bike_model)                                 as bike_model,

        count(*)                                        as total_rentals,
        round(sum(duration_sec) / 3600.0, 1)           as total_hours_ridden,
        round(avg(duration_min), 1)                     as avg_trip_min,

        min(start_date)                                 as first_seen,
        max(start_date)                                 as last_seen,

        date_diff(
            date(max(start_date)),
            date(min(start_date)),
            day
        )                                               as active_lifespan_days,

        countif(is_anomalous_duration)                  as anomalous_trip_count

    from hire
    group by bike_id
)

select
    bike_id,

    coalesce(bike_model, 'Unknown')                     as bike_model,
    case
        when bike_model = 'PBSC_EBIKE' then 'E-Bike'
        when bike_model = 'CLASSIC'    then 'Classic'
        else 'Unknown'
    end                                                 as model_category,

    total_rentals,
    total_hours_ridden,
    avg_trip_min,
    first_seen,
    last_seen,
    active_lifespan_days,
    anomalous_trip_count,

    -- Retirement thresholds (vars defined in dbt_project.yml)
    total_rentals > {{ var('bike_retirement_rentals') }}
        or total_hours_ridden > {{ var('bike_retirement_hours') }}
                                                        as exceeds_retirement_threshold,

    round(total_rentals / nullif(active_lifespan_days, 0), 1) as avg_rentals_per_day

from bike_stats

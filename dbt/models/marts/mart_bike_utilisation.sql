{{
  config(materialized='table')
}}

/*
  Bike utilisation mart (Surprise Finding §3.4).
  Aggregates full rental history per bike. Flags bikes over retirement thresholds
  with no workshop record — potential safety risk or maintenance data gap.
*/

with fact as (
    select
        bike_id,
        duration_min,
        start_date,
        is_anomalous_duration
    from {{ ref('fact_rentals') }}
    where bike_id is not null
),

maintenance as (
    -- Bikes that appear in workshop-destination records
    select distinct bike_id
    from {{ ref('stg_cycle_hire') }}
    where is_maintenance_trip
      and bike_id is not null
),

utilisation as (
    select
        f.bike_id,
        count(*)                                            as total_rentals,
        round(sum(f.duration_min) / 60.0, 1)               as total_hours_ridden,
        round(avg(f.duration_min), 1)                      as avg_trip_min,
        min(f.start_date)                                  as first_rental,
        max(f.start_date)                                  as last_rental,
        date_diff(date(max(f.start_date)),
                  date(min(f.start_date)), day)            as active_lifespan_days,
        countif(f.is_anomalous_duration)                   as anomalous_rentals,
        max(m.bike_id) is not null                         as has_workshop_record
    from fact f
    left join maintenance m on f.bike_id = m.bike_id
    group by f.bike_id
)

select
    u.*,
    b.bike_model,
    b.model_category,
    b.exceeds_retirement_threshold,
    round(u.total_rentals /
          nullif(u.active_lifespan_days, 0), 1)            as avg_rentals_per_day,

    -- High-risk flag: over threshold AND no workshop record in data
    b.exceeds_retirement_threshold
        and not u.has_workshop_record                       as is_high_risk_no_maintenance

from utilisation u
left join {{ ref('dim_bike') }} b on u.bike_id = b.bike_id
order by total_rentals desc

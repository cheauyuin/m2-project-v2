{{
  config(materialized='table')
}}

/*
  Monthly KPI mart used for seasonality analysis, exec dashboards, and anomaly detection.
  Joins external_events to flag disrupted months.
*/

with fact as (
    select
        date_trunc(start_date, month)                       as month_start,
        extract(year from start_date)                       as year,
        extract(month from start_date)                      as month,
        duration_min,
        trip_segment,
        is_round_trip,
        is_anomalous_duration,
        is_disrupted_period,
        disruption_type,
        season,
        start_station_id,
        end_station_id,
        bike_id
    from {{ ref('fact_rentals') }}
),

monthly as (
    select
        month_start,
        year,
        month,
        season,

        count(*)                                            as total_rentals,
        countif(trip_segment = 'commute_am')               as commute_am_rentals,
        countif(trip_segment = 'commute_pm')               as commute_pm_rentals,
        countif(trip_segment = 'leisure')                  as leisure_rentals,
        countif(trip_segment = 'nightlife')                as nightlife_rentals,
        countif(trip_segment = 'night')                    as night_rentals,
        countif(trip_segment = 'daytime')                  as daytime_rentals,
        countif(is_round_trip)                             as round_trips,
        countif(is_anomalous_duration)                     as anomalous_trips,

        round(avg(duration_min), 1)                        as avg_duration_min,
        round(approx_quantiles(duration_min, 100)[offset(50)], 1) as median_duration_min,

        count(distinct start_station_id)                   as active_start_stations,
        count(distinct end_station_id)                     as active_end_stations,
        count(distinct bike_id)                            as unique_bikes,

        max(is_disrupted_period)                           as is_disrupted_month,
        max(disruption_type)                               as disruption_type

    from fact
    group by month_start, year, month, season
),

-- Month-over-month delta
with_mom as (
    select
        *,
        lag(total_rentals) over (order by month_start)     as prev_month_rentals,
        lag(avg_duration_min) over (order by month_start)  as prev_month_avg_min
    from monthly
)

select
    *,
    round(safe_divide(
        total_rentals - prev_month_rentals,
        prev_month_rentals
    ) * 100, 1)                                            as mom_rental_change_pct,

    round(safe_divide(
        avg_duration_min - prev_month_avg_min,
        prev_month_avg_min
    ) * 100, 1)                                            as mom_duration_change_pct,

    -- Alert flag: duration change > 15% month-over-month (anomaly signal)
    abs(safe_divide(
        avg_duration_min - prev_month_avg_min,
        prev_month_avg_min
    )) > 0.15                                              as duration_anomaly_flag

from with_mom

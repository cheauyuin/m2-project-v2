{{
  config(materialized='table')
}}

/*
  Hourly station-level demand mart.
  Computes departures, arrivals, and net flow per station per hour-of-day + day-type.
  Flags structurally imbalanced stations (persistent ±10%+ net flow).
*/

with fact as (
    select
        start_station_id,
        start_station_name,
        end_station_id,
        end_station_name,
        extract(hour from start_date)                       as hour_of_day,
        is_weekend,
        trip_segment
    from {{ ref('fact_rentals') }}
    where not is_anomalous_duration
      and not is_round_trip
),

departures as (
    select
        start_station_id                                    as station_id,
        start_station_name                                  as station_name,
        hour_of_day,
        is_weekend,
        count(*)                                            as departures
    from fact
    where start_station_id is not null
    group by station_id, station_name, hour_of_day, is_weekend
),

arrivals as (
    select
        end_station_id                                      as station_id,
        end_station_name                                    as station_name,
        hour_of_day,
        is_weekend,
        count(*)                                            as arrivals
    from fact
    where end_station_id is not null
    group by station_id, station_name, hour_of_day, is_weekend
),

combined as (
    select
        coalesce(d.station_id, a.station_id)               as station_id,
        coalesce(d.station_name, a.station_name)            as station_name,
        coalesce(d.hour_of_day, a.hour_of_day)             as hour_of_day,
        coalesce(d.is_weekend, a.is_weekend)               as is_weekend,
        coalesce(d.departures, 0)                          as departures,
        coalesce(a.arrivals, 0)                            as arrivals
    from departures d
    full outer join arrivals a
        on  d.station_id  = a.station_id
        and d.hour_of_day = a.hour_of_day
        and d.is_weekend  = a.is_weekend
)

select
    c.station_id,
    c.station_name,
    c.hour_of_day,
    c.is_weekend,
    case when c.is_weekend then 'Weekend' else 'Weekday' end as day_type,
    c.departures,
    c.arrivals,
    c.departures - c.arrivals                               as net_flow,

    -- Positive = net source (bikes leaving); negative = net sink (bikes accumulating)
    safe_divide(c.departures - c.arrivals,
                c.departures + c.arrivals) * 100            as hourly_imbalance_pct,

    s.is_structural_imbalance,
    s.flow_role,
    s.latitude,
    s.longitude,
    s.docks_count

from combined c
left join {{ ref('dim_station') }} s on c.station_id = s.station_id
where not coalesce(s.has_capacity_error, false)

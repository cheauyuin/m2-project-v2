{{
  config(materialized='table')
}}

/*
  dim_station enriches stg_stations with:
  - is_structural_imbalance: station where net_flow > ±10% sustained over the full dataset
    (Waterloo bleeds +16%, Hop Exchange absorbs −15% — 8-year structural patterns)
  - total_departures / total_arrivals from the full hire history
*/

with stations as (
    select * from {{ ref('stg_stations') }}
),

-- Compute lifetime flow per station from the full hire dataset
hire_flows as (
    select
        start_station_id     as station_id,
        count(*)             as departures,
        0                    as arrivals
    from {{ source('london_bicycles', 'cycle_hire') }}
    where start_station_id is not null
      and end_station_id is not null
      and start_station_id != end_station_id
    group by station_id

    union all

    select
        end_station_id       as station_id,
        0                    as departures,
        count(*)             as arrivals
    from {{ source('london_bicycles', 'cycle_hire') }}
    where start_station_id is not null
      and end_station_id is not null
      and start_station_id != end_station_id
    group by station_id
),

flow_summary as (
    select
        station_id,
        sum(departures)      as total_departures,
        sum(arrivals)        as total_arrivals,
        sum(departures) - sum(arrivals)                             as net_outflow,
        safe_divide(
            sum(departures) - sum(arrivals),
            sum(departures) + sum(arrivals)
        ) * 100                                                     as imbalance_pct
    from hire_flows
    group by station_id
)

select
    s.id                                                as station_id,
    s.name                                              as station_name,
    s.latitude,
    s.longitude,
    s.docks_count,
    s.bikes_count,
    s.empty_docks,
    s.installed,
    s.temporary,
    s.terminal_name,
    s.install_date,
    s.removal_date,

    -- Cleaning flags from staging
    s.has_capacity_error,
    s.install_date_unknown,
    s.is_removed,
    s.is_not_installed,

    -- Flow metrics
    coalesce(f.total_departures, 0)                    as total_departures,
    coalesce(f.total_arrivals, 0)                      as total_arrivals,
    coalesce(f.net_outflow, 0)                         as net_outflow,
    coalesce(f.imbalance_pct, 0)                       as imbalance_pct,

    -- Structural imbalance: sustained ±10%+ over full dataset lifetime
    abs(coalesce(f.imbalance_pct, 0)) > 10             as is_structural_imbalance,

    case
        when coalesce(f.net_outflow, 0) > 0 then 'source'
        when coalesce(f.net_outflow, 0) < 0 then 'sink'
        else 'balanced'
    end                                                as flow_role

from stations s
left join flow_summary f on s.id = f.station_id

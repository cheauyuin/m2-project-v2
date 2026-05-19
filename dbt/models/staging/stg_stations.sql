{{
  config(materialized='view')
}}

/*
  Staging model for cycle_stations.

  Cleaning decisions:
  - has_capacity_error : 2 stations have docks_count = 0 despite being installed
  - install_date_unknown : 88 stations (11%) pre-date the tracking field
  - is_removed : only 3 stations have a removal_date recorded
*/

with source as (
    select * from {{ source('london_bicycles', 'cycle_stations') }}
)

select
    id,
    name,
    installed,
    latitude,
    longitude,
    locked,
    bikes_count,
    docks_count,
    nbEmptyDocks                           as empty_docks,
    temporary,
    terminal_name,
    install_date,
    removal_date,

    -- Cleaning flags
    docks_count = 0                        as has_capacity_error,
    install_date is null                   as install_date_unknown,
    removal_date is not null               as is_removed,
    not installed                          as is_not_installed

from source

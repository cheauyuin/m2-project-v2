-- Singular test: stations with has_capacity_error should never appear
-- in station demand mart with a docks_count value > 0 (data integrity check).

select station_id
from {{ ref('mart_station_demand') }}
where docks_count = 0
  and departures + arrivals > 0

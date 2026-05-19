-- Singular test: fact_rentals must not contain any cleaning-excluded row types.
-- Returns rows if any violation exists (test fails when row count > 0).

select rental_id, 'invalid_duration' as violation
from {{ ref('fact_rentals') }}
where duration_sec <= 0

union all

select rental_id, 'incomplete_trip'
from {{ ref('fact_rentals') }}
where start_date is not null and end_date is null

union all

select rental_id, 'ghost_end'
from {{ ref('fact_rentals') }}
where end_date is not null
  and end_station_id is null
  and end_station_name is null

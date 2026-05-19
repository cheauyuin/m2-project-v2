-- Singular test: maintenance trip count should be < 2,000.
-- A spike would indicate workshop records are leaking into customer data.
-- Returns a row (fails) if count exceeds threshold.

select count(*) as maintenance_count
from {{ ref('mart_maintenance_trips') }}
having count(*) > 2000

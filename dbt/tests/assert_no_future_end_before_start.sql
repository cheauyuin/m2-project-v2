-- Singular test: end_date must never precede start_date.

select rental_id
from {{ ref('fact_rentals') }}
where end_date is not null
  and end_date < start_date

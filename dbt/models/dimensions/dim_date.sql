{{
  config(materialized='table')
}}

with date_spine as (
    select date
    from unnest(
        generate_date_array(
            date '{{ var("start_date") }}',
            date '{{ var("end_date") }}'
        )
    ) as date
),

bank_holidays as (
    select holiday_date
    from {{ source('reference', 'uk_bank_holidays') }}
),

external_events as (
    select
        event_date,
        event_name,
        event_type,
        expected_impact
    from {{ source('reference', 'external_events') }}
)

select
    -- Surrogate key
    cast(format_date('%Y%m%d', d.date) as int64)   as date_id,
    d.date,

    -- Calendar fields
    extract(year  from d.date)                      as year,
    extract(month from d.date)                      as month,
    format_date('%B', d.date)                       as month_name,
    format_date('%b', d.date)                       as month_abbr,
    extract(day   from d.date)                      as day_of_month,

    -- Day of week (BigQuery: 1=Sunday, 7=Saturday)
    extract(dayofweek from d.date)                  as day_of_week_num,
    format_date('%A', d.date)                       as day_of_week_name,
    format_date('%a', d.date)                       as day_of_week_abbr,

    -- Weekend flag
    extract(dayofweek from d.date) in (1, 7)        as is_weekend,

    -- Season (Northern Hemisphere)
    case
        when extract(month from d.date) in (12, 1, 2) then 'Winter'
        when extract(month from d.date) in (3, 4, 5)  then 'Spring'
        when extract(month from d.date) in (6, 7, 8)  then 'Summer'
        else 'Autumn'
    end                                             as season,

    -- Quarter
    extract(quarter from d.date)                    as quarter,
    concat('Q', extract(quarter from d.date), ' ',
           extract(year from d.date))               as quarter_label,

    -- Bank holiday
    bh.holiday_date is not null                     as is_uk_bank_holiday,

    -- External disruption (any event on this date)
    ee.event_date is not null                       as is_disrupted_period,
    ee.event_name                                   as disruption_name,
    ee.event_type                                   as disruption_type,
    ee.expected_impact                              as disruption_impact,

    -- Nightlife flag: Fri night or Sat night (drives Saturday/Sunday early-AM spike)
    extract(dayofweek from d.date) in (6, 7)        as is_nightlife_day

from date_spine d
left join bank_holidays bh   on d.date = bh.holiday_date
left join external_events ee on d.date = ee.event_date

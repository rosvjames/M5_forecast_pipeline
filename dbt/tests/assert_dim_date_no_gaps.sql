-- dim_date no tiene huecos: tantas fechas como días entre la primera y la última,
-- y week_seq avanza de a 1 (cada semana Walmart tiene su número consecutivo).
-- El test pasa si no devuelve filas.

select count(*) as n_dates, datediff(day, min(date), max(date)) + 1 as expected_dates,
       max(week_seq) as max_week_seq, count(distinct wm_yr_wk) as n_weeks
from {{ ref('dim_date') }}
having count(*) != datediff(day, min(date), max(date)) + 1
    or max(week_seq) != count(distinct wm_yr_wk)

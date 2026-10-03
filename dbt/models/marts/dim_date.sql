-- Dimensión fecha: una fila por día (1.969), incluye los 28 días del horizonte de pronóstico.
-- Esas filas no tienen ventas en fact_sales, pero dan las features conocidas a futuro (día de semana,
-- eventos, semana Walmart para el precio) sin fuga de información.
-- SNAP no va aquí: depende de fecha × estado y vive en dim_date_state.

with calendar as (
    select * from {{ ref('stg_calendar') }}
)

select
    -- Llave YYYYMMDD: entera, estable y legible (20160619). La usan fact_sales y dim_date_state.
    to_number(to_char(date, 'YYYYMMDD'))::int as date_key,
    date,
    d,
    d_num,

    -- Semana Walmart (sábado a viernes). wm_yr_wk = 1 + YY + WW (11101 = año fiscal 2011, semana 01).
    wm_yr_wk,
    floor(wm_yr_wk / 100)::int + 1900 as wm_fiscal_year,
    mod(wm_yr_wk, 100)::int as wm_week_of_year,
    -- Índice secuencial de semana (1, 2, 3…): para lags y ventanas semanales. wm_yr_wk no se puede restar
    -- porque salta de 52 a 01 y el año fiscal 2013 tiene 53 semanas.
    dense_rank() over (order by wm_yr_wk)::int as week_seq,

    weekday,
    wday,                                         -- 1 = sábado … 7 = viernes
    wday in (1, 2) as is_weekend,
    day(date) as day_of_month,
    month,
    quarter(date) as quarter,
    year,

    event_name_1,
    event_type_1,
    event_name_2,
    event_type_2,
    is_event_day,
    (event_name_1 is not null)::int + (event_name_2 is not null)::int as n_events,

    is_christmas_closed,
    is_forecast_horizon,

    -- Mismo día del año anterior: t − 364 conserva el día de semana (t − 365 no), que es la estacionalidad
    -- más fuerte (EDA 04, §6.5). Es el baseline "año anterior". La llave queda NULL el primer año (fuera del calendario).
    dateadd(day, -364, date) as date_ly_364,
    iff(d_num > 364, to_number(to_char(dateadd(day, -364, date), 'YYYYMMDD'))::int, null) as date_key_ly_364
from calendar

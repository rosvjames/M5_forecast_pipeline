-- Calendario limpio: una fila por día (d_1..d_1969, incluye las 28 del horizonte de pronóstico sin ventas).
-- Solo tipos, nombres y flags que dependen únicamente de la fecha. Los derivados de modelado
-- (date_key, índice secuencial de semana, date_ly_364) van en dim_date (Gold).
-- View: son 1.969 filas, recalcularla cuesta nada y siempre refleja Bronze.

with source as (
    select *
    from {{ source('bronze', 'calendar') }}
)

select
    d,
    try_to_number(substr(d, 3))::int as d_num,  -- d_1 → 1: permite ordenar y filtrar rangos de días
    date,
    wm_yr_wk,
    weekday,
    wday,                                        -- convención M5: 1 = sábado … 7 = viernes (la semana Walmart empieza en sábado)
    month,
    year,

    -- Eventos: el nulo es estructural (día sin evento, 91,8 %), no un dato perdido. Se conserva tal cual
    -- y se agrega un booleano para no tener que repetir "event_name_1 is not null" en cada modelo.
    event_name_1,
    event_type_1,
    event_name_2,
    event_type_2,
    event_name_1 is not null as is_event_day,

    -- SNAP viene como 0/1 por estado. Booleano para que el join con la tienda (por state_id) sea directo.
    snap_ca = 1 as is_snap_ca,
    snap_tx = 1 as is_snap_tx,
    snap_wi = 1 as is_snap_wi,

    -- Calidad #2 (docs/calidad_datos.md): Walmart cierra en Navidad. Regla por fecha, no por ventas:
    -- coincide con los 5 días detectados en dq_02 (25-dic de 2011 a 2015).
    month = 12 and day(date) = 25 as is_christmas_closed,

    -- Últimos 28 días del calendario (d_1942..d_1969): horizonte de pronóstico de M5, sin ventas.
    try_to_number(substr(d, 3)) > 1941 as is_forecast_horizon,

    _source_file,
    _batch_id,
    _loaded_at
from source

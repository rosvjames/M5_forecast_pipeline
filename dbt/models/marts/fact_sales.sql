-- Hecho de ventas. Grain: item × tienda × día (59 M filas, mismas que int_sales_daily).
-- Solo llaves, medidas y flags que dependen de la fila (serie × día). Lo que depende solo de la fecha
-- (eventos, Navidad, horizonte) está en dim_date; lo que depende de fecha × estado (SNAP), en dim_date_state.
-- Table (rebuild completo): int_sales_daily ya se recalcula entero en cada corrida.

with sales as (
    select * from {{ ref('int_sales_daily') }}
)

select
    -- Llaves hacia las dimensiones
    to_number(to_char(date, 'YYYYMMDD'))::int as date_key,     -- → dim_date
    item_id,                                                    -- → dim_item
    store_id,                                                   -- → dim_store
    state_id,                                                   -- con date_key → dim_date_state (SNAP)

    -- Medidas
    sales as units,
    sell_price,                                                 -- NULL antes del lanzamiento
    revenue,                                                    -- units × sell_price (aproximado: precio promedio semanal)

    -- Flags de calidad por serie × día (docs/calidad_datos.md). Se marca, no se borra.
    is_pre_launch,
    is_store_closed,
    is_sales_spike,                                             -- solo diagnóstico, nunca feature

    -- Linaje: entrega semanal de Kestra que trajo la fila
    week_idx,
    _loaded_at
from sales
-- Escribir ordenado por fecha agrupa las fechas en las micro-particiones de Snowflake: las consultas
-- por rango de fechas (backtesting, lectura desde Spark) saltan las particiones que no necesitan.
order by date_key, store_id, item_id

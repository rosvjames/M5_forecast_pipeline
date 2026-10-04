-- Hecho de ventas. Grain: item × tienda × día (59 M filas, mismas que int_sales_daily).
-- Solo llaves, medidas y flags que dependen de la fila (serie × día). Lo que depende solo de la fecha
-- (eventos, Navidad, horizonte) está en dim_date; lo que depende de fecha × estado (SNAP), en dim_date_state.
-- Table (rebuild completo): int_sales_daily ya se recalcula entero en cada corrida.

with sales as (
    select * from {{ ref('int_sales_daily') }}
),

-- Solo trae los días dentro de una racha marcada: con left join, el resto queda en false.
stockouts as (
    select * from {{ ref('int_stockout_flags') }}
)

select
    -- Llaves hacia las dimensiones
    to_number(to_char(s.date, 'YYYYMMDD'))::int as date_key,     -- → dim_date
    s.item_id,                                                  -- → dim_item
    s.store_id,                                                 -- → dim_store
    state_id,                                                   -- con date_key → dim_date_state (SNAP)

    -- Medidas
    sales as units,
    sell_price,                                                 -- NULL antes del lanzamiento
    revenue,                                                    -- units × sell_price (aproximado: precio promedio semanal)

    -- Flags de calidad por serie × día (docs/calidad_datos.md). Se marca, no se borra.
    is_pre_launch,
    is_store_closed,
    is_sales_spike,                                             -- solo diagnóstico, nunca feature
    -- Calidad #4: día dentro de una racha de ceros anómala (posible quiebre de stock), con dos reglas para
    -- el análisis de sensibilidad. Marcan la racha completa: sirven para filtrar, no como feature del día.
    coalesce(so.is_suspected_stockout_conservative, false) as is_suspected_stockout_conservative,
    coalesce(so.is_suspected_stockout_nb, false) as is_suspected_stockout_nb,

    -- Linaje: entrega semanal de Kestra que trajo la fila
    week_idx,
    _loaded_at
from sales s
left join stockouts so
    on so.item_id = s.item_id and so.store_id = s.store_id and so.date = s.date
-- Escribir ordenado por fecha agrupa las fechas en las micro-particiones de Snowflake: las consultas
-- por rango de fechas (backtesting, lectura desde Spark) saltan las particiones que no necesitan.
order by date_key, s.store_id, s.item_id

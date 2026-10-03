-- SNAP por fecha × estado (1.969 × 3 = 5.907 filas). Los cupones SNAP dependen del estado, no de la tienda,
-- así que no caben en dim_date (habría que elegir columna con un CASE) ni en dim_store (cambian cada día).
-- Con esta tabla, agregar un estado es agregar filas, no columnas.
-- fact_sales se une por (date_key, state_id).

with calendar as (
    select * from {{ ref('stg_calendar') }}
),

unpivoted as (
    select date, 'CA' as state_id, is_snap_ca as is_snap from calendar
    union all
    select date, 'TX', is_snap_tx from calendar
    union all
    select date, 'WI', is_snap_wi from calendar
)

select
    to_number(to_char(date, 'YYYYMMDD'))::int as date_key,
    state_id,
    is_snap
from unpivoted

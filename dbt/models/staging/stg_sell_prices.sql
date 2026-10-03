-- Precios limpios: una fila por tienda × item × semana Walmart (6.841.121 filas, solo semanas con precio).
-- Bronze ya trae los tipos correctos (sell_price NUMBER(10,2)); aquí se agrega la semana de lanzamiento.
-- Table, no view: se une con los 59 M de stg_sales y como view se releería Bronze en cada modelo que la use.
-- Sin flags de precio: los precios extremos y los centavos atípicos se conservan (calidad #6 y #7).

{{ config(materialized='table') }}

with source as (
    select *
    from {{ source('bronze', 'sell_prices') }}
)

select
    store_id,
    item_id,
    wm_yr_wk,
    sell_price,

    -- Primera semana con precio de la serie = lanzamiento del producto en esa tienda (calidad #1:
    -- 0 ventas antes de esta semana). De aquí sale is_pre_launch en el modelo de ventas.
    -- min() es válido porque wm_yr_wk (YYYWW) conserva el orden cronológico; restar códigos no lo es,
    -- porque el año fiscal 2013 tiene 53 semanas.
    min(wm_yr_wk) over (partition by store_id, item_id) as launch_wm_yr_wk,

    _source_file,
    _batch_id,
    _loaded_at
from source

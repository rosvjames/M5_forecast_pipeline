-- Dimensión tienda: una fila por tienda (10), con su estado. state_id es también la llave hacia
-- dim_date_state (SNAP).

with sales as (
    select * from {{ ref('stg_sales') }}
)

select distinct
    store_id,
    state_id
from sales

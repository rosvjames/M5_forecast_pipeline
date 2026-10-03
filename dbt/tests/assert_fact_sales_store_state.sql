-- state_id del fact coincide con el estado de la tienda en dim_store (si no, el SNAP saldría del estado equivocado).
-- El test pasa si no devuelve filas.

select distinct f.store_id, f.state_id, s.state_id as dim_state_id
from {{ ref('fact_sales') }} f
join {{ ref('dim_store') }} s on s.store_id = f.store_id
where f.state_id != s.state_id

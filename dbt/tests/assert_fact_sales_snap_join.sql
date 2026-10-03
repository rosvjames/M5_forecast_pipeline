-- Llave compuesta fact_sales (date_key, state_id) → dim_date_state.
-- dbt no tiene test de relationships para llaves compuestas, por eso va como test singular.
-- Devuelve las combinaciones sin SNAP; el test pasa si no devuelve filas.

select distinct f.date_key, f.state_id
from {{ ref('fact_sales') }} f
left join {{ ref('dim_date_state') }} ds
    on ds.date_key = f.date_key and ds.state_id = f.state_id
where ds.date_key is null

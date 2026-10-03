-- Cada fecha × estado tiene su fila de SNAP: si falta una, el join del fact perdería el SNAP de ese día.
-- Devuelve las combinaciones faltantes; el test pasa si no devuelve filas.

with expected as (
    select d.date_key, s.state_id
    from {{ ref('dim_date') }} d
    cross join (select distinct state_id from {{ ref('dim_store') }}) s
)

select e.*
from expected e
left join {{ ref('dim_date_state') }} ds
    on ds.date_key = e.date_key and ds.state_id = e.state_id
where ds.date_key is null

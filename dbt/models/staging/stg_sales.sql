-- Ventas en formato largo: una fila por item × tienda × día.
-- Es el paso ancho → largo que antes hacía la ingesta; ahora vive en Silver, versionado y testeado.
-- Sin limpieza: los flags de calidad (lanzamiento, Navidad, cierres, picos) van en un modelo posterior.

-- Incremental por entrega semanal. delete+insert con unique_key = week_idx: si Kestra recarga una semana,
-- dbt borra esa semana completa de la tabla y la vuelve a insertar (misma idempotencia que en Bronze).
{{ config(
    materialized='incremental',
    incremental_strategy='delete+insert',
    unique_key='week_idx'
) }}

with deliveries as (
    select *
    from {{ source('bronze', 'sales_raw') }}
    {% if is_incremental() %}
    -- Solo entregas cargadas (o recargadas) después de la última corrida de este modelo.
    where _loaded_at > (select max(_loaded_at) from {{ this }})
    {% endif %}
),

cells as (
    -- OBJECT_CONSTRUCT(*) arma un objeto {columna: valor} con TODAS las columnas de la fila y omite las NULL:
    -- de las ~1.941 columnas D_N quedan solo los 7 días que trajo esa entrega.
    -- Unpivot por NOMBRE: no hay lista de columnas escrita a mano ni generada, así que sirve igual
    -- cuando schema evolution agrega columnas nuevas. (Probado: mismo resultado que UNPIVOT y ~3× más rápido.)
    select
        id, item_id, dept_id, cat_id, store_id, state_id,
        week_idx, _source_file, _batch_id, _loaded_at,
        object_construct(*) as row_object
    from deliveries
)

select
    c.id,
    c.item_id,
    c.dept_id,
    c.cat_id,
    c.store_id,
    c.state_id,
    lower(f.key) as d,                -- Snowflake crea las columnas en mayúsculas (D_1); calendar usa 'd_1'
    f.value::number as sales,         -- cada archivo infiere su propio NUMBER(p,0); aquí se unifica el tipo
    c.week_idx,
    c._source_file,
    c._batch_id,
    c._loaded_at
from cells c,
    lateral flatten(input => c.row_object) f
where regexp_like(f.key, 'D_[0-9]+')  -- deja fuera las claves de jerarquía y metadatos

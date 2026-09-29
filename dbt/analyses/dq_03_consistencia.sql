-- Calidad · Consistencia: ¿los datos se contradicen entre columnas o entre tablas?
-- Una fila por chequeo: afectados = registros que violan la regla (esperado 0), evaluados = universo revisado.
-- Referencia EDA: eda/reports/03_consistency_quality.md §3 (0 contradicciones, malla completa 3.049 × 10).

with series as (
    -- La jerarquía se repite en cada día; basta revisarla una vez por serie.
    select distinct id, item_id, dept_id, cat_id, store_id, state_id
    from {{ ref('stg_sales') }}
),

price_pairs as (
    select distinct item_id, store_id
    from {{ source('bronze', 'sell_prices') }}
),

checks as (
    -- 1. El id es exactamente item_id + store_id + sufijo.
    select
        'id = item_id_store_id_evaluation' as check_name,
        count_if(id != item_id || '_' || store_id || '_evaluation') as afectados,
        count(*) as evaluados
    from series

    union all

    -- 2. Los prefijos respetan la jerarquía: item empieza con su dept, dept con su cat, store con su state.
    select
        'prefijos item > dept > cat, store > state',
        count_if(
            not startswith(item_id, dept_id || '_')
            or not startswith(dept_id, cat_id || '_')
            or not startswith(store_id, state_id || '_')
        ),
        count(*)
    from series

    union all

    -- 3. Relaciones funcionales: cada hijo tiene un solo padre.
    select 'item con más de un dept', count(*), (select count(distinct item_id) from series)
    from (select item_id from series group by item_id having count(distinct dept_id) > 1)

    union all

    select 'dept con más de una cat', count(*), (select count(distinct dept_id) from series)
    from (select dept_id from series group by dept_id having count(distinct cat_id) > 1)

    union all

    select 'store con más de un state', count(*), (select count(distinct store_id) from series)
    from (select store_id from series group by store_id having count(distinct state_id) > 1)

    union all

    -- 4. Malla completa: cada tienda vende el mismo catálogo (3.049 items).
    select
        'tiendas con catálogo incompleto',
        count_if(n_items != (select count(distinct item_id) from series)),
        count(*)
    from (select store_id, count(*) as n_items from series group by store_id)

    union all

    -- 5. Consistencia entre tablas: los pares item × tienda de ventas y de precios coinciden.
    select 'series de ventas sin ningún precio', count(*), (select count(*) from series)
    from series s
    left join price_pairs p using (item_id, store_id)
    where p.item_id is null

    union all

    select 'pares de precios sin serie de ventas', count(*), (select count(*) from price_pairs)
    from price_pairs p
    left join series s using (item_id, store_id)
    where s.item_id is null
)

select
    check_name,
    afectados,
    evaluados,
    round(100 * afectados / nullif(evaluados, 0), 2) as pct
from checks

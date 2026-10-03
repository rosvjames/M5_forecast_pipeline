-- Ventas diarias listas para modelar: una fila por item × tienda × día (mismo grain y conteo que stg_sales),
-- con fecha, precio vigente, ingreso y los flags de calidad de docs/calidad_datos.md.
-- Marca, no borra: la malla SKU × día queda completa y cada exclusión es explícita y reversible.
-- Los flags de quiebre de stock (calidad #4) van en un modelo aparte: necesitan rachas y ventanas causales.
-- Table (rebuild completo, ~30 s): el flag de picos usa la mediana de toda la serie, que cambia con cada
-- semana nueva, así que un incremental tendría que recalcular igual todas las series.

{{ config(materialized='table') }}

with sales as (
    select * from {{ ref('stg_sales') }}
),

calendar as (
    select * from {{ ref('stg_calendar') }}
),

prices as (
    select * from {{ ref('stg_sell_prices') }}
),

-- Una fila por serie: hace falta aparte porque antes del lanzamiento no hay fila de precio que la traiga.
launch as (
    select distinct store_id, item_id, launch_wm_yr_wk
    from prices
),

closures as (
    select * from {{ ref('store_closures') }}
),

joined as (
    select
        s.item_id,
        s.dept_id,
        s.cat_id,
        s.store_id,
        s.state_id,
        s.d,
        c.d_num,
        c.date,
        c.wm_yr_wk,
        s.sales,
        p.sell_price,                                   -- NULL antes del lanzamiento: no había precio
        s.sales * p.sell_price as revenue,              -- aproximado: sell_price es un promedio semanal (calidad #6)

        -- SNAP es por estado: se toma el del estado de la tienda.
        case s.state_id
            when 'CA' then c.is_snap_ca
            when 'TX' then c.is_snap_tx
            when 'WI' then c.is_snap_wi
        end as is_snap,
        c.is_event_day,
        c.event_name_1,
        c.event_type_1,

        -- Calidad #1: antes de la primera semana con precio el producto no estaba en la tienda; el 0 no es demanda.
        -- Comparar wm_yr_wk con < es válido (conserva el orden); restarlos no.
        coalesce(c.wm_yr_wk < l.launch_wm_yr_wk, true) as is_pre_launch,
        -- Calidad #2: tiendas cerradas el 25-dic.
        c.is_christmas_closed,
        -- Calidad #3: cierres puntuales revisados (seed store_closures).
        cl.store_id is not null as is_store_closed,

        -- Calidad #5: mediana de los días con venta de la serie, para el flag de picos.
        median(iff(s.sales > 0, s.sales, null)) over (partition by s.item_id, s.store_id) as series_median_nonzero,

        s.week_idx,
        s._loaded_at
    from sales s
    join calendar c
        on c.d = s.d
    left join prices p
        on p.store_id = s.store_id and p.item_id = s.item_id and p.wm_yr_wk = c.wm_yr_wk
    left join launch l
        on l.store_id = s.store_id and l.item_id = s.item_id
    left join closures cl
        on cl.store_id = s.store_id and cl.date = c.date
)

select
    item_id,
    dept_id,
    cat_id,
    store_id,
    state_id,
    d,
    d_num,
    date,
    wm_yr_wk,
    sales,
    sell_price,
    revenue,
    is_snap,
    is_event_day,
    event_name_1,
    event_type_1,
    is_pre_launch,
    is_christmas_closed,
    is_store_closed,
    -- Calidad #5: pico = > 10× la mediana de los días con venta y >= 20 u (mismos umbrales que el EDA y dq_02).
    -- Descriptivo: usa la serie completa, así que NO debe usarse como feature ni para filtrar entrenamiento.
    coalesce(sales > 10 * series_median_nonzero and sales >= 20, false) as is_sales_spike,
    week_idx,
    _loaded_at
from joined

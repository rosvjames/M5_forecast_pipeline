-- Calidad #4: quiebres de stock sospechosos. M5 no trae inventario, así que se aproximan con rachas de ceros
-- demasiado largas para la demanda que traía la serie. Una fila por item × tienda × día DENTRO de una racha marcada
-- (los demás días no aparecen: fact_sales hace left join y los deja en false).
--
-- Dos reglas, para el análisis de sensibilidad (mismos umbrales que el EDA, eda/scripts/02_sell_prices.py §5):
--   conservadora      : tasa local >= 1 u/día y racha >= 14 días.
--   binomial negativa : racha >= 7 días y P(racha de L ceros) < 0,001, con P(0) = (1 + λ/k)^-k.
-- Todo lo que entra a la regla es CAUSAL, es decir, usa solo días anteriores a la racha:
--   λ (tasa local) = media de los 56 días previos; exige >= 28 días de historia.
--   k (dispersión) = por momentos sobre toda la historia previa de la serie (ventana expansiva).
--                    El EDA lo calculaba con la serie completa, que incluye el futuro.
-- Lo que NO es causal es el largo de la racha: un día se marca sabiendo cuánto duró la racha entera.
-- Sirve para excluir días de rachas ya cerradas al entrenar o evaluar; no sirve como feature del día.
--
-- La secuencia de días omite el pre-lanzamiento, Navidad y los cierres de tienda: esos ceros ya tienen
-- explicación (calidad #1, #2 y #3) y no cuentan ni cortan una racha.

{{ config(materialized='table') }}

with days as (
    select
        item_id,
        store_id,
        date,
        sales,
        row_number() over (partition by item_id, store_id order by d_num) as seq
    from {{ ref('int_sales_daily') }}
    where not is_pre_launch
      and not is_christmas_closed
      and not is_store_closed
),

-- Serie activa: desde su primera venta. Antes no hay demanda con qué comparar.
active as (
    select *
    from days
    qualify seq >= min(iff(sales > 0, seq, null)) over (partition by item_id, store_id)
),

-- Estadísticas de la historia PREVIA a cada día (los marcos terminan en "1 preceding": nunca ven el día ni el futuro).
history as (
    select
        *,
        sum(sales) over (partition by item_id, store_id order by seq rows between 56 preceding and 1 preceding) as units_56,
        count(*)   over (partition by item_id, store_id order by seq rows between 56 preceding and 1 preceding) as days_56,
        sum(sales) over (partition by item_id, store_id order by seq rows between unbounded preceding and 1 preceding) as units_hist,
        sum(sales * sales) over (partition by item_id, store_id order by seq rows between unbounded preceding and 1 preceding) as units_sq_hist,
        count(*)   over (partition by item_id, store_id order by seq rows between unbounded preceding and 1 preceding) as days_hist
    from active
),

-- Rachas de ceros (gaps and islands): dentro de una racha, seq menos su número de orden entre los ceros es constante.
zero_days as (
    select
        *,
        seq - row_number() over (partition by item_id, store_id order by seq) as run_id
    from history
    where sales = 0
),

-- Una fila por racha, con la historia vista desde su primer día.
runs as (
    select
        item_id,
        store_id,
        run_id,
        min(date) as run_start_date,
        max(date) as run_end_date,
        count(*) as run_length,
        min_by(units_56, seq) as units_56,
        min_by(days_56, seq) as days_56,
        min_by(units_hist, seq) as units_hist,
        min_by(units_sq_hist, seq) as units_sq_hist,
        min_by(days_hist, seq) as days_hist
    from zero_days
    group by item_id, store_id, run_id
),

rates as (
    select
        *,
        iff(days_56 >= 28, units_56 / days_56, null) as local_rate,
        units_hist / days_hist as hist_mean,
        units_sq_hist / days_hist - square(units_hist / days_hist) as hist_var
    from runs
),

scored as (
    select
        *,
        -- Método de momentos: var = media + media²/k. Sin sobredispersión (var <= media) queda NULL → Poisson.
        iff(hist_var > 1.0001 * hist_mean, square(hist_mean) / (hist_var - hist_mean), null) as nb_k
    from rates
),

flagged as (
    select
        *,
        coalesce(local_rate >= 1 and run_length >= 14, false) as is_suspected_stockout_conservative,
        -- ln P(racha) = L × ln P(0); con k NULL se usa Poisson: ln P(0) = -λ.
        coalesce(
            run_length >= 7
            and run_length * iff(nb_k is null, -local_rate, -nb_k * ln(1 + local_rate / nb_k)) < ln(0.001),
            false
        ) as is_suspected_stockout_nb
    from scored
)

select
    z.item_id,
    z.store_id,
    z.date,
    f.is_suspected_stockout_conservative,
    f.is_suspected_stockout_nb,
    -- Contexto de la racha, para auditar la regla
    f.run_start_date,
    f.run_end_date,
    f.run_length,
    f.local_rate,
    f.nb_k
from zero_days z
join flagged f
    on f.item_id = z.item_id and f.store_id = z.store_id and f.run_id = z.run_id
where f.is_suspected_stockout_conservative or f.is_suspected_stockout_nb

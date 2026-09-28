-- Calidad · Completitud: ¿está todo lo que debería estar? (filas, semanas, días, precios, eventos)
-- Una fila por chequeo: afectados = registros que caen en el caso, evaluados = universo revisado.
-- Aquí no todo es "falla": los ceros previos al lanzamiento y los nulos de eventos son hallazgos a tratar en Silver.
-- Referencia EDA: eda/reports/01_sales_eval.md (20,9 % previo al lanzamiento) y 04_calendar.md (91,8 % sin evento).
-- Nota: SALES llega hasta d_1939 hasta que el cron cargue la semana 277; los % difieren levemente del EDA (d_1941).

with calendar as (
    select *, try_to_number(substr(d, 3)) as d_num
    from {{ source('bronze', 'calendar') }}
),

-- ---------- Carga semanal (Kestra) ----------
sales_by_week as (
    select week_idx, count(*) as n_rows, count(distinct d) as n_days
    from {{ source('bronze', 'sales') }}
    group by week_idx
),

last_success_log as (
    -- Última carga exitosa de cada semana (las re-ejecuciones dejan varias filas en el log).
    select week_idx, rows_loaded
    from {{ source('bronze', 'load_log') }}
    where table_name = 'SALES' and status = 'SUCCESS'
    qualify row_number() over (partition by week_idx order by loaded_at desc) = 1
),

-- ---------- Malla de series ----------
days_per_series as (
    select item_id, store_id, count(*) as n_days
    from {{ source('bronze', 'sales') }}
    group by item_id, store_id
),

-- ---------- Lanzamiento y precios ----------
weeks as (
    -- Semanas Walmart con su primer día y un índice secuencial (wm_yr_wk no se puede restar: 2013 tiene 53 semanas).
    select wm_yr_wk, min(date) as week_start, row_number() over (order by wm_yr_wk) as week_seq
    from calendar
    group by wm_yr_wk
),

price_span as (
    select
        p.item_id, p.store_id,
        min(w.week_start) as launch_date,
        min(w.week_seq) as first_seq,
        max(w.week_seq) as last_seq,
        count(*) as n_weeks
    from {{ source('bronze', 'sell_prices') }} p
    join weeks w using (wm_yr_wk)
    group by p.item_id, p.store_id
),

sales_vs_launch as (
    -- Una sola pasada sobre SALES con fecha, lanzamiento y precio de su semana.
    select
        count(*) as n,
        count_if(s.sales = 0) as ceros,
        count_if(c.date < l.launch_date) as pre_launch,
        count_if(c.date < l.launch_date and s.sales > 0) as venta_pre_launch,
        count_if(c.date >= l.launch_date and p.sell_price is null) as sin_precio_post_launch,
        count_if(s.sales > 0 and p.sell_price is null) as venta_sin_precio
    from {{ source('bronze', 'sales') }} s
    join calendar c on c.d = s.d
    join price_span l on l.item_id = s.item_id and l.store_id = s.store_id
    left join {{ source('bronze', 'sell_prices') }} p
        on p.item_id = s.item_id and p.store_id = s.store_id and p.wm_yr_wk = c.wm_yr_wk
),

checks as (
    -- 1. Semanas: ninguna falta entre la 0 y la última cargada.
    select
        'semanas faltantes entre 0 y la última cargada' as check_name,
        max(week_idx) + 1 - count(*) as afectados,
        max(week_idx) + 1 as evaluados
    from sales_by_week

    union all

    -- 2. Cada semana trae 30.490 series × sus días (7, salvo la última del M5).
    select
        'semanas con filas != 30.490 × días esperados',
        count_if(n_rows != 30490 * least(7, 1941 - 7 * week_idx) or n_days != least(7, 1941 - 7 * week_idx)),
        count(*)
    from sales_by_week

    union all

    -- 3. Lo que Kestra dijo que cargó (LOAD_LOG) coincide con lo que hay en la tabla.
    select
        'semanas donde LOAD_LOG != filas reales',
        count_if(l.rows_loaded is null or l.rows_loaded != w.n_rows),
        count(*)
    from sales_by_week w
    left join last_success_log l using (week_idx)

    union all

    -- 4. Malla completa: todas las series tienen todos los días cargados.
    select
        'series con días faltantes',
        count_if(n_days != (select count(distinct d) from {{ source('bronze', 'sales') }})),
        count(*)
    from days_per_series

    union all

    -- 5. Calendario continuo d_1..d_1969 (incluye el horizonte futuro d_1942..d_1969).
    select 'huecos en los d del calendario', max(d_num) - count(*), max(d_num)
    from calendar

    union all

    -- 6. Hallazgo principal: días-serie antes de que el producto existiera (primera semana con precio).
    select 'días-serie previos al lanzamiento', pre_launch, n from sales_vs_launch

    union all

    select 'ceros que son previos al lanzamiento', pre_launch, ceros from sales_vs_launch

    union all

    select 'ventas > 0 antes del lanzamiento', venta_pre_launch, pre_launch from sales_vs_launch

    union all

    -- 7. Después del lanzamiento el precio nunca falta (se arrastra aunque no haya ventas).
    select 'días-serie post lanzamiento sin precio', sin_precio_post_launch, n - pre_launch from sales_vs_launch

    union all

    select 'días con venta y sin precio', venta_sin_precio, n from sales_vs_launch

    union all

    select 'series con semanas sin precio tras lanzar', count_if(last_seq - first_seq + 1 != n_weeks), count(*)
    from price_span

    union all

    -- 8. Nulos estructurales: día sin evento (dq_04 confirma que nombre y tipo son nulos juntos).
    select 'días sin evento (event_name_1 nulo)', count_if(event_name_1 is null), count(*)
    from calendar
)

select
    check_name,
    afectados,
    evaluados,
    round(100 * afectados / nullif(evaluados, 0), 2) as pct
from checks

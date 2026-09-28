-- Calidad · Precisión: ¿el valor refleja la realidad que dice medir? (demanda real, precio real)
-- Una fila por chequeo: afectados = registros en el caso, evaluados = universo revisado, detalle = casos puntuales.
-- Umbrales iguales a los del EDA (eda/scripts/01_sales_eval.py §2 y §7, 02_sell_prices.py) para poder comparar:
--   día anómalo  = venta total < 10 % de la mediana móvil centrada de 29 días
--   pico         = venta > 10 × mediana de los días con venta de la serie y >= 20 unidades
--   precio raro  = > 5 × o < 0,2 × la mediana de precio de la serie

with store_daily as (
    select s.store_id, c.date, sum(s.sales) as units
    from {{ source('bronze', 'sales') }} s
    join {{ source('bronze', 'calendar') }} c on c.d = s.d
    group by s.store_id, c.date
),

total_daily as (
    select date, sum(units) as units
    from store_daily
    group by date
),

-- ---------- Días anómalos: Navidad y cierres de tienda ----------
total_vs_median as (
    -- Mediana móvil con self-join (±14 días): Snowflake no admite marco de ventana en MEDIAN.
    select a.date, a.units, median(b.units) as rolling_median
    from total_daily a
    join total_daily b on b.date between dateadd(day, -14, a.date) and dateadd(day, 14, a.date)
    group by a.date, a.units
),

store_vs_median as (
    select a.store_id, a.date, a.units, median(b.units) as rolling_median
    from store_daily a
    join store_daily b
        on b.store_id = a.store_id
        and b.date between dateadd(day, -14, a.date) and dateadd(day, 14, a.date)
    group by a.store_id, a.date, a.units
),

-- ---------- Picos de venta ----------
series_stats as (
    select
        item_id, store_id,
        max(sales) as max_sales,
        median(iff(sales > 0, sales, null)) as median_nonzero
    from {{ source('bronze', 'sales') }}
    group by item_id, store_id
),

spike_days as (
    select count(*) as n, count_if(s.sales > 10 * st.median_nonzero and s.sales >= 20) as spikes
    from {{ source('bronze', 'sales') }} s
    join series_stats st using (item_id, store_id)
),

-- ---------- Precios ----------
prices as (
    select
        p.*,
        median(sell_price) over (partition by item_id, store_id) as median_price
    from {{ source('bronze', 'sell_prices') }} p
),

checks as (
    -- 1. Días con la venta total casi nula: ¿son todos Navidad (tiendas cerradas)?
    select
        'días con venta total < 10 % de la mediana móvil' as check_name,
        count_if(units < 0.1 * rolling_median) as afectados,
        count(*) as evaluados,
        listagg(iff(units < 0.1 * rolling_median, date || ' (' || units || ' u)', null), ', ')
            within group (order by date) as detalle
    from total_vs_median

    union all

    select
        '  de ellos, fuera del 25 de diciembre',
        count_if(units < 0.1 * rolling_median and not (month(date) = 12 and day(date) = 25)),
        count_if(units < 0.1 * rolling_median),
        null
    from total_vs_median

    union all

    -- 2. Cierres puntuales de tienda (fuera de Navidad).
    select
        'días-tienda < 10 % de su mediana móvil (sin Navidad)',
        count(*),
        (select count(*) from store_daily),
        listagg(store_id || ' ' || date || ' (' || units || ' u)', ', ') within group (order by date)
    from store_vs_median
    where units < 0.1 * rolling_median and not (month(date) = 12 and day(date) = 25)

    union all

    select
        'días-tienda < 50 % de su mediana móvil (sin Navidad)',
        count(*),
        (select count(*) from store_daily),
        null
    from store_vs_median
    where units < 0.5 * rolling_median and not (month(date) = 12 and day(date) = 25)

    union all

    -- 3. Picos extremos: series que alguna vez vendieron > 10× su mediana y >= 20 u.
    select
        'series con pico > 10× mediana no nula y >= 20 u',
        count_if(max_sales > 10 * median_nonzero and max_sales >= 20),
        count(*),
        null
    from series_stats

    union all

    select 'días-serie que son pico', spikes, n, null
    from spike_days

    union all

    -- 4. Precios: extremos respecto de la propia serie y precios de un centavo.
    select
        'precios > 5× o < 0,2× la mediana de su serie',
        count_if(sell_price > 5 * median_price or sell_price < 0.2 * median_price),
        count(*),
        null
    from prices

    union all

    select 'precios de $0,01', count_if(sell_price = 0.01), count(*), null
    from prices

    union all

    -- 5. Centavos finales 2, 3, 4 o 6: no son precios de lista (terminan en 8, 7, 0...),
    --    señal de que sell_price es un promedio semanal que mezcla dos precios.
    select
        'precios con centavo final atípico (2, 3, 4, 6)',
        count_if(mod(round(sell_price * 100), 10) in (2, 3, 4, 6)),
        count(*),
        null
    from prices
)

select
    check_name,
    afectados,
    evaluados,
    round(100 * afectados / nullif(evaluados, 0), 2) as pct,
    detalle
from checks

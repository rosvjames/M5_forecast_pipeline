-- Calidad · Validez: ¿cada valor está dentro de su dominio (formato, rango, valores permitidos)?
-- Una fila por chequeo: afectados = registros que violan la regla (esperado 0), evaluados = universo revisado.
-- Referencia EDA: eda/reports/03_consistency_quality.md §3-4 y 04_calendar.md.

with sales_checks as (
    -- Una sola pasada sobre los 59 M de filas: todos los conteos de SALES salen de aquí.
    select
        count(*) as n,
        count_if(sales < 0) as sales_negativas,
        count_if(sales is null) as sales_nulas,
        count_if(not regexp_like(d, 'd_[0-9]+')) as d_mal_formado,
        count_if(try_to_number(substr(d, 3)) not between 1 and 1941) as d_fuera_de_rango,
        -- Regla del flow load_sales_week: la semana k carga d_(7k+1) .. d_(7k+7).
        count_if(week_idx != floor((try_to_number(substr(d, 3)) - 1) / 7)) as week_idx_incoherente
    from {{ source('bronze', 'sales') }}
),

series as (
    select distinct item_id, dept_id, cat_id, store_id, state_id
    from {{ source('bronze', 'sales') }}
),

calendar as (
    select *, try_to_number(substr(d, 3)) as d_num
    from {{ source('bronze', 'calendar') }}
),

checks as (
    -- SALES: rangos y formatos
    select 'sales negativas' as check_name, sales_negativas as afectados, n as evaluados from sales_checks
    union all
    select 'sales nulas', sales_nulas, n from sales_checks
    union all
    select 'd con formato distinto de d_N', d_mal_formado, n from sales_checks
    union all
    select 'd fuera de d_1..d_1941', d_fuera_de_rango, n from sales_checks
    union all
    select 'week_idx no corresponde a su d', week_idx_incoherente, n from sales_checks

    union all

    -- Jerarquía: códigos con el formato y los valores que declara la documentación de M5
    select
        'códigos de jerarquía con formato inválido',
        count_if(
            not regexp_like(item_id, '(HOBBIES|FOODS|HOUSEHOLD)_[0-9]+_[0-9]{3}')
            or not regexp_like(store_id, '(CA|TX|WI)_[0-9]+')
            or cat_id not in ('HOBBIES', 'FOODS', 'HOUSEHOLD')
            or state_id not in ('CA', 'TX', 'WI')
        ),
        count(*)
    from series

    union all

    -- SELL_PRICES: precio positivo y semana Walmart bien formada (1 + año de 2 dígitos + semana 01..53)
    select
        'sell_price nulo o <= 0',
        count_if(sell_price is null or sell_price <= 0),
        count(*)
    from {{ source('bronze', 'sell_prices') }}

    union all

    select
        'wm_yr_wk con formato inválido',
        count_if(not regexp_like(to_varchar(wm_yr_wk), '1[0-9]{2}(0[1-9]|[1-4][0-9]|5[0-3])')),
        count(*)
    from {{ source('bronze', 'sell_prices') }}

    union all

    -- CALENDAR: la fecha avanza un día por cada d (base del join ventas → fecha en Silver)
    select
        'date distinta de 2011-01-29 + (d - 1)',
        count_if(date != dateadd(day, d_num - 1, '2011-01-29'::date)),
        count(*)
    from calendar

    union all

    select
        'weekday no coincide con date',
        count_if(left(weekday, 3) != dayname(date)),
        count(*)
    from calendar

    union all

    select
        'snap_* fuera de {0, 1}',
        count_if(snap_ca not in (0, 1) or snap_tx not in (0, 1) or snap_wi not in (0, 1)),
        count(*)
    from calendar

    union all

    select
        'event_type fuera de los 4 tipos',
        count_if(
            (event_type_1 is not null and event_type_1 not in ('Cultural', 'National', 'Religious', 'Sporting'))
            or (event_type_2 is not null and event_type_2 not in ('Cultural', 'National', 'Religious', 'Sporting'))
        ),
        count(*)
    from calendar

    union all

    -- Nombre y tipo de evento van juntos: los nulos son estructurales (día sin evento), no datos perdidos.
    select
        'event_name y event_type no nulos a la vez',
        count_if(
            (event_name_1 is null) != (event_type_1 is null)
            or (event_name_2 is null) != (event_type_2 is null)
        ),
        count(*)
    from calendar
)

select
    check_name,
    afectados,
    evaluados,
    round(100 * afectados / nullif(evaluados, 0), 2) as pct
from checks

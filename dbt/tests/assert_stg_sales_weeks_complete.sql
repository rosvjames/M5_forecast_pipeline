-- Ninguna celda se pierde en el unpivot.
-- OBJECT_CONSTRUCT omite los NULL, así que una celda vacía de la fuente desaparecería sin error.
-- Cada semana debe tener (series de su entrega) × (días de la semana: 7, salvo la última del M5, que tiene 2).
-- Devuelve las semanas que no cuadran; el test pasa si no devuelve filas.

with expected as (
    select week_idx, count(*) * least(7, 1941 - 7 * week_idx) as expected_rows
    from {{ source('bronze', 'sales_raw') }}
    group by week_idx
),

actual as (
    select week_idx, count(*) as actual_rows
    from {{ ref('stg_sales') }}
    group by week_idx
)

select e.week_idx, e.expected_rows, a.actual_rows
from expected e
left join actual a using (week_idx)
where a.actual_rows is null or a.actual_rows != e.expected_rows

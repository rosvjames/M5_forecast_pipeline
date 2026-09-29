# Calidad de datos (Fase 2)

Base para la sección *Data Quality* del documento técnico. Todas las cifras salen de SQL en Snowflake y se pueden reproducir. Calendario y precios se leen de Bronze. Las ventas se leen de `SILVER.stg_sales`, que es `BRONZE.SALES_RAW` en formato largo, sin filtros ni correcciones (una celda de la entrega = una fila):

```
docker compose run --rm dbt build -s stg_sales+ source:bronze   # contrato de ingesta + stg_sales y sus tests
docker compose run --rm dbt show -s dq_01_completitud --limit 20
docker compose run --rm dbt show -s dq_02_precision   --limit 20
docker compose run --rm dbt show -s dq_03_consistencia --limit 20
docker compose run --rm dbt show -s dq_04_validez     --limit 20
```

*Corte: 29-sep-2026, `SALES_RAW` con las semanas 0–276 (8.445.730 filas) → `stg_sales` hasta d_1939 (59.120.110 filas). Las cifras son idénticas a las del corte del 27-sep, medidas sobre la tabla v1 en formato largo (`BRONZE.SALES`, ya eliminada). La semana 277 (d_1940–1941) entra con el cron del 3-oct; los porcentajes pueden moverse en décimas.*

## Cómo se organiza la revisión

| Capa | Qué se verifica | Herramienta |
|---|---|---|
| Bronze | **Contrato de ingesta:** unicidad de llaves naturales (en ventas, una fila por serie y entrega), llaves no nulas, `wm_yr_wk` existe en calendar | Tests de dbt sobre `source()` |
| Silver (`stg_sales`) | **Unpivot sin pérdidas:** unicidad de (item, store, d), `d` existe en calendar, `sales` ≥ 0, todas las semanas completas | Tests de `stg_sales.yml` y `assert_stg_sales_weeks_complete` |
| Bronze + `stg_sales` | **Contenido:** completitud, precisión, consistencia, validez | `dbt/analyses/dq_01`–`dq_04` (solo lectura) |
| Silver / Gold | **Acción:** flags, filtros y tests de reglas de negocio | Modelos dbt (Fases 3 y 4) |

Bronze no se corrige ni se testea por contenido: conserva la entrega original. `stg_sales` solo cambia la forma (ancho → largo), no los valores. Los problemas se miden aquí y se tratan en los modelos Silver que vienen después.

## Problemas encontrados

| # | Dimensión | Problema | Evidencia | Acción | Justificación |
|---|---|---|---|---|---|
| 1 | Completitud | Ceros antes del lanzamiento del producto | 12.299.413 días-serie: 20,8 % de la matriz y 30,6 % de todos los ceros. 0 ventas antes de la primera semana con precio | Flag `is_pre_launch` en Silver. Se excluyen del entrenamiento y de las métricas | El producto no estaba en la tienda: no es demanda cero. Se marca en vez de borrar para mantener completa la malla SKU × día y que la exclusión quede explícita. Test en Gold: ninguna venta antes del lanzamiento |
| 2 | Precisión | Navidad: tiendas cerradas | 5 días con 11–20 u en total, frente a ~30 mil un día normal. Son los únicos días de la cadena bajo el 10 % de la mediana móvil de 29 días | Flag `is_christmas_closed`. Se excluyen del entrenamiento y de la evaluación | El cero lo causa el cierre, no la demanda. Si el modelo lo aprende, subestima la víspera y el año siguiente |
| 3 | Precisión | Cierres puntuales de tienda | 2 días-tienda bajo el 10 % de la mediana móvil fuera de Navidad: WI_1 2011-02-02 (2 u) y TX_2 2015-03-24 (131 u) | Flag `is_store_closed` para esas tiendas y fechas | Mismo motivo que Navidad, pero en una sola tienda. Las otras 19 caídas bajo el 50 % (sobre todo Thanksgiving) son demanda real: las explica el calendario de eventos y no se marcan |
| 4 | Precisión | Quiebres de stock no observados (censura) | M5 no trae inventario. Tras el lanzamiento el precio nunca falta: 0 de 46,8 M días-serie sin precio, incluidos los días sin venta. Por eso el precio no delata quiebres. Rachas de ceros anómalas (EDA): 4,2 % de los días activos con la regla conservadora y 14,4 % con la binomial negativa | Flags `is_suspected_stockout_conservative` y `is_suspected_stockout_nb` en Silver (window functions sobre rachas) | No se puede separar un quiebre de una caída real de demanda. Se marca con dos reglas para hacer un análisis de sensibilidad y se declara como limitación: el nivel de servicio del backtest es optimista |
| 5 | Precisión | Picos extremos de venta | 1.934 series (6,3 %) con algún día > 10× su mediana de días con venta y ≥ 20 u. Son 6.497 días-serie (0,01 %) | Flag `is_sales_spike`. No se eliminan | Mezclan ventas reales grandes (compras institucionales, eventos) con posibles errores (601 u en una serie de mediana 1) y en M5 no se pueden distinguir. Borrarlos eliminaría demanda real. El flag permite medir su efecto |
| 6 | Precisión | `sell_price` es un promedio semanal, no el precio de lista | 21,3 % de los precios terminan en centavos atípicos (2, 3, 4, 6); los precios de lista terminan en 8, 7 o 0 | Se conserva tal cual y se documenta | Es el único precio disponible. Sirve como feature y para valorizar el inventario, pero no como precio exacto de cada transacción |
| 7 | Precisión | Precios extremos | 445 precios (0,007 %) > 5× o < 0,2× la mediana de su serie; 12 precios de $0,01 en 7 series | Se conservan y se documentan | Probables liquidaciones o errores de captura. Por su volumen no afectan los ingresos agregados, y corregirlos exigiría inventar un valor |
| 8 | Completitud | Nulos en eventos | 1.807 días sin `event_name_1` (91,8 %). En el 100 % de los casos, nombre y tipo son nulos a la vez | Ninguna imputación. En Silver se leen como "sin evento" | Es un nulo estructural (día sin evento), no un dato perdido |

## Verificaciones sin hallazgos

Confirman los supuestos de los que dependen los joins y las dimensiones de Silver y Gold.

| Dimensión | Verificación | Resultado | Por qué importa |
|---|---|---|---|
| Completitud | Semanas 0–276 sin huecos: 30.490 filas por entrega en `SALES_RAW` (= `LOAD_LOG`) y 30.490 × 7 en `stg_sales` | 0 fallas en 277 semanas | La ingesta con Kestra no perdió ni duplicó lotes, y el unpivot no perdió celdas |
| Completitud | Todas las series tienen todos los días; calendario d_1–d_1969 continuo | 0 fallas | Malla completa SKU × día para el fact |
| Consistencia | Unicidad de (item, store, week_idx) en `SALES_RAW`, (item, store, d) en `stg_sales` y (store, item, wm_yr_wk) en precios | 0 duplicados (tests de dbt) | Evidencia de idempotencia de la carga |
| Consistencia | Un item → un dept → una cat; una tienda → un estado; `id` = item + store + sufijo | 0 contradicciones en 30.490 series | `dim_item` y `dim_store` se construyen sin reglas de resolución y `id` se descarta por redundante |
| Consistencia | Mismos 30.490 pares item × tienda en ventas y en precios | 0 pares huérfanos | El join de precios no deja series sin precio |
| Validez | `sales` ≥ 0 y no nulo; `d` en d_1–d_1941; `week_idx` coherente con `d` | 0 fallas en 59,1 M filas | Variable objetivo válida; cada fila entró en su lote |
| Validez | `sell_price` > 0; `wm_yr_wk` con formato válido y presente en calendar | 0 fallas en 6,8 M filas | El join por `wm_yr_wk` no pierde filas |
| Validez | `date` = 2011-01-29 + (d − 1); `weekday` coincide; SNAP ∈ {0,1}; 4 tipos de evento | 0 fallas en 1.969 días | La conversión `d` → fecha de Silver es exacta |

## Notas

- Las cifras coinciden con el EDA en Python (`eda/reports/01`–`04`). Las diferencias son de décimas y vienen del corte en d_1939.
- Al rediseñar la ingesta (v2, 28-sep) se volvieron a correr `dq_01`–`dq_04` sobre `stg_sales`: todas las cifras de este documento se mantuvieron idénticas.
- El EDA reportaba 10 precios de $0,01. El conteo en Snowflake y en el CSV original es 12 (se corrigió `02_sell_prices.md`).
- Umbrales usados, iguales a los del EDA: día anómalo = < 10 % de la mediana móvil centrada de 29 días; pico = > 10× la mediana de los días con venta y ≥ 20 u; precio extremo = > 5× o < 0,2× la mediana de la serie.

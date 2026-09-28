# Calidad de datos (Fase 2)

Base para la sección *Data Quality* del documento técnico. Todas las cifras salen de SQL sobre Bronze en Snowflake y se pueden reproducir:

```
docker compose run --rm dbt test -s source:bronze          # contrato de ingesta (14 tests)
docker compose run --rm dbt show -s dq_01_completitud --limit 20
docker compose run --rm dbt show -s dq_02_precision   --limit 20
docker compose run --rm dbt show -s dq_03_consistencia --limit 20
docker compose run --rm dbt show -s dq_04_validez     --limit 20
```

*Corte: 27-sep-2026, `SALES` hasta d_1939 (59.120.110 filas). La semana 277 (d_1940–1941) entra con el cron del 3-oct; los porcentajes pueden moverse en décimas.*

## Cómo se organiza la revisión

| Capa | Qué se verifica | Herramienta |
|---|---|---|
| Bronze | **Contrato de ingesta:** unicidad de llaves naturales, llaves no nulas, `d` y `wm_yr_wk` existen en calendar | Tests de dbt sobre `source()` (14/14 PASS) |
| Bronze | **Contenido:** completitud, precisión, consistencia, validez | `dbt/analyses/dq_01`–`dq_04` (solo lectura) |
| Silver / Gold | **Acción:** flags, filtros y tests de reglas de negocio | Modelos dbt (Fases 3 y 4) |

Bronze no se corrige ni se testea por contenido: conserva el dato original. Los problemas se miden aquí y se tratan en Silver.

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
| Completitud | Semanas 0–276 sin huecos, 30.490 × 7 filas cada una, filas = `LOAD_LOG` | 0 fallas en 277 semanas | La ingesta con Kestra no perdió ni duplicó lotes |
| Completitud | Todas las series tienen todos los días; calendario d_1–d_1969 continuo | 0 fallas | Malla completa SKU × día para el fact |
| Consistencia | Unicidad de (item, store, d) y de (store, item, wm_yr_wk) | 0 duplicados (tests de Bronze) | Evidencia de idempotencia de la carga |
| Consistencia | Un item → un dept → una cat; una tienda → un estado; `id` = item + store + sufijo | 0 contradicciones en 30.490 series | `dim_item` y `dim_store` se construyen sin reglas de resolución y `id` se descarta por redundante |
| Consistencia | Mismos 30.490 pares item × tienda en ventas y en precios | 0 pares huérfanos | El join de precios no deja series sin precio |
| Validez | `sales` ≥ 0 y no nulo; `d` en d_1–d_1941; `week_idx` coherente con `d` | 0 fallas en 59,1 M filas | Variable objetivo válida; cada fila entró en su lote |
| Validez | `sell_price` > 0; `wm_yr_wk` con formato válido y presente en calendar | 0 fallas en 6,8 M filas | El join por `wm_yr_wk` no pierde filas |
| Validez | `date` = 2011-01-29 + (d − 1); `weekday` coincide; SNAP ∈ {0,1}; 4 tipos de evento | 0 fallas en 1.969 días | La conversión `d` → fecha de Silver es exacta |

## Notas

- Las cifras coinciden con el EDA en Python (`eda/reports/01`–`04`). Las diferencias son de décimas y vienen del corte en d_1939.
- El EDA reportaba 10 precios de $0,01. El conteo en Snowflake y en el CSV original es 12 (se corrigió `02_sell_prices.md`).
- Umbrales usados, iguales a los del EDA: día anómalo = < 10 % de la mediana móvil centrada de 29 días; pico = > 10× la mediana de los días con venta y ≥ 20 u; precio extremo = > 5× o < 0,2× la mediana de la serie.

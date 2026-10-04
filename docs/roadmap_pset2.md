# Roadmap PSet 2 — Pipeline ELT end-to-end

Fuente → Kestra → Bronze → dbt → Silver → dbt → Gold → Spark → OBT (todo en Snowflake)

Enunciado: `CD_PSet_2.pdf`. Enfoque y decisiones del proyecto: `docs/enfoque_proyecto.md` (sección 8 = decisiones de ingesta, calidad y star schema ya tomadas).

Modo de trabajo: James implementa; Claude guía, revisa y explica. Marcar `[x]` al completar cada punto para poder retomar tras un `/clear`.

**Rúbrica:** Kestra 15 % · Calidad 20 % · dbt/Bronze-Silver-Gold 15 % · Star schema 15 % · Spark/OBT 15 % · Infra y reproducibilidad 10 % · Documento 10 %.

**Entrega: domingo 4 de octubre de 2026.**

---

## ▶ Retomar aquí (2-oct)

Fase 3 (Silver) cerrada salvo los flags de quiebre de stock, que se dejaron para después de Spark (decisión 2-oct: Gold y Spark pesan 30 % y estaban en cero; los quiebres se agregan luego con un `left join` al fact sin rediseñar nada).

1. ~~Fase 4 (Gold)~~ ✅ 2-oct, con diagrama en el README.
2. ~~Semana 277 y `dbt build -s stg_sales+`~~ ✅ 3 y 4-oct.
3. ~~Fase 5 (Spark → OBT)~~ ✅ re-corrida el 4-oct con la semana 277.
4. `int_stockout_flags` (calidad #4): reglas conservadora y binomial negativa, con `k` **causal** (ventana expansiva hasta el día previo a la racha; el EDA usaba la serie completa → fuga). Recalcular los % y actualizar `calidad_datos.md` #4 y el §5 del enfoque.
5. Documento (domingo).

## Estado actual y cómo sumarse

*Actualizado: 4-oct-2026.*

| Fase (PDF) | Estado |
|---|---|
| 0 · Infraestructura (PDF §1) | ✅ Docker Compose con Kestra, Spark y dbt, conectado a Snowflake. Diagrama en `docs/img/arquitectura.png`. |
| 1 · Ingesta Kestra → Bronze (PDF §2) | ✅ Rediseñada (v2, 28-sep): Bronze guarda las entregas semanales tal cual (`SALES_RAW`, formato ancho, carga por nombre de columna). Backfill v2 terminado y verificado (29-sep). Semana 277 cargada el 3-oct por ejecución de API (el tick del cron no disparó; ver Fase 1): 278 semanas, 8.476.220 filas. |
| 2 · Calidad (PDF §3) | ✅ Tests de contrato en Bronze y de unpivot en `stg_sales`, 4 analyses (`dbt/analyses/dq_0*`) y tabla de decisiones en `docs/calidad_datos.md`. Los flags se implementan en Silver. |
| 3 · dbt Silver | 🔄 `stg_calendar`, `stg_sell_prices` e `int_sales_daily` (fecha, precio, ingreso, SNAP y flags #1, #2, #3, #5) listos y testeados. Falta `int_stockout_flags` (#4), pospuesto. |
| 4 · dbt Gold (star schema) | ✅ `fact_sales`, `dim_date`, `dim_item`, `dim_store` y `dim_date_state` (SNAP) en `GOLD`, diagrama en el README (2-oct); 118 tests en verde en todo el proyecto (4-oct). |
| 5 · Spark → OBT | ✅ `spark/build_obt.py` (conector `spark-snowflake` 3.2.2 en `spark/Dockerfile`): `OBT.OBT_SALES`, 59.181.090 filas (278 semanas), validaciones OK (4-oct, ~13 min). |
| Orquestación de punta a punta | ✅ Flow `transform` (4-oct): se dispara al terminar `load_sales_week` y corre `dbt build` y luego `spark-submit build_obt.py`. Detalle en el paso 10 del README. |
| 6 · Documento y README | ✅ Memo en PDF (`PSet2_memo_*.pdf`) y README con los pasos 1–10 (4-oct). Falta probar el README en una cuenta limpia. |

**Qué hay en Snowflake:**
- `BRONZE.CALENDAR` y `BRONZE.SELL_PRICES`: valores originales de Kaggle cargados por nombre de columna, más `_source_file`, `_batch_id` y `_loaded_at`.
- `BRONZE.SALES_RAW`: entregas semanales de ventas tal como las publica la fuente (formato ancho: jerarquía + columnas `D_N`, que crea schema evolution; una fila por serie y entrega) + `week_idx`, `_source_file`, `_source_row`, `_batch_id`, `_loaded_at`.
- `SILVER.stg_sales` (dbt, incremental): las ventas en formato largo, una fila por `item_id` × `store_id` × `d`.
- `SILVER.stg_calendar` (view), `SILVER.stg_sell_prices` (table, con `launch_wm_yr_wk`) y el seed `SILVER.store_closures`.
- `SILVER.int_sales_daily` (table, ~30 s): ventas + fecha + precio + ingreso + SNAP + flags de calidad. Es la base de `fact_sales`.
- `GOLD` (star schema, tables): `fact_sales` (item × tienda × día, 59 M filas), `dim_date` (1.969 días con horizonte, `week_seq`, `date_key_ly_364`), `dim_item` (3.049), `dim_store` (10) y `dim_date_state` (SNAP por fecha × estado, 5.907).
- `LOAD_LOG` guarda la auditoría de cargas. En `@RAW_STAGE/m5/` están los CSV de Kaggle y en `@RAW_STAGE/m5/sales_weekly/` las entregas semanales.

**Tareas que se pueden adelantar sin bloquear la ingesta.** Anota tu nombre en la tarea antes de empezar, para no duplicar trabajo.

| Tarea | Fase | Depende de | Responsable |
|---|---|---|---|
| ~~Consultas de calidad sobre Bronze~~ ✅ hecho (`dbt/analyses/dq_0*`, `docs/calidad_datos.md`) | 2 | — | James |
| ~~Modelos `stg_calendar`, `stg_sell_prices` e `int_sales_daily`~~ ✅ hecho | 3 | — | James |
| `int_stockout_flags` (calidad #4, `k` causal) | 3 | `int_sales_daily` | |
| ~~Conector Spark–Snowflake y prueba de lectura~~ ✅ hecho (`spark/Dockerfile`, `spark/test_connection.py`) | 5 | — | James |
| Diagrama de arquitectura y sección *Batch vs. streaming* del documento | 6 | Nada | |

**Reglas para trabajar en paralelo:**
- Una rama por tarea y PR a `main`. No edites `kestra/` sin avisar: los flows están corriendo.
- Snowflake: pendiente decidir si cada uno usa su propia cuenta trial (el README reproduce todo desde cero, con ~2 h 45 min de backfill) o si se crean usuarios en la cuenta compartida. **Nadie** usa el usuario de servicio `M5_PIPELINE_USER` con una llave copiada.
- Los modelos dbt leen de `source('bronze', ...)`, nunca con nombres de tabla escritos a mano.

---

## Fase 0 — Setup (base de todo)

- [x] Crear el repo `pset_2/` con git: `docker-compose.yml`, `.env.example`, `README.md`, `kestra/`, `dbt/`, `spark/`, `docs/`.
- [x] `.gitignore`: `.env`, datos (`*.csv`, `*.parquet`), `target/`, `logs/`, llaves privadas. **Nunca subir credenciales.**
- [x] Snowflake: cuenta (trial), warehouse XS con auto-suspend, base de datos `M5`, esquemas `BRONZE`, `SILVER`, `GOLD`, `OBT`. Rol y usuario de servicio para el pipeline (autenticación por key-pair).
- [x] Token de Kaggle (aceptar las reglas de M5 con la cuenta). Va como secret en Kestra, no en el repo.
- [x] `docker-compose.yml` mínimo: Kestra (+ Postgres como backend) y Spark (master + worker, imagen oficial `apache/spark`). dbt Core en Docker (el enunciado solo permite Docker o dbt Cloud).
- [x] Verificar: Kestra UI abre, Spark UI abre, `dbt debug` conecta a Snowflake.

**Listo cuando:** `docker compose up` levanta todo y hay conexión a Snowflake desde Kestra, dbt y Spark.

## Fase 1 — Ingesta con Kestra → Bronze (15 %)

**Decisión revisada (28-sep, tras feedback del profesor): v2 implementada.** La v1 hacía el `UNPIVOT` en la ingesta y leía columnas por posición (`$n`): si la fuente cambiaba de formato, corrompía datos sin avisar. Ahora:
- **Simulador de fuente** (`publish_week`): un *unload* en Snowflake (`COPY INTO @stage`, `HEADER = TRUE`) publica cada semana un CSV **ancho** con la jerarquía + `d_(7k+1)..d_(7k+7)` en `@RAW_STAGE/m5/sales_weekly/sales_wk_<k>.csv.gz` (~2 s). Lee por posición porque hace de fuente y conoce su formato. (Primero fue Python con descarga del archivo, ~17 s; se reemplazó a mitad del backfill tras verificar que produce el mismo archivo línea por línea.)
- **Ingesta** (`load_week`): una transacción con `DELETE week_idx = k` → `COPY` a `BRONZE.SALES_RAW` con `PARSE_HEADER`, `MATCH_BY_COLUMN_NAME` e `INCLUDE_METADATA` (tabla con `ENABLE_SCHEMA_EVOLUTION`) → `UPDATE` de `week_idx`, `_batch_id` y `_loaded_at` → `LOAD_LOG`. No nombra ninguna columna de ventas.
- **Silver** (`stg_sales`): `OBJECT_CONSTRUCT(*)` + `FLATTEN` (unpivot por nombre, ~3× más rápido que `UNPIVOT` y sin lista de columnas), incremental `delete+insert` por `week_idx`. Test `assert_stg_sales_weeks_complete` para que no se pierdan celdas.
- `calendar` y `sell_prices` también se cargan con `MATCH_BY_COLUMN_NAME`.
- **Bug encontrado y corregido:** `MATCH_BY_COLUMN_NAME` no aplica `DEFAULT` → `_loaded_at` quedaba NULL. El `UPDATE` post-`COPY` ahora lo fija; las filas ya cargadas se completaron una vez con la hora real de `LOAD_LOG` (cruce por `_batch_id`).
- **No subir `concurrency`:** el `UPDATE ... WHERE week_idx IS NULL` supone una sola carga a la vez.
- Mejora posible (no aplicada): derivar `week_idx` de `_source_file` para evitar el `UPDATE`; `load_week` pasa de ~8 s a ~16–25 s a medida que la tabla crece.
- Por qué la tabla ancha y dispersa: M5 publica un archivo que crece una columna por día. Con una fuente real en formato largo, Bronze sería un append de filas.

Conceptos a decidir y poder explicar:
- **Bronze conserva el dato original:** CSV crudos en un stage de Snowflake (inmutables) + tablas Bronze con los valores sin alterar y metadatos de carga (`_loaded_at`, `_source_file`, `_batch_id`).
- **Reloj simulado:** M5 es estático. Cada ejecución semanal del trigger se mapea a una semana de M5 (fecha de ejecución − fecha ancla → índice de semana → rango d_). Ancla = 2021-06-12 (sábado). Hay 278 semanas (k = 0..277) y la 277 solo tiene 2 días.
- **Backfill:** k = 0..276 (d_1..d_1939) con el backfill nativo del Schedule trigger. La semana 277 (d_1940–1941) entra como carga incremental con el tick real del sábado 2026-10-03. El ancla se eligió para que ese tick cayera antes de la entrega.
- **Idempotencia:** delete + insert (o MERGE) por partición. Llaves: ventas (item_id, store_id, date); precios (store_id, item_id, wm_yr_wk). Re-ejecutar una semana no duplica.
- **Paso de archivos (decidido):** tareas separadas vía internal storage de Kestra (descarga con `outputFiles` → `snowflake.Upload` al stage → `COPY INTO`). Retry por tarea sin repetir la descarga. Purga con `PurgeCurrentExecutionFiles` en el bloque `finally`.
- **Errores:** `retry` exponencial en tareas de red/descarga/carga; bloque `errors` que registre la falla; timeouts.

Tareas:
- [x] Flow 1: descarga desde Kaggle (API) → stage de Snowflake. `calendar` y `sell_prices` como carga completa (son chicos) o precios por `wm_yr_wk`.
- [x] Flow 2: carga semanal de ventas a Bronze, un lote por semana (v1 en formato largo; reemplazada por v2, ver arriba).
- [x] Trigger semanal (cron) + backfill v1 ejecutado y verificado (59.120.110 filas, SUM 66.821.317).
- [x] Backfill v2 (`SALES_RAW`) terminado y verificado (29-sep): 277 ejecuciones en SUCCESS (label `backfill: v2-sales-raw`, 2 h 44 min, mediana 28 s por semana); 8.445.730 filas, 30.490 por semana, un lote por semana, 0 `_loaded_at` NULL; `stg_sales` con 59.120.110 filas y SUM 66.821.317, 23/23 tests PASS; `dq_01`–`dq_04` idénticas. `BRONZE.SALES` (v1) eliminada. Retry, `errors` e idempotencia re-probados con v2 (semanas 1, 2 y 10).
- [x] Probar un fallo a propósito para mostrar el retry. Input `simulate_failure` (TRANSIENT → 2 intentos y SUCCESS; PERMANENT → 3 intentos, bloque `errors` y fila FAILED en LOAD_LOG). Semana 100 sigue con 213.430 filas.
- [x] Probar la idempotencia: re-ejecutar una semana y verificar que el conteo no cambia.
- [x] **Sáb 3-oct:** semana 277 cargada (`SALES_RAW` 8.476.220 filas, 30.490 de la 277, 0 `_loaded_at` NULL). **No entró por el cron:** la Mac estaba suspendida a las 06:00 UTC y, al volver, el scheduler de Kestra no disparó el tick vencido ni con `recoverMissedSchedules: ALL`, ni tras dos reinicios, ni un backfill de esa fecha (quedó pendiente en el trigger). Se cargó con una ejecución por API con `week_idx = 277` (id `7e3WRGURerEdmwUkq9p0PC`). Causa del scheduler sin identificar: contarlo en Limitaciones. `dbt build -s stg_sales+` y la OBT re-corridos el 4-oct: 59.181.090 filas, SUM 66.927.173.

**Listo cuando:** Bronze tiene las 278 entregas de ventas (8.476.220 filas en `SALES_RAW` → 59.181.090 en `stg_sales`), 6.841.121 de precios y 1.969 de calendario, sin cargas manuales.

## Fase 2 — Calidad de datos (20 %, la más pesada)

**Decisión (27-sep):** Bronze se testea solo como contrato de ingesta: unicidad de llaves naturales, `not_null` en las llaves y `relationships` de `d` y `wm_yr_wk` hacia calendar. La calidad del contenido se mide con analyses (`dbt/analyses/dq_0*.sql`) y se corrige con flags y tests en Silver y Gold (`accepted_values`, rangos, reglas de negocio).

- [x] `sources.yml` sobre `BRONZE` (4 tablas, freshness en `sales`).
- [x] `packages.yml` con `dbt_utils` y tests de contrato en los sources. `dbt test -s source:bronze`: 14/14 PASS (27-sep, 12,6 s).
- [x] Recalcular en Snowflake (SQL sobre Bronze) las métricas del EDA: completitud, precisión, consistencia, validez. `dbt/analyses/dq_01`–`dq_04`, todas < 15 s.
- [x] Tabla Problema | Evidencia | Acción | Justificación: `docs/calidad_datos.md`.
- [x] Cada decisión con métrica concreta (ej. "20,8 % de los días-serie son previos al lanzamiento").
- [ ] Cada acción con su modelo o test en dbt: se completa en las Fases 3 y 4 (flags de `docs/calidad_datos.md`).

**Listo cuando:** la tabla está completa y cada acción tiene su modelo o test en dbt.

## Fase 3 — dbt Silver (limpieza)

- [x] Proyecto dbt con `sources.yml` sobre Bronze (usar `source()`), perfiles por variables de entorno.
- [x] Modelos `stg_*`: `stg_sales` (unpivot), `stg_calendar` (d_num, SNAP booleano, eventos, Navidad, horizonte), `stg_sell_prices` (`launch_wm_yr_wk`).
- [x] `int_sales_daily`: join ventas → calendario → precios (left, por tienda + item + `wm_yr_wk`), ingreso, SNAP del estado. Cifras iguales a `calidad_datos.md`.
- [x] Flags: `is_pre_launch` (#1, por primera semana con precio, no por primera venta: 144 series se lanzaron antes de vender), `is_christmas_closed` (#2), `is_store_closed` (#3, seed `store_closures`), `is_sales_spike` (#5, solo diagnóstico).
- [ ] `int_stockout_flags`: `is_suspected_stockout_conservative` y `is_suspected_stockout_nb` (#4, `k` causal). **Pospuesto** hasta después de Spark.
- [x] Materialización: `stg_sales` incremental por semana; `int_sales_daily` table (la mediana de picos usa la serie completa; rebuild ~30 s); `stg_sell_prices` table; `stg_calendar` view.
- [x] Tests: grain, `equal_rowcount` contra `stg_sales`, sin ventas antes del lanzamiento, sin días post-lanzamiento sin precio, `accepted_values`, rangos, conversión `d` → fecha exacta.

## Fase 4 — dbt Gold (star schema, 15 %)

- [x] `fact_sales`: grain SKU–tienda–día; medidas: unidades, precio, ingreso; flags de calidad.
- [x] `dim_item`, `dim_store`, `dim_date` (índice secuencial de semana, flags de evento, `date_ly_364`, horizonte futuro), `dim_date_state` (SNAP fecha × estado; se llamaba `bridge_snap`, pero no es un puente: la relación con el fact es muchos a uno).
- [x] Todo con `ref()`.
- [x] Tests con reglas reales del negocio (más: horizonte sin ventas, ingreso = unidades × precio, llave compuesta del SNAP, calendario sin huecos):
  - `relationships` fact → dims.
  - Unicidad del grain.
  - Ninguna venta sin precio.
  - Ninguna venta antes del lanzamiento.
  - El join de precios no cambia el conteo de filas.
- [x] Diagrama del star schema (Mermaid en el README, sección "Modelo de datos (Gold)").

## Fase 5 — Spark → OBT (15 %)

- [x] Leer Gold desde Snowflake con el conector Spark-Snowflake: jars en la imagen (`spark/Dockerfile`), key-pair con `pem_private_key`, `autopushdown` apagado para que los joins los haga Spark. Prueba: `spark/test_connection.py`.
- [x] Construir la OBT: fact + dims + SNAP del estado de la tienda (left joins con broadcast). Grain = SKU–tienda–día (el mismo del fact). Sin `persist`: cachear 59 M filas dio OutOfMemoryError con 4 GB de worker.
- [x] Validar joins: conteo antes = después, unicidad de la llave, nulos en columnas de dims = 0, estado fact = estado `dim_store`. Si algo falla, no escribe.
- [x] Escribir en `OBT` de Snowflake (`OBT_SALES`, overwrite con tabla de staging) y verificar el conteo leyendo de vuelta.
- [x] Re-corrida tras la semana 277 (4-oct): `dbt build -s stg_sales+` (`stg_sales` y `fact_sales` con 59.181.090 filas, SUM 66.927.173) y `build_obt.py` → `OBT.OBT_SALES` con 59.181.090 filas, todas las validaciones OK, 756 s. Ojo: tras suspender la Mac el worker de Spark se desregistra del master (el job queda esperando recursos); se arregla con `docker compose restart spark-worker`.
- [x] Explicar cuándo usar el star schema (análisis, BI, dbt tests) y cuándo la OBT (entrenar el modelo).

## Fase 6 — Documento técnico (≤ 6 páginas) y README

- [x] Diagrama de arquitectura: `docs/img/arquitectura.png` (fuente `arquitectura.py` → SVG), insertado en el README.
- [x] Secciones: Arquitectura, Ingesta, Data Quality, Transformaciones y modelado, Spark y OBT, Batch vs streaming, Limitaciones.
- [x] Batch vs streaming: M5 es diario/histórico y la decisión (reposición semanal) tolera latencia de días. Streaming solo se justificaría con reposición intradía, inventario en tiempo real o alertas de quiebre.
- [ ] README: cómo levantar la infraestructura y ejecutar Kestra, dbt y Spark paso a paso. Probarlo desde cero.
- [x] Nombre del archivo: `PSet2_memo_<apellido_1>_<apellido_2>.pdf`.

**Decisiones revisadas (contar en la sección Ingesta y en Limitaciones):**
- **Ingesta v1 → v2 (28-sep, feedback de Erick).** v1 hacía el `UNPIVOT` en la ingesta y leía las columnas por posición (`$n`): un cambio de formato en la fuente habría corrompido datos sin error. v2 guarda la entrega tal cual en `SALES_RAW` (formato ancho, `COPY` por nombre de columna, schema evolution) y hace el unpivot en dbt (`stg_sales`). Se validó que v2 reproduce v1: mismas 59.120.110 filas, mismo SUM y mismas cifras de calidad.
- **Costo de v2:** el backfill pasó de ~35 min (v1, ~6 s por semana) a ~2 h 45 min (mediana 28 s por semana), porque el `UPDATE` post-`COPY` recorre una tabla que crece. Mejora posible: derivar `week_idx` de `_source_file` y evitar el `UPDATE`.
- **Gotchas que vale la pena mencionar:** `MATCH_BY_COLUMN_NAME` no aplica los `DEFAULT` (por eso `_loaded_at` se fija en el `UPDATE`), y la carga supone `concurrency: 1`.
- **Flags y fuga de información (Limitaciones):** `is_sales_spike` usa la mediana de la serie completa y por eso es solo diagnóstico: nunca feature, nunca filtro de entrenamiento, nunca excluye días de la métrica principal. Los flags de quiebre sí filtran, así que su dispersión `k` se calcula con ventana causal (el EDA la calculaba con la serie completa).
- **Tabla ancha y dispersa:** es consecuencia de cómo publica M5 (un archivo que crece una columna por día). Con una fuente real en formato largo, Bronze sería un append de filas.

---

## Orden sugerido

0 → 1 → 3 → 4 → 5 → 6. La Fase 2 corre en paralelo desde que Bronze tiene datos. El documento se escribe a medida que se avanza, no al final.

## Riesgos a vigilar

- **Créditos de Snowflake:** warehouse XS, auto-suspend de 60 s y cuidado con las cargas repetidas.
- **Memoria de Spark local** con 59 M de filas: subir la memoria del driver y del worker, o probar primero con una tienda.
- **Mapeo del reloj simulado y del backfill:** definirlo por escrito antes de programar.
- **Precios:** unir por `wm_yr_wk` vía `dim_date`, nunca restar códigos de semana (el año fiscal 2013 tiene 53 semanas).

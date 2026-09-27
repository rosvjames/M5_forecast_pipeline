# Roadmap PSet 2 — Pipeline ELT end-to-end

Fuente → Kestra → Bronze → dbt → Silver → dbt → Gold → Spark → OBT (todo en Snowflake)

Enunciado: `CD_PSet_2.pdf`. Enfoque y decisiones del proyecto: `docs/enfoque_proyecto.md` (sección 8 = decisiones de ingesta, calidad y star schema ya tomadas).

Modo de trabajo: James implementa; Claude guía, revisa y explica. Marcar `[x]` al completar cada punto para poder retomar tras un `/clear`.

**Rúbrica:** Kestra 15 % · Calidad 20 % · dbt/Bronze-Silver-Gold 15 % · Star schema 15 % · Spark/OBT 15 % · Infra y reproducibilidad 10 % · Documento 10 %.

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

Conceptos a decidir y poder explicar:
- **Bronze conserva el dato original:** CSV crudos en un stage de Snowflake (inmutables) + tablas Bronze con los valores sin alterar y metadatos de carga (`_loaded_at`, `_source_file`, `_batch_id`).
- **Reloj simulado:** M5 es estático. Cada ejecución semanal del trigger se mapea a una semana de M5 (fecha de ejecución − fecha ancla → índice de semana → rango d_).
- **Backfill:** d_1..d_1913 por semanas usando el backfill nativo del Schedule trigger. Las últimas 4 semanas (d_1914..d_1941) quedan como cargas incrementales.
- **Idempotencia:** delete + insert (o MERGE) por partición. Llaves: ventas (item_id, store_id, date); precios (store_id, item_id, wm_yr_wk). Re-ejecutar una semana no duplica.
- **Paso de archivos (decidido):** tareas separadas vía internal storage de Kestra (descarga con `outputFiles` → `snowflake.Upload` al stage → `COPY INTO`). Retry por tarea sin repetir la descarga. Purga con `PurgeCurrentExecutionFiles` en el bloque `finally`.
- **Errores:** `retry` exponencial en tareas de red/descarga/carga; bloque `errors` que registre la falla; timeouts.

Tareas:
- [ ] Flow 1: descarga desde Kaggle (API) → stage de Snowflake. `calendar` y `sell_prices` como carga completa (son chicos) o precios por `wm_yr_wk`.
- [ ] Flow 2: carga semanal de ventas a Bronze (formato largo con valores originales, un lote por semana).
- [ ] Trigger semanal (cron) + backfill ejecutado y verificado (conteo de filas por semana).
- [ ] Probar un fallo a propósito para mostrar el retry.
- [ ] Probar la idempotencia: re-ejecutar una semana y verificar que el conteo no cambia.

**Listo cuando:** Bronze tiene 59.181.090 filas de ventas, 6.841.121 de precios y 1.969 de calendario, sin cargas manuales.

## Fase 2 — Calidad de datos (20 %, la más pesada)

- [ ] Recalcular en Snowflake (SQL sobre Bronze) las métricas del EDA: completitud, precisión, consistencia, validez. Las cifras de referencia están en `eda/reports/01`–`04`.
- [ ] Tabla Problema | Evidencia | Acción | Justificación (base: `enfoque_proyecto.md`, sección 8).
- [ ] Cada decisión con métrica concreta (ej. "20,9 % de los días-serie son previos al lanzamiento").

**Listo cuando:** la tabla está completa y cada acción tiene su modelo o test en dbt.

## Fase 3 — dbt Silver (limpieza)

- [ ] Proyecto dbt con `sources.yml` sobre Bronze (usar `source()`), perfiles por variables de entorno.
- [ ] Modelos `stg_*`: tipos, nombres, fechas (join a calendar), jerarquía.
- [ ] Limpieza: `is_pre_launch`, `is_christmas_closed`, cierres puntuales, `is_suspected_stockout_conservative` (SQL con window functions), picos marcados.
- [ ] Materialización: incremental para ventas (por semana), table para el resto.
- [ ] Tests: `not_null`, `unique` / `unique_combination_of_columns`, `accepted_values`, rangos (ventas ≥ 0).

## Fase 4 — dbt Gold (star schema, 15 %)

- [ ] `fact_sales`: grain SKU–tienda–día; medidas: unidades, precio, ingreso; flags de calidad.
- [ ] `dim_item`, `dim_store`, `dim_date` (índice secuencial de semana, flags de evento, `date_ly_364`, horizonte futuro), `bridge_snap` (fecha × estado).
- [ ] Todo con `ref()`.
- [ ] Tests con reglas reales del negocio:
  - `relationships` fact → dims.
  - Unicidad del grain.
  - Ninguna venta sin precio.
  - Ninguna venta antes del lanzamiento.
  - El join de precios no cambia el conteo de filas.
- [ ] Diagrama del star schema.

## Fase 5 — Spark → OBT (15 %)

- [ ] Leer Gold desde Snowflake con el conector Spark-Snowflake (jars en la imagen o en `spark/`).
- [ ] Construir la OBT: fact + dims + SNAP del estado de la tienda. Grain = SKU–tienda–día (el mismo del fact).
- [ ] Validar joins: conteo antes = después, unicidad de la llave, nulos en columnas de dims = 0.
- [ ] Escribir en `OBT` de Snowflake.
- [ ] Explicar cuándo usar el star schema (análisis, BI, dbt tests) y cuándo la OBT (entrenar el modelo).

## Fase 6 — Documento técnico (≤ 6 páginas) y README

- [ ] Diagrama de arquitectura.
- [ ] Secciones: Arquitectura, Ingesta, Data Quality, Transformaciones y modelado, Spark y OBT, Batch vs streaming, Limitaciones.
- [ ] Batch vs streaming: M5 es diario/histórico y la decisión (reposición semanal) tolera latencia de días. Streaming solo se justificaría con reposición intradía, inventario en tiempo real o alertas de quiebre.
- [ ] README: cómo levantar la infraestructura y ejecutar Kestra, dbt y Spark paso a paso. Probarlo desde cero.
- [ ] Nombre del archivo: `PSet2_memo_<apellido_1>_<apellido_2>.pdf`.

---

## Orden sugerido

0 → 1 → 3 → 4 → 5 → 6. La Fase 2 corre en paralelo desde que Bronze tiene datos. El documento se escribe a medida que se avanza, no al final.

## Riesgos a vigilar

- **Créditos de Snowflake:** warehouse XS, auto-suspend de 60 s y cuidado con las cargas repetidas.
- **Memoria de Spark local** con 59 M de filas: subir la memoria del driver y del worker, o probar primero con una tienda.
- **Mapeo del reloj simulado y del backfill:** definirlo por escrito antes de programar.
- **Precios:** unir por `wm_yr_wk` vía `dim_date`, nunca restar códigos de semana (el año fiscal 2013 tiene 53 semanas).

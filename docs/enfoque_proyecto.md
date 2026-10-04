# Enfoque actualizado del proyecto

Grupo: Isabella Tulcán, Gabriel Ávalos, Keoma Quiroga, David Bucheli, James Soto
Última actualización: 2026-09-29

Este documento registra los cambios al planteamiento del PSet 1 tras la defensa y el análisis exploratorio. No reemplaza el memo del PSet 1: explica qué cambió, por qué, y qué decisiones quedan fijadas para el PSet 2 en adelante.

> **Pendiente:** confirmación de Erick de que se pueden hacer cambios justificados al planteamiento del PSet 1 (correo enviado el 2026-09-25).

---

## 1. Qué cambió y por qué

Feedback de la defensa del PSet 1:

1. **Ventas observadas ≠ demanda.** Si un producto se agota, la demanda no atendida no queda registrada.
2. **Conexión débil con reposición.** El modelo aporta, pero no conecta por sí solo con la decisión de inventario (EOQ, punto de reorden).
3. **Un solo baseline no demuestra que el modelo sea bueno.** Hay que comparar contra varios, incluido el mismo periodo del año anterior.

| Elemento | PSet 1 | Ahora | Motivo |
|---|---|---|---|
| Dataset | M5 | M5 (se mantiene) | Ningún dataset público lo supera en conjunto (sección 6) |
| Pregunta de negocio | Reducción simulada de faltantes y excedentes | Stock de seguridad y ROP necesarios para un nivel de servicio objetivo | La versión anterior dependía de inventario, órdenes y costos inventados |
| Métrica principal | WAPE por SKU–tienda | WRMSSE + WAPE pooled del acumulado de L días | El WAPE por serie premia pronosticar ceros (sección 3) |
| Baseline | Promedio móvil de 30 días | Cuatro baselines: media 28 días, naive semanal, año anterior (t−364), Croston SBA | Feedback de Erick |
| Censura | Mencionada como riesgo | Marca `is_suspected_stockout` + análisis de sensibilidad | El EDA confirma que es relevante (sección 5) |

---

## 2. Pregunta de negocio

> **¿Cuánto stock de seguridad se necesita para alcanzar un nivel de servicio objetivo usando nuestro pronóstico, frente a los baselines?**

**Lógica.** El stock de seguridad depende de cuánto se equivoca el pronóstico durante el lead time. Si el modelo reduce ese error, se necesita menos inventario para el mismo nivel de servicio. Ese inventario extra es capital inmovilizado.

**Cálculo por SKU–tienda:**

- `D_L` = demanda pronosticada acumulada durante el lead time `L`.
- `SS` = percentil `q` del error acumulado de `L` días, obtenido del backtesting.
- `ROP = D_L + SS`.

Se usa el **percentil empírico** del error y no la fórmula `z·σ·√L`, porque el 91 % de las series es intermitente o lumpy: el error no es normal ni independiente día a día. En series con poca venta, el percentil se estima agrupando por segmento (departamento × clase de intermitencia) para evitar estimaciones ruidosas.

**Validación (backtesting):**

- **Nivel de servicio logrado:** fracción de ventanas en que la venta real acumulada de `L` días fue ≤ ROP. Debe acercarse al objetivo.
- **Stock de seguridad total**, en unidades y en dinero (con `sell_price`).
- **Entregable principal:** curva nivel de servicio vs. stock de seguridad por método. Si la curva del modelo domina a la de los baselines, el modelo logra más servicio con el mismo inventario.

**Qué se valida con datos reales y qué es supuesto:**

| Con datos reales | Supuesto explícito |
|---|---|
| Error del pronóstico y su distribución | Lead time `L`: base 7 días, sensibilidad 3 / 7 / 14 |
| Nivel de servicio logrado en backtesting | Nivel de servicio objetivo: 0,90 / 0,95 / 0,98 (referencia: VN2, razón crítica ≈ 0,83) |
| Valor del inventario (precio real) | Costo de mantener inventario (solo para expresarlo en dinero anual) |

La comparación modelo vs. baseline se hace con los mismos supuestos para ambos, así que la conclusión relativa es robusta aunque el lead time real sea otro.

**Qué NO afirma el proyecto:** ahorros reales, optimización del inventario ni que las ventas sean demanda. El EOQ queda como extensión con costos supuestos: depende poco de la precisión del pronóstico, que es donde el modelo aporta valor.

---

## 3. Métricas

| Rol | Métrica | Por qué |
|---|---|---|
| Principal técnica | **WRMSSE** (nivel SKU, ponderada por ingreso de los últimos 28 días) | Métrica oficial de M5. Basada en error cuadrático (premia la media, que es lo que necesita el inventario) y escalada por la dificultad de cada serie |
| Principal de negocio | **WAPE pooled del acumulado de L días** + nivel de servicio logrado | Mide el insumo directo del stock de seguridad |
| Secundaria | WAPE pooled por nivel: SKU–día, departamento, tienda, total | Interpretable; muestra cómo cae el error al agregar |
| Obligatoria | **Sesgo** = (Σ pronóstico − Σ real) / Σ real | Un sesgo negativo genera quiebres aunque el WAPE sea bueno |
| Comparación | **Skill score** = 1 − error_modelo / error_baseline | Responde "¿cuánto mejora el modelo?" |

**No se usa el WAPE promedio por serie.** Con 91 % de series intermitentes, pronosticar todo ceros obtiene 1,000 y supera a todos los baselines (1,33–1,58). Una métrica que recomienda no tener inventario no sirve para esta pregunta. Además, se indefine en series sin ventas en la ventana.

`WAPE pooled = Σ|pronóstico − real| / Σ real`, sumando sobre todas las series y días del nivel evaluado.

---

## 4. Baselines

Resultados promedio de 3 cortes de 28 días (d_1858, d_1886 y d_1914 como inicio de cada ventana). Menor es mejor. Script: `eda/scripts/05_metrics_baselines.py`.

| Métrica | Todo ceros | Media 28 d | Media 30 d (memo) | Naive semanal | Año anterior (t−364) | Croston SBA |
|---|---|---|---|---|---|---|
| WAPE promedio por serie (descartada) | 1,000 | 1,331 | 1,341 | 1,437 | 1,579 | 1,384 |
| WAPE pooled SKU–día | 1,000 | **0,750** | 0,753 | 0,877 | 0,984 | 0,771 |
| WAPE pooled SKU, acumulado 7 días | 1,000 | **0,389** | 0,391 | 0,433 | 0,627 | 0,411 |
| WAPE pooled clase A, acumulado 7 días | 1,000 | **0,313** | 0,316 | 0,346 | 0,531 | 0,315 |
| WAPE departamento–día | 1,000 | 0,141 | 0,143 | **0,100** | 0,152 | 0,141 |
| WAPE total–día | 1,000 | 0,129 | 0,131 | **0,080** | 0,145 | 0,129 |
| WRMSSE (nivel SKU) | 1,405 | 0,875 | 0,876 | 1,116 | 1,222 | **0,871** |
| Sesgo | −100 % | −1,5 % | −0,3 % | −5,4 % | −14,4 % | −2,6 % |

Definiciones:

- **Media 28 días:** reemplaza la media de 30 días del memo. Resultados equivalentes (0,750 vs 0,753) y alineada con el horizonte.
- **Naive semanal:** repite la última semana observada.
- **Año anterior:** ŷ(t) = y(t − 364). El desfase de 364 días conserva el día de semana en el 100 % de los casos; la misma fecha calendario no lo conserva nunca. Los eventos de fecha móvil (19 de 30) quedan desalineados.
- **Croston SBA:** método para demanda intermitente, α = 0,1.

Lectura:

- No hay un baseline ganador único: la media gana a nivel SKU, el naive semanal en niveles agregados (captura el patrón de día de semana) y Croston en WRMSSE. La meta del modelo es superar a todos en WRMSSE y en el acumulado de L días.
- **El baseline del año anterior pierde en todos los niveles**, con sesgo de −14 %. El negocio crece ~4,7 % anual, entran productos nuevos (las series activas pasan de 15 mil a 30,5 mil entre 2011 y 2016) y algunas tiendas cambian de nivel (WI_1 ×1,86 en 2012). El ajuste por factor de crecimiento empeora a nivel serie (WAPE 1,026) y solo gana en el total agregado (0,065). Se reporta tal cual: se probó lo que sugirió Erick y se explica por qué pierde.

---

## 5. Tratamiento de la censura

M5 no trae inventario. El precio no sirve para detectar quiebres: se arrastra aunque no haya ventas y nunca desaparece tras el lanzamiento. Tampoco sirve como proxy de promociones: las semanas con caída de precio no venden más que las de control.

Los quiebres se aproximan con rachas de ceros anómalas en productos con precio vigente:

| Regla | Definición | Series afectadas | Días activos afectados |
|---|---|---|---|
| Conservadora | Tasa local ≥ 1 unidad/día y racha ≥ 14 días | 37,0 % | 4,2 % |
| Binomial negativa | Tasa de los 56 días previos, p < 0,001, racha ≥ 7 días | 89,5 % | 14,4 % |

Ventas posiblemente perdidas (**cota superior**): entre 8,8 % y 12,7 % de las unidades vendidas. Las rachas mezclan quiebres, descatalogaciones y caídas reales de demanda, y con M5 no se pueden separar. Como referencia externa, FreshRetailNet (quiebres etiquetados) reporta una subestimación de la demanda de ~7 % al ignorar la censura: el mismo orden de magnitud.

**Implementación:**

- Columnas previstas en Silver: `is_suspected_stockout_conservative` y `is_suspected_stockout_nb`. **Aún no implementadas** (al 4-oct-2026): las cifras de la tabla son del EDA, con un `k` no causal, y se recalcularán con ventana causal.
- Análisis de sensibilidad: métricas con esos días (a) incluidos, (b) excluidos de la evaluación y (c) imputados.
- Se declara como limitación: el nivel de servicio logrado en backtesting es optimista, porque se mide contra ventas y no contra demanda.

---

## 6. Decisión del dataset: M5

Se buscaron datasets con inventario o quiebres observados, ≥ 2 años diarios, unidades y precios reales, millones de filas y licencia usable. Se revisaron 13 candidatos. Detalle y fuentes: `reports/Datasets retail con inventario.md`.

| Candidato | Por qué no reemplaza a M5 |
|---|---|
| Rohlik v2 | Las ventas ya vienen corregidas por un método interno no publicado; valores alterados; ~4 M filas; licencia limitada a la competencia |
| FreshRetailNet-50K / LT | Quiebres etiquetados, pero ~90 días por serie, ventas normalizadas, sin precios, ids anónimos |
| VN2 | Lead time y costos reales, pero semanal y 599 series |
| Favorita, Iowa Liquor, Dominick's | Sin inventario |
| WWI, TPC-DS, datasets "inventory" de Kaggle | Sintéticos |

Fortalezas de M5 verificadas en el EDA:

- 0 nulos, 0 duplicados, jerarquía 100 % consistente.
- 5,3 años de historia; 98,7 % de las series tiene ≥ 1 año desde su primera venta; 43 cortes de 28 días con ≥ 2 años de historia previa.
- Variables explicativas con efecto medible: SNAP (+10 % a +30 % en FOODS según estado), eventos (−28 % a +26 %), precios y calendario conocidos para el horizonte.
- ~59 M filas en formato largo: justifica Spark sin ser inmanejable.

Complementos opcionales, no para el PSet 2: FreshRetailNet para validar la regla de censura, VN2 como referencia de parámetros de inventario.

---

## 7. Alcance del modelo

- Se pronostican todas las series, pero el análisis de negocio se reporta por **clase ABC por ingreso**: el 36,8 % de las series genera el 80 % del ingreso.
- **Clase A:** foco del modelo y del análisis de stock de seguridad. Series más densas: la censura se detecta mejor y hay más margen para superar a los baselines.
- **Clases B y C:** si ningún modelo supera a los baselines, se recomienda el baseline. Es un resultado válido ("en este segmento no vale la pena modelar").
- Horizonte: 28 días. Holdout final: d_1914–d_1941 (2016-04-25 a 2016-05-22), la última ventana con valores reales. Los días d_1942–d_1969 no tienen ventas publicadas.
- Backtesting con origen móvil en cortes de 28 días previos al holdout.

---

## 8. Decisiones para el PSet 2 que salen del EDA

**Ingesta**

- Ingerir `sales_train_evaluation.csv`, `sell_prices.csv` y `calendar.csv`. `sales_train_validation` es un prefijo exacto de evaluation (0 diferencias en 58 M de celdas); `sample_submission` está todo en ceros.
- Descarga con la API de Kaggle desde Kestra (`kaggle competitions download -c m5-forecasting-accuracy`), con el token en un secret.
- Dataset estático → simular cargas con un reloj semanal: la semana k carga d_(7k+1)..d_(7k+7). Backfill de las semanas 0–276 (d_1..d_1939); la 277 (d_1940–1941) estaba prevista para el cron del sábado 2026-10-03; el tick no disparó y se cargó ese día ejecutando el flow por la API. El 4-oct, al volver a guardar el flow, el trigger recuperó ese tick, recargó la semana sin duplicar y encadenó `transform` (dbt + Spark).
- Bronze guarda cada entrega tal como la publica la fuente (decisión revisada el 28-sep, tras el feedback de Erick): un simulador publica cada semana un CSV ancho (jerarquía + sus 7 columnas `d_N`) y Kestra lo copia a `BRONZE.SALES_RAW` **por nombre de columna** (`MATCH_BY_COLUMN_NAME` + schema evolution). El paso a formato largo se hace en dbt (`stg_sales`). Así, si la fuente reordena o agrega columnas, la ingesta no corrompe datos. La primera versión hacía el `UNPIVOT` en la ingesta leyendo columnas por posición.
- Llaves naturales para idempotencia: ventas en Bronze (item_id, store_id, week_idx) y en Silver (item_id, store_id, d); precios (store_id, item_id, wm_yr_wk).

**Calidad y limpieza (Silver)**

| Problema | Evidencia | Acción |
|---|---|---|
| Ceros antes del lanzamiento | 12,4 M días-serie (20,9 % de la matriz), sin precio | Marcar o filtrar desde la primera semana con precio |
| Navidad (tiendas cerradas) | 5 días con 11–20 unidades en total, frente a ~27–34 mil un día normal | Flag `is_christmas_closed` y excluir de entrenamiento y evaluación |
| Quiebres sospechosos | 4,2 %–14,4 % de días activos | Flags de la sección 5 |
| Cierres puntuales de tienda | WI_1 (2011-02-02), TX_2 (2015-03-24) | Flag de cierre |
| Picos extremos | 6,4 % de las series con días > 10× su mediana no nula | Marcar; no eliminar sin revisar |
| Eventos nulos | 91,8 % en `event_name_1` | Nulo estructural (día sin evento), no error |
| Precio semanal promedio | Centavos atípicos; 445 precios atípicos | Documentar; no es precio de lista |

**Star schema (Gold)**

- `fact_sales`: grain SKU–tienda–día.
- `dim_item` (item → dept → cat), `dim_store` (store → state), `dim_date`.
- `dim_date`: una fila por fecha (1.969, incluye el horizonte futuro); llave `date_key` = YYYYMMDD; índice secuencial de semana (el año fiscal 2013 tiene 53 semanas, así que `wm_yr_wk` no se puede restar); flags de evento, cierre de Navidad y horizonte de pronóstico; `date_ly_364`.
- SNAP en una tabla aparte fecha × estado (5.907 filas), no como columnas en `dim_date`.
- Precio unido por (item, store, `wm_yr_wk`): join muchos a uno. Test de unicidad después del join; unir sin `store_id` multiplica las filas por 10.

---

## 9. Limitaciones y preguntas abiertas

- **Respuesta de Erick** sobre si se aceptan cambios justificados al planteamiento del PSet 1.
- Sin confirmar si la política de reposición debe validarse contra inventario real (con M5 no es posible).
- La censura se estima con heurísticas no validables en M5.
- Lead time, nivel de servicio y costos son supuestos.
- Un solo holdout con valores reales (d_1914–d_1941).
- Datos de 2011–2016, solo de EE. UU.

---

## Referencias internas

- `eda/reports/01_sales_eval.md`: ventas, intermitencia, censura sin precios.
- `eda/reports/02_sell_prices.md`: precios, promociones, quiebres con precio vigente.
- `eda/reports/03_consistency_quality.md`: integridad, tamaños, estrategia de ingesta.
- `eda/reports/04_calendar.md`: eventos, SNAP, baseline año anterior, `dim_date`.
- `eda/reports/05_metrics_baselines.csv`: comparación de baselines y métricas.
- `reports/Datasets retail con inventario.md`: búsqueda de datasets alternativos.

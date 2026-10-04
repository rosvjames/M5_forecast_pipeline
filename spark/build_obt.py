"""OBT de ventas: fact_sales + dimensiones de Gold → OBT.OBT_SALES en Snowflake.

Grain: item × tienda × día con ventas observadas (el mismo de fact_sales).
Todas las dimensiones son N:1 respecto del fact, así que la OBT debe tener exactamente las mismas filas.
Si alguna validación falla, el job termina con error ANTES de escribir.
"""
import sys
import time

from pyspark.sql import SparkSession
from pyspark.sql import functions as F

from sf_conn import SNOWFLAKE_SOURCE, sf_options

GRAIN = ["item_id", "store_id", "date_key"]
TARGET_TABLE = "OBT_SALES"

spark = SparkSession.builder.appName("build_obt_sales").getOrCreate()
t0 = time.time()


def read_gold(table: str):
    df = spark.read.format(SNOWFLAKE_SOURCE).options(**sf_options("GOLD")).option("dbtable", table).load()
    # Snowflake devuelve los nombres en mayúsculas; en minúsculas quedan igual que en dbt.
    return df.toDF(*[c.lower() for c in df.columns])


fact = read_gold("FACT_SALES")
dim_date = read_gold("DIM_DATE").drop("is_forecast_horizon")  # siempre falso en filas con ventas
dim_item = read_gold("DIM_ITEM")
dim_store = read_gold("DIM_STORE").withColumnRenamed("state_id", "store_state_id")
dim_date_state = read_gold("DIM_DATE_STATE")

# Left joins: si a una fila le falta su dimensión, queda con nulos (y la validación lo detecta)
# en vez de desaparecer en silencio como en un inner join.
# Broadcast: las dimensiones son chicas (≤ 5.907 filas) y se copian a cada executor;
# así el fact de 59 M filas no se reparte por la red (no hay shuffle).
obt = (
    fact
    .join(F.broadcast(dim_date), "date_key", "left")
    .join(F.broadcast(dim_item), "item_id", "left")
    .join(F.broadcast(dim_store), "store_id", "left")
    .join(F.broadcast(dim_date_state), ["date_key", "state_id"], "left")
    .select(
        # Llaves y jerarquía
        "date_key", "date", "d", "d_num",
        "item_id", "dept_id", "cat_id",
        "store_id", "state_id", "store_state_id",
        # Objetivo y medidas
        "units", "sell_price", "revenue",
        # Calendario (conocido a futuro: sin fuga)
        "wm_yr_wk", "wm_fiscal_year", "wm_week_of_year", "week_seq",
        "weekday", "wday", "is_weekend", "day_of_month", "month", "quarter", "year",
        "event_name_1", "event_type_1", "event_name_2", "event_type_2", "is_event_day", "n_events",
        "is_christmas_closed", "date_ly_364", "date_key_ly_364",
        # SNAP del estado de la tienda en esa fecha
        "is_snap",
        # Flags de calidad (docs/calidad_datos.md): se marcan, no se borran
        "is_pre_launch", "is_store_closed", "is_sales_spike",
        "is_suspected_stockout_conservative", "is_suspected_stockout_nb",
        # Linaje
        "week_idx", "_loaded_at",
    )
)

# Sin persist(): cachear 59 M filas anchas agota la memoria del worker (4 GB, OutOfMemoryError en la
# primera corrida). Cada acción (validar, escribir) vuelve a leer de Snowflake: más lento, pero estable.

# ---------- Validaciones ----------
# Columnas que vienen de una dimensión y nunca pueden ser nulas tras el join.
# (event_*, sell_price, revenue y date_key_ly_364 sí pueden: son nulos legítimos.)
DIM_COLUMNS = ["date", "d", "wm_yr_wk", "week_seq", "is_christmas_closed",  # dim_date
               "dept_id", "cat_id",                                         # dim_item
               "store_state_id",                                            # dim_store
               "is_snap"]                                                   # dim_date_state

n_fact = fact.count()
stats = obt.agg(
    F.count("*").alias("n_obt"),
    *[F.sum(F.col(c).isNull().cast("int")).alias(f"null_{c}") for c in DIM_COLUMNS],
    F.sum((F.col("state_id") != F.col("store_state_id")).cast("int")).alias("state_mismatch"),
).first().asDict()
n_dup_keys = obt.groupBy(*GRAIN).count().filter("count > 1").count()

checks = {
    f"conteo fact = OBT ({n_fact:,} vs {stats['n_obt']:,})": n_fact == stats["n_obt"],
    f"grain único {GRAIN} ({n_dup_keys} llaves repetidas)": n_dup_keys == 0,
    **{f"sin nulos en {c} ({stats[f'null_{c}']})": stats[f"null_{c}"] == 0 for c in DIM_COLUMNS},
    f"estado del fact = estado de dim_store ({stats['state_mismatch']} distintos)": stats["state_mismatch"] == 0,
}
print("\n=== Validaciones de la OBT ===")
for name, ok in checks.items():
    print(f"[{'OK' if ok else 'FALLA'}] {name}")
if not all(checks.values()):
    print("La OBT no se escribe: hay validaciones con falla.")
    spark.stop()
    sys.exit(1)

# ---------- Escritura ----------
# overwrite con tabla de staging (default del conector): escribe en una tabla temporal y la intercambia
# al final; si falla a mitad, la OBT anterior queda intacta.
(obt.drop("store_state_id")  # igual a state_id (validado): no se duplica en la tabla final
    .write.format(SNOWFLAKE_SOURCE).options(**sf_options("OBT"))
    .option("dbtable", TARGET_TABLE).mode("overwrite").save())

# Verificación posterior: lo que quedó en Snowflake tiene las mismas filas que el fact.
n_written = (spark.read.format(SNOWFLAKE_SOURCE).options(**sf_options("OBT"))
             .option("query", f"select count(*) as n from {TARGET_TABLE}").load().first()[0])
print(f"[{'OK' if n_written == n_fact else 'FALLA'}] filas en OBT.{TARGET_TABLE}: {n_written:,}")
print(f"Tiempo total: {time.time() - t0:.0f} s")

spark.stop()
sys.exit(0 if n_written == n_fact else 1)

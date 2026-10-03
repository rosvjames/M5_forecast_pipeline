"""Prueba del conector: lee GOLD.DIM_STORE desde Snowflake."""
from pyspark.sql import SparkSession

from sf_conn import SNOWFLAKE_SOURCE, sf_options

spark = SparkSession.builder.appName("test_snowflake_connection").getOrCreate()
df = spark.read.format(SNOWFLAKE_SOURCE).options(**sf_options("GOLD")).option("dbtable", "DIM_STORE").load()
df.show()
print(f"filas: {df.count()}")
spark.stop()

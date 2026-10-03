# Imagen oficial de Spark + conector Spark–Snowflake.
# Los jars se copian a /opt/spark/jars (classpath del driver y de los executors), así no hace falta
# --packages: el usuario spark no tiene HOME (/nonexistent) e Ivy no podría descargar al ejecutar.
FROM apache/spark:4.1.3-scala2.13-java17-python3-ubuntu

ARG MAVEN=https://repo1.maven.org/maven2
# Conector para Spark 4.1 / Scala 2.13 y sus dependencias de compilación (pom 3.2.2-spark_4.1).
# parquet-avro va en 1.16.0, la misma versión de parquet que trae Spark 4.1.3.
ADD --chmod=644 ${MAVEN}/net/snowflake/spark-snowflake_2.13/3.2.2-spark_4.1/spark-snowflake_2.13-3.2.2-spark_4.1.jar /opt/spark/jars/
ADD --chmod=644 ${MAVEN}/net/snowflake/snowflake-jdbc/4.0.2/snowflake-jdbc-4.0.2.jar /opt/spark/jars/
ADD --chmod=644 ${MAVEN}/org/apache/parquet/parquet-avro/1.16.0/parquet-avro-1.16.0.jar /opt/spark/jars/

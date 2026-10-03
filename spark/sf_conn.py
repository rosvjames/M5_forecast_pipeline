"""Opciones del conector Spark–Snowflake, tomadas de las variables de entorno del contenedor."""
import os

SNOWFLAKE_SOURCE = "net.snowflake.spark.snowflake"
KEY_PATH = "/secrets/rsa_key.p8"  # montada en docker-compose (spark-master)


def _private_key() -> str:
    # El conector recibe la llave PKCS8 sin las líneas BEGIN/END ni saltos de línea.
    with open(KEY_PATH) as f:
        return "".join(line.strip() for line in f if "-----" not in line)


def sf_options(schema: str) -> dict:
    return {
        "sfURL": f"{os.environ['SNOWFLAKE_ACCOUNT']}.snowflakecomputing.com",
        "sfUser": os.environ["SNOWFLAKE_USER"],
        "sfRole": os.environ["SNOWFLAKE_ROLE"],
        "sfWarehouse": os.environ["SNOWFLAKE_WAREHOUSE"],
        "sfDatabase": os.environ["SNOWFLAKE_DATABASE"],
        "sfSchema": schema,
        "pem_private_key": _private_key(),
        # Sin pushdown: si no, el conector traduce los joins a SQL y los ejecuta Snowflake, no Spark.
        "autopushdown": "off",
    }

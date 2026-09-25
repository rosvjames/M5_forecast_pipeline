-- Setup de Snowflake para el pipeline M5.
-- Idempotente: se puede ejecutar varias veces sin errores.

-- ============================================================
-- 1. Identidades (USERADMIN: crea y administra roles y usuarios)
-- ============================================================
USE ROLE USERADMIN;

CREATE ROLE IF NOT EXISTS M5_PIPELINE;
-- Jerarquía: SYSADMIN hereda M5_PIPELINE y puede ver lo que crea el pipeline
GRANT ROLE M5_PIPELINE TO ROLE SYSADMIN;

-- Usuario de servicio: sin contraseña, solo key-pair
CREATE USER IF NOT EXISTS M5_PIPELINE_USER
    TYPE = SERVICE
    DEFAULT_ROLE = M5_PIPELINE
    DEFAULT_WAREHOUSE = M5_WAREHOUSE
    DEFAULT_NAMESPACE = M5.BRONZE;

GRANT ROLE M5_PIPELINE TO USER M5_PIPELINE_USER;

-- ============================================================
-- 2. Objetos (SYSADMIN: dueño de warehouse, base y esquemas)
-- ============================================================
USE ROLE SYSADMIN;

-- Warehouse XS con auto-suspend de 60 s para cuidar créditos
CREATE WAREHOUSE IF NOT EXISTS M5_WAREHOUSE
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

-- Base y capas de la arquitectura medallion
CREATE DATABASE IF NOT EXISTS M5;
CREATE SCHEMA IF NOT EXISTS M5.BRONZE;
CREATE SCHEMA IF NOT EXISTS M5.SILVER;
CREATE SCHEMA IF NOT EXISTS M5.GOLD;
CREATE SCHEMA IF NOT EXISTS M5.OBT;

-- ============================================================
-- 3. Permisos del pipeline (mínimo privilegio por capa)
-- ============================================================
GRANT USAGE ON WAREHOUSE M5_WAREHOUSE TO ROLE M5_PIPELINE;
GRANT USAGE ON DATABASE M5 TO ROLE M5_PIPELINE;

-- Bronze (Kestra): tablas crudas + stage y file format para los CSV de Kaggle
GRANT USAGE, CREATE TABLE, CREATE STAGE, CREATE FILE FORMAT ON SCHEMA M5.BRONZE TO ROLE M5_PIPELINE;

-- Silver y Gold (dbt): tablas y vistas
GRANT USAGE, CREATE TABLE, CREATE VIEW ON SCHEMA M5.SILVER TO ROLE M5_PIPELINE;
GRANT USAGE, CREATE TABLE, CREATE VIEW ON SCHEMA M5.GOLD   TO ROLE M5_PIPELINE;

-- OBT (Spark): tablas + stage temporal que usa el conector Spark-Snowflake
GRANT USAGE, CREATE TABLE, CREATE STAGE ON SCHEMA M5.OBT TO ROLE M5_PIPELINE;

-- ============================================================
-- 4. Llave pública (paso manual, propio de cada entorno)
-- ============================================================
-- Generar el par de llaves fuera del repo (ver README) y ejecutar:
-- USE ROLE USERADMIN;
-- ALTER USER M5_PIPELINE_USER SET RSA_PUBLIC_KEY = '<contenido de rsa_key.pub sin BEGIN/END>';

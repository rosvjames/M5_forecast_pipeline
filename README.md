# M5 Forecast Pipeline — PSet 2

Pipeline ELT reproducible para el dataset **M5 Forecasting (Walmart, Kaggle)**, construido con Kestra, Snowflake, dbt y Spark.

```
Kaggle → Kestra → BRONZE → dbt → SILVER → dbt → GOLD → Spark → OBT
                  └──────────────── Snowflake (base M5) ───────────┘
```

- **Kestra** orquesta la ingesta desde la API de Kaggle hacia la capa Bronze.
- **dbt** limpia (Silver) y modela el star schema (Gold).
- **Spark** construye la One Big Table (OBT) a partir de Gold y la escribe de vuelta en Snowflake.

El enfoque del proyecto y las decisiones de diseño están en [`docs/enfoque_proyecto.md`](docs/enfoque_proyecto.md). El avance por fases está en [`docs/roadmap_pset2.md`](docs/roadmap_pset2.md).

> **Estado actual:** Fase 0 (infraestructura) completa. Kestra, Spark y dbt corren en Docker y Kestra y dbt ya se conectan a Snowflake. La ingesta y las transformaciones están en desarrollo.

---

## Stack y versiones

Todas las imágenes tienen versión fija para que el entorno sea reproducible.

| Componente | Imagen / versión | Rol |
|---|---|---|
| Kestra | `kestra/kestra:v1.3.40` | Orquestador (UI + scheduler + worker) |
| PostgreSQL | `postgres:16.15` | Backend de Kestra (flows, ejecuciones, logs) |
| Spark | `apache/spark:4.1.3-scala2.13-java17-python3-ubuntu` | Cluster standalone (1 master + 1 worker) |
| dbt Core | `ghcr.io/dbt-labs/dbt-snowflake:1.9.0` | Transformaciones Silver y Gold |
| Snowflake | Cuenta trial (Enterprise) | Data warehouse: esquemas `BRONZE`, `SILVER`, `GOLD`, `OBT` |

## Estructura del repositorio

```
pset_2/
├── docker-compose.yml   # Kestra + Postgres, Spark (master/worker) y dbt
├── .env.example         # Plantilla de variables de entorno (copiar a .env)
├── kestra/              # Flows de Kestra (se sincronizan solos con la UI)
├── dbt/                 # Proyecto dbt (profiles.yml lee todo de variables de entorno)
├── spark/               # Scripts de PySpark (montados en /opt/spark-apps)
├── snowflake/setup.sql  # Crea warehouse, base, esquemas, rol y usuario de servicio
└── docs/                # Enfoque del proyecto y roadmap
```

---

## Requisitos previos

- **Docker** con Docker Compose v2 (Docker Desktop u OrbStack). Asigna al menos **8 GB de RAM** a Docker.
- **Git** y **OpenSSL** (vienen con macOS y la mayoría de distribuciones Linux).
- Una cuenta de **Snowflake** con acceso a los roles `SYSADMIN` y `USERADMIN`. Un trial gratuito sirve.
- Una cuenta de **Kaggle**.

## Puesta en marcha

### 1. Clonar el repositorio

```bash
git clone https://github.com/rosvjames/M5_forecast_pipeline.git
cd M5_forecast_pipeline
cp .env.example .env
```

Todos los valores que se configuran en los pasos siguientes van en `.env`. Ese archivo está en `.gitignore`: **nunca lo subas al repositorio.**

### 2. Snowflake

**2.1 Crear el par de llaves.** El pipeline se autentica con key-pair, sin contraseña. Genera las llaves **fuera del repositorio**:

```bash
mkdir -p ~/.snowflake
openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out ~/.snowflake/rsa_key.p8 -nocrypt
openssl rsa -in ~/.snowflake/rsa_key.p8 -pubout -out ~/.snowflake/rsa_key.pub
chmod 600 ~/.snowflake/rsa_key.p8
```

**2.2 Crear los objetos.** En Snowflake, abre una SQL Worksheet, pega el contenido de [`snowflake/setup.sql`](snowflake/setup.sql) y ejecútalo completo con **Run All** (`Cmd/Ctrl + Shift + Enter`). El script es idempotente: se puede volver a ejecutar sin errores. Crea:

- el warehouse `M5_WAREHOUSE` (XS, auto-suspend de 60 s);
- la base `M5` con los esquemas `BRONZE`, `SILVER`, `GOLD` y `OBT`;
- el rol `M5_PIPELINE`, con permisos mínimos por capa;
- el usuario de servicio `M5_PIPELINE_USER` (`TYPE = SERVICE`, sin contraseña).

**2.3 Registrar la llave pública.** Copia la llave en una sola línea y sin encabezados:

```bash
grep -v "PUBLIC KEY" ~/.snowflake/rsa_key.pub | tr -d '\n' | pbcopy   # macOS; en Linux usa xclip o cópiala a mano
```

En la worksheet, ejecuta:

```sql
USE ROLE USERADMIN;
ALTER USER M5_PIPELINE_USER SET RSA_PUBLIC_KEY = '<pega aquí la llave>';
```

**2.4 Completar `.env`:**

| Variable | Valor |
|---|---|
| `SNOWFLAKE_ACCOUNT` | Account identifier (`ORGNAME-ACCOUNTNAME`). Lo encuentras en el menú de tu usuario → *Connect a tool to Snowflake*. |
| `SNOWFLAKE_USER`, `SNOWFLAKE_ROLE`, `SNOWFLAKE_WAREHOUSE`, `SNOWFLAKE_DATABASE` | Ya vienen con los nombres que crea `setup.sql`. |
| `SNOWFLAKE_PRIVATE_KEY_PATH` | Ruta **absoluta** a `rsa_key.p8`, por ejemplo `/Users/<tu_usuario>/.snowflake/rsa_key.p8`. La usa dbt. |
| `SECRET_SNOWFLAKE_PRIVATE_KEY` | La llave privada en base64. La usa Kestra. Genérala con el comando de abajo. |

```bash
base64 -i ~/.snowflake/rsa_key.p8 | tr -d '\n'     # macOS
base64 -w0 ~/.snowflake/rsa_key.p8                 # Linux
```

### 3. Kaggle

1. En la competencia [M5 Forecasting - Accuracy](https://www.kaggle.com/competitions/m5-forecasting-accuracy), pestaña **Data**, **acepta las reglas**. Sin este paso la API responde `403 Forbidden`.
2. En Kaggle → **Settings → API → Create New Token**, genera un API token.
3. Codifícalo en base64 sin que quede en el historial de la terminal. Ejecuta el comando, pega el token (no se ve en pantalla) y presiona Enter:

   ```bash
   read -rs T && printf %s "$T" | base64; unset T
   ```

4. Pon el resultado en `SECRET_KAGGLE_API_TOKEN` en `.env`.

### 4. Kestra y Postgres

Completa en `.env`:

- `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`: los valores que quieras. Postgres se inicializa con ellos la primera vez.
- `KESTRA_USER`: un email válido. `KESTRA_PASSWORD`: al menos 8 caracteres, con una mayúscula y un número. Son las credenciales de la UI de Kestra.

> **Sobre los secrets de Kestra:** Kestra (versión open source) lee como secrets las variables de entorno con prefijo `SECRET_`, y su valor **debe estar en base64**. En un flow se usan con `{{ secret('KAGGLE_API_TOKEN') }}`, sin el prefijo.

### 5. Levantar la infraestructura

```bash
docker compose up -d
```

El **primer arranque de Kestra tarda unos minutos**, porque migra la base de datos y carga los plugins. Para seguir el avance: `docker compose logs -f kestra`.

| Servicio | URL |
|---|---|
| Kestra UI | http://localhost:8080 (credenciales `KESTRA_USER` / `KESTRA_PASSWORD`) |
| Spark Master UI | http://localhost:8090 |
| Spark Worker UI | http://localhost:8091 |

dbt no aparece en esta tabla porque no queda corriendo: se ejecuta a demanda (ver más abajo).

### 6. Verificar

1. **Kestra → Snowflake:** en la UI, en *Flows*, ejecuta `m5.pipeline.snowflake_check`. En los outputs de la tarea `whoami` deben aparecer `M5_PIPELINE_USER`, `M5_PIPELINE` y `M5_WAREHOUSE`.
2. **dbt → Snowflake:**
   ```bash
   docker compose run --rm dbt debug
   ```
   Debe terminar en `All checks passed!`.
3. **Cluster de Spark:** en http://localhost:8090 el worker debe aparecer como **ALIVE**. Para una prueba completa:
   ```bash
   docker compose exec spark-master /opt/spark/bin/spark-submit \
     --master spark://spark-master:7077 \
     /opt/spark/examples/src/main/python/pi.py 10
   ```
   Debe imprimir `Pi is roughly 3.14...`.

---

## Uso diario

### Kestra

- Los flows viven en `kestra/` y **se sincronizan solos** con Kestra: al guardar un archivo, el cambio aparece en la UI.
- **El nombre del archivo es obligatorio** y sigue el formato `<tenant>_<namespace>_<id>.yml`. En la versión open source el tenant es siempre `main`. Ejemplo: `main_m5.pipeline_snowflake_check.yml`. Con otro nombre, Kestra ignora el flow y deja un error de `tenantId` en los logs.
- Edita los flows en el repositorio, no en la UI, para que queden versionados.

### dbt

dbt corre en un contenedor de un solo uso (profile `tools` de Compose):

```bash
docker compose run --rm dbt debug      # probar la conexión
docker compose run --rm dbt run        # ejecutar modelos
docker compose run --rm dbt test       # ejecutar tests
docker compose run --rm dbt build      # run + test en orden de dependencias
```

`profiles.yml` está versionado, pero no contiene credenciales: todo sale de `.env` con `env_var()`.

### Spark

Los scripts van en `spark/` y dentro de los contenedores quedan en `/opt/spark-apps`:

```bash
docker compose exec spark-master /opt/spark/bin/spark-submit \
  --master spark://spark-master:7077 \
  /opt/spark-apps/<script>.py
```

### Apagar

```bash
docker compose down        # detiene los contenedores y conserva los datos (volúmenes)
docker compose down -v     # además BORRA los volúmenes: historial de Kestra y archivos internos
```

---

## Problemas frecuentes

| Síntoma | Causa y solución |
|---|---|
| Un flow no aparece en Kestra y los logs dicen `tenantId: must match ...` | El nombre del archivo no sigue el formato `main_<namespace>_<id>.yml`. |
| La UI de Kestra no abre justo después de `up` | El primer arranque es lento. Espera y revisa `docker compose logs -f kestra`. |
| Kaggle responde `403 Forbidden` | No se aceptaron las reglas de la competencia M5 con esa cuenta. |
| `dbt debug`: `profiles.yml file [ERROR not found]` | Revisa que exista `dbt/profiles.yml`. El contenedor lo busca en `DBT_PROFILES_DIR=/usr/app/dbt`. |
| `dbt debug` falla con un error de autenticación JWT | La llave pública registrada en Snowflake no corresponde a la privada. Compara el `RSA_PUBLIC_KEY_FP` de `DESC USER M5_PIPELINE_USER;` con: `openssl rsa -pubin -in ~/.snowflake/rsa_key.pub -outform DER \| openssl dgst -sha256 -binary \| openssl enc -base64` |
| Error de volumen en el servicio `dbt` al arrancar | `SNOWFLAKE_PRIVATE_KEY_PATH` está vacío o no es una ruta absoluta. |
| dbt va lento en Mac con chip Apple | La imagen de dbt es solo `amd64` y corre emulada (`platform: linux/amd64`). Es esperado. |

## Seguridad

- **Nunca** se versionan `.env`, llaves (`*.p8`, `*.pem`) ni `kaggle.json`: están en `.gitignore`.
- El pipeline usa un **usuario de servicio** con un rol de **mínimo privilegio**, nunca `ACCOUNTADMIN`.
- Los datos de M5 **no están en el repositorio**: los descarga Kestra desde la API de Kaggle. Las reglas de la competencia no permiten redistribuirlos, y los archivos superan el límite de GitHub.

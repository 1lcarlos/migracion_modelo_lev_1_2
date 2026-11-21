# Migración gestor catastral → LADM-COL Levantamiento Catastral v1.2

Migra los datos de los esquemas del gestor catastral (`cunXXXXX`: `gc_*`, `extavaluo`, `zh*`, `cc_*`)
al modelo **LADM-COL Lev Cat v1.2** y genera un **XTF INTERLIS validado** por municipio y vigencia.

- Documentación: [`docs/README.md`](docs/README.md). Trabajo en curso y cómo retomarlo:
  [`docs/05_lote_25_municipios.md`](docs/05_lote_25_municipios.md) §7.
- Orquestador vigente (lote de 25 municipios desde las BD de corte): `python scripts/lote.py <mun>...`
  con `config/lote_25.csv`, la plantilla `etl/plantilla/` y validación con ilivalidator.
- Flujo heredado (backup entregado + mezcla con el XTF del operador): `bash scripts/migrar.sh <municipio> [etapa...]`
  con `config/municipios/<municipio>.env` (ver `docs/02_runbook_migracion.md`).
- Requisitos locales: PostgreSQL 16 + PostGIS, Java 8, Python 3.10, ili2pg 5.5.1 e ilivalidator 1.15.0
  (rutas en `.env`, plantilla en `.env.example`).

No se versionan: `.env`, backups (`*.sql` en la raíz), dumps de `insumos/`, XTF generados o de terceros,
listados por predio con datos personales, logs ni binarios de herramientas (ver `.gitignore`). Sí se versionan
los manifiestos, `.sha256` y el resumen del lote (`salida/lote_25/`).

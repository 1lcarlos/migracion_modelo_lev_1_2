# Runbook — Migrar un municipio nuevo

Proceso reproducible con la plantilla parametrizada (`etl/plantilla/`) y el orquestador
`scripts/migrar.sh` (Git Bash). Probado con Vergara (2026-10-02, ~10 min en total, de los
cuales ~6 son la exportación/validación de ili2pg). Ante errores de validación consultar
`03_decisiones_y_lecciones.md` antes de improvisar soluciones.

## 0. Requisitos

- `.env` en la raíz con `PGPASSWORD` y rutas (copiar de `.env.example`).
- Backup pg_dump (texto plano) del municipio en la raíz del proyecto.
- Existe la BD indicada en `BD_PLANTILLA_LEV12` (de ahí se clona `lev_cat_12`).

## 1. Crear la configuración del municipio

`config/municipios/<mun>.env`:

```bash
MUN=vergara                 # nombre corto (prefijo de OID, dataset, nombres de archivo)
ESQ=cun25862                # esquema origen en el backup (ver "CREATE SCHEMA" al inicio)
BD=vergara_lev12            # BD destino (se crea)
PREFIJO=VERGARA_            # prefijo de id_operacion
VIGENCIA=2023               # año de extavaluo.vigencia a migrar
BACKUP=vergara_produccion_v2023_202610021615.sql
RAZON_MUNICIPIO=            # opcional: razón social del municipio con documento vacío
NIT_MUNICIPIO=              # opcional: NIT a asignar en ese caso
```

## 2. Ejecutar por etapas (recomendado)

```bash
bash scripts/migrar.sh <mun> preparar   # crea BD, extensiones, restaura backup, clona lev_cat_12
bash scripts/migrar.sh <mun> dominios   # códigos origen sin equivalente en v1.2
bash scripts/migrar.sh <mun> etl        # 01_migracion (transacción única, re-ejecutable)
bash scripts/migrar.sh <mun> complemento # 04: solo si config define XTF_COMPLEMENTO (re-ejecutar tras cada etl)
bash scripts/migrar.sh <mun> fix        # 02_fix_validacion (verificación final debe dar 0 en todo)
bash scripts/migrar.sh <mun> exportar   # ili2pg export + validación; genera .sha256 si es válido
bash scripts/migrar.sh <mun> verificar  # cuadre de avalúos y conteos origen vs destino
```

`bash scripts/migrar.sh <mun>` (o `todo`) corre todas las etapas seguidas; úsese solo cuando
los dominios del municipio ya fueron revisados.

### Qué revisar en cada etapa

- **preparar**: aborta si la BD ya existe (borrarla a mano para recrear). Tolera el error
  `schema "public" already exists` del backup; cualquier otro error detiene el proceso
  (ver `logs/restore_<mun>.log`).
- **dominios**: `gc_predio.tipo` (`Privado`, `Publico.*`) es falso positivo (el ETL antepone
  `Predio.`); `tb_valortipologia.tipo_anexo` es esperado. Cualquier otro código: decidir la
  homologación ANTES de migrar, implementarla en la plantilla y documentarla en `03_...`.
- **etl**: aborta si alguna tabla origen tiene `id >= 100.000.000` (estrategia de offsets).
  Si el origen no tiene `tb_valortipologia`, avisa y deja `av_tipologiaconstruccion` vacía.
- **complemento**: toma de un XTF previo del municipio lo que el backup no trae (contacto de
  visita, novedades de números prediales, observaciones y avalúo de unidades). Revisar la tabla
  resumen: `aplicados` < `ref` solo debe corresponder a predios que ya no existen en el backup.
- **fix**: los `NOTICE: Self-intersection` son informativos (polígonos que se reparan);
  lo que importa es la tabla final, toda en 0.
- **exportar**: `XTF VÁLIDO` solo si el log termina en `...export done`. Si sale
  `XTF INVÁLIDO`, el script resume los errores; corregir en la plantilla (preventivo y global,
  no registro a registro), re-ejecutar `etl fix exportar`.
- **verificar**: `avaluo_origen` = `avaluo_destino` al peso; `predios_migrados` =
  `predios_con_avaluo_vigencia`; `avaluos_duplicados_vigencia` = 0.

## 3. Cierre

1. Registrar el municipio en la tabla de `01_contexto_general.md`.
2. Registrar decisiones/homologaciones nuevas en `03_decisiones_y_lecciones.md`.
3. Si existe un XTF previo del municipio, compararlo:
   `python scripts/comparar_xtf.py <xtf_previo> salida/<xtf> --salida comparacion/informe_<mun>.json`.
4. Entregar el XTF junto con su `.sha256`.

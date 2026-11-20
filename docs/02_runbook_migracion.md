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
ZH_ULTIMA_VIGENCIA=         # opcional (si): zonas homogéneas de la última vigencia <= VIGENCIA por tabla
                            # (cuando el backup no trae ZH de la vigencia exacta; Nemocón: rurales 2021)
```

> El chequeo de `dominios` solo revisa las ZH de `VIGENCIA`; con `ZH_ULTIMA_VIGENCIA=si` correrlo también
> con la vigencia de las ZH (`psql -v esq=<esq> -v vigencia=<año_zh> -f etl/plantilla/00_check_dominios.sql`).

## 2. Ejecutar por etapas (recomendado)

```bash
bash scripts/migrar.sh <mun> preparar   # crea BD, extensiones, restaura backup, clona lev_cat_12
bash scripts/migrar.sh <mun> auxiliar   # opcional: BACKUP_AUX -> esquema ESQ_AUX (vía BD temporal)
bash scripts/migrar.sh <mun> dominios   # códigos origen sin equivalente en v1.2
bash scripts/migrar.sh <mun> etl        # 01_migracion (transacción única, re-ejecutable)
bash scripts/migrar.sh <mun> complemento # 04: solo si config define XTF_COMPLEMENTO (re-ejecutar tras cada etl)
bash scripts/migrar.sh <mun> cancelados # 05: solo si INCLUIR_CANCELADOS=si (re-ejecutar tras cada etl)
bash scripts/migrar.sh <mun> operador   # 06: solo si COMPLEMENTO_OPERADOR=si (re-ejecutar tras cada etl y tras cancelados)
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
- **auxiliar**: solo si la config define `BACKUP_AUX` y `ESQ_AUX`. Carga el esquema del segundo
  backup con otro nombre; hoy se usa para leer tipologías (`ESQ_TIPOLOGIA=<ESQ_AUX>`) cuando el
  backup principal no trae `tb_valortipologia` (Sutatausa).
- **complemento**: toma de un XTF previo del municipio lo que el backup no trae (contacto de
  visita, novedades de números prediales, observaciones y avalúo de unidades; el avalúo se omite con
  `COMPLEMENTO_AVALUO_UNIDADES=no`). Revisar la tabla
  resumen: `aplicados` < `ref` solo debe corresponder a predios que ya no existen en el backup.
- **cancelados**: extrae del `XTF_COMPLEMENTO` los predios con novedad `Cancelacion` que no están en la
  migración y todo lo que depende de ellos; los importa con ili2pg (valida) en `ref_canc`, un clon vacío
  de `lev_cat_12`, y `05_cancelados_xtf.sql` los copia reutilizando interesados ya existentes
  (mismo tipo y documento, comparado sin espacios ni U+00A0). Después corrige la calidad de lo copiado:
  direcciones repetidas, una dirección principal por predio, fuentes repetidas en un derecho y tipo de
  agrupación según sus miembros. En el resumen, `predios_sin_1_direccion_principal` debe dar 0.
- **operador**: solo si la config define `XTF_COMPLEMENTO` y `COMPLEMENTO_OPERADOR=si`. `filtrar_xtf_ref.py`
  deja del XTF los tópicos Levantamiento_Catastral, Avaluos y LimitesOperativosCatastro (descarta los de
  insumos); se importan completos con ili2pg (sin validar: es insumo) en `ref_ope`, clon vacío de
  `lev_cat_12` con t_id >= 8·10⁹, y `06_complemento_operador.sql` copia lo que el backup no trae:
  linderos de terrenos cuya geometría coincide con la del backup (mismo NPN, diferencia simétrica
  < 0,1 m², par 1 a 1) con sus puntos y `col_masCcl`/`col_menosCcl` reapuntados, puntos de levantamiento,
  fuentes espaciales (`col_baunitFuente` reapuntado por NPN), ZHF urbanas y `AV_TipologiaConstruccion`
  (estas dos solo si el destino está vacío; las ZHG no se tocan). Los terrenos no cruzados quedan en
  `ref_ope.rep_terrenos_no_cruzados`. La etapa `cancelados` borra t_id >= 6·10⁹ (incluye lo de esta
  etapa): si se re-ejecuta, correr `operador` después.
- **fix**: los `NOTICE: Self-intersection` son informativos (polígonos que se reparan);
  lo que importa es la tabla final, toda en 0.
- **exportar**: `XTF VÁLIDO` solo si el log termina en `...export done`. Si sale
  `XTF INVÁLIDO`, el script resume los errores; corregir en la plantilla (preventivo y global,
  no registro a registro), re-ejecutar `etl fix exportar`.
- **verificar**: `avaluo_origen` = `avaluo_destino` al peso; `predios_migrados` =
  `predios_con_avaluo_vigencia`; `avaluos_duplicados_vigencia` = 0; `zh_modificadas_vs_backup` = 0
  (zonas homogéneas idénticas al backup en valores y geometría redondeada a 1 mm);
  `copropiedad_origen` = `copropiedad_destino` y `copropiedad_matrices_coef_distinto_1` = 0.

## 3. Cierre

1. Registrar el municipio en la tabla de `01_contexto_general.md`.
2. Registrar decisiones/homologaciones nuevas en `03_decisiones_y_lecciones.md`.
3. Si existe un XTF previo del municipio, compararlo:
   `python scripts/comparar_xtf.py <xtf_previo> salida/<xtf> --salida comparacion/informe_<mun>.json`.
4. Entregar el XTF junto con su `.sha256`.

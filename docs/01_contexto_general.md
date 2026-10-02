# Contexto general del proyecto

> Documento de arranque para retomar el trabajo. Última actualización: 2026-08-28.

## Objetivo

Migrar los datos catastrales de municipios gestionados en el "modelo gestor" (esquemas
PostgreSQL `cunXXXXX` con tablas `gc_*`, `extavaluo`, `zhf_*`, `cc_*`, etc.) al modelo
**LADM-COL Levantamiento Catastral v1.2** y generar un **XTF INTERLIS validado** por ili2pg.
Solo se migran los predios con avalúo de la **vigencia 2024** (filtro por
`extavaluo.vigencia`, campo tipo fecha: `date_part('year', vigencia) = 2024`).

## Municipios procesados

| Municipio | Código DANE | Esquema origen | BD PostgreSQL | Prefijo id_operacion | Dataset | XTF |
|---|---|---|---|---|---|---|
| Tibirita | 25807 | `cun25807` | `tibirita_lev12` | `TIB_` | `tibirita_2024` | `salida/tibirita_lev_cat_v1_2_vigencia2024.xtf` ✅ válido |
| Tibacuy | 25805 | `cun25805` | `tibacuy_lev12` | `TIBACUY_` | `tibacuy_2024` | `salida/tibacuy_lev_cat_v1_2_vigencia2024.xtf` ✅ válido |

Cada BD contiene dos esquemas: el origen (`cunXXXXX`, restaurado del backup pg_dump) y el
destino (`lev_cat_12`, estructura generada por ili2pg 5.5.1 a partir de los modelos .ili).

## Entorno y herramientas

- **PostgreSQL 16.9** en `localhost:5432`, usuario `postgres` (contraseña local del equipo;
  exportar `PGPASSWORD` antes de usar `psql`). PostGIS 3.4.2. SRS de trabajo: **9377** (CTM12).
- **psql**: `C:\Program Files\PostgreSQL\16\bin\psql`
- **Java 8** (requerido por ili2pg): en el PATH.
- **ili2pg 5.5.1**: `C:\ladm_col\desarrollos\creacion_modelos_fisicos\windows_version\ili2pg\ili2pg-5.5.1\ili2pg-5.5.1.jar`
- **Modelos .ili**: carpeta `LADM_COL_Lev_Cat_v1_2_docs\` (Modelo_Aplicacion_LADMCOL_Lev_Cat_V1_2,
  Submodelo_Avaluos_V1_2, Submodelo_Cartografia_Catastral_V1_2, Submodelo_Insumos_V1_2,
  LADM_COL_V3_1, ISO19107_PLANAS_V3_0). Se usa como `--modeldir`.

## Estructura del proyecto

```
migracion_modelo_lev_1_2/
├── LADM_COL_Lev_Cat_v1_2_docs/   # Modelos .ili (repositorio local para ili2pg)
├── etl/
│   ├── 00_check_dominios.sql             # Chequeo dominios Tibirita
│   ├── 01_migracion.sql                  # ETL Tibirita
│   ├── 02_fix_validacion.sql             # Fix post-validación Tibirita (versión original)
│   ├── 03_fix_revalidacion_tibirita.sql  # Fix definitivo Tibirita (geometrías + agrupaciones)
│   ├── 00_check_dominios_tibacuy.sql     # Chequeo dominios Tibacuy
│   ├── 01_migracion_tibacuy.sql          # ETL Tibacuy
│   └── 02_fix_validacion_tibacuy.sql     # Fix post-validación Tibacuy (pipeline definitivo)
├── salida/                       # XTF generados
├── logs/                         # Logs de schemaimport y export de ili2pg
├── docs/                         # Esta documentación
└── *.sql                         # Backups pg_dump de los municipios
```

## Convenciones clave del ETL

- **t_id** en destino = `offset_millón + id_origen` (predio 1M, dirección 2M, terreno 3M,
  construcción 4M, unidad 5M, características 6M, tipología 7M, cal. no conv. 8M,
  interesado 9M, agrupación 10M, derecho 11M, fuente adm. 12M, datos adicionales 13M,
  ofertas 14M, uebaunit 15M, rrrfuente 16M, miembros 17M, zonas 18–21M, av_tipología 22M,
  cartografía 23–33M). Requiere que los id de origen sean < 1.000.000.
  Al final se ajusta `setval('lev_cat_12.t_ili2db_seq', 40000000, false)`.
- **t_ili_tid** (OID UUID): `md5('<municipio>_<tabla>' || id)::uuid` — el prefijo del
  municipio evita colisiones de OID si dos XTF se cargan en el mismo sistema destino.
  (Tibirita se generó sin prefijo; Tibacuy con prefijo `tibacuy_`.)
- **3 baskets**: (1) Levantamiento_Catastral, (2) Avaluos, (3) LimitesOperativosCatastro.
- El esquema `lev_cat_12` de un municipio nuevo se **clona** desde una BD existente
  (`pg_dump --schema=lev_cat_12`) para garantizar estructura y t_id de catálogos idénticos;
  el ETL trunca los datos y reconstruye.

## Comandos de referencia

```bash
# Exportar XTF (validación incluida; ...export done = válido)
java -jar <ruta>/ili2pg-5.5.1.jar --export --exportTid \
  --dbhost localhost --dbport 5432 --dbdatabase <bd> --dbusr postgres --dbpwd <pwd> \
  --dbschema lev_cat_12 --defaultSrsCode 9377 \
  --models 'Modelo_Aplicacion_LADMCOL_Lev_Cat_V1_2;Submodelo_Avaluos_V1_2;Submodelo_Cartografia_Catastral_V1_2' \
  --modeldir <ruta>/LADM_COL_Lev_Cat_v1_2_docs \
  --log logs/export_<municipio>.log salida/<municipio>_lev_cat_v1_2_vigencia2024.xtf
```

> **Importante**: ili2pg escribe el XTF aunque la validación falle. Un XTF solo es válido si
> el log termina en `Info: ...export done`. Si termina en `...export failed`, el archivo
> existe pero está inválido (así ocurrió con el primer XTF de Tibirita).

## Pendientes / ideas

- [ ] Desarrollar la herramienta de seguimiento de migraciones (ver `04_propuesta_herramienta_seguimiento.md`).
- [ ] Unificar los ETL por municipio en una plantilla parametrizada (esquema, prefijo, dataset).
- [ ] Evaluar si los 277 predios de Tibacuy sin unidad espacial requieren gestión con la fuente.

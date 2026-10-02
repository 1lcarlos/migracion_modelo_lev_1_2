# Contexto general del proyecto

> Documento de arranque para retomar el trabajo. Última actualización: 2026-10-02.

## Objetivo

Migrar los datos catastrales de municipios gestionados en el "modelo gestor" (esquemas
PostgreSQL `cunXXXXX` con tablas `gc_*`, `extavaluo`, `zhf_*`, `cc_*`, etc.) al modelo
**LADM-COL Levantamiento Catastral v1.2** y generar un **XTF INTERLIS validado** por ili2pg.
Solo se migran los predios con avalúo de **una vigencia** (parámetro `VIGENCIA` por
municipio; filtro `date_part('year', extavaluo.vigencia) = <VIGENCIA>`).

## Municipios procesados

| Municipio | Código DANE | Esquema origen | BD PostgreSQL | Vigencia | Prefijo id_operacion | Dataset | XTF |
|---|---|---|---|---|---|---|---|
| Tibirita | 25807 | `cun25807` | `tibirita_lev12` | 2024 | `TIB_` | `tibirita_2024` | `salida/tibirita_lev_cat_v1_2_vigencia2024.xtf` ✅ válido (scripts históricos) |
| Tibacuy | 25805 | `cun25805` | `tibacuy_lev12` | 2024 | `TIBACUY_` | `tibacuy_2024` | `salida/tibacuy_lev_cat_v1_2_vigencia2024.xtf` ✅ válido (scripts históricos) |
| Vergara | 25862 | `cun25862` | `vergara_lev12` | 2023 | `VERGARA_` | `vergara_2023` | `salida/vergara_lev_cat_v1_2_vigencia2023.xtf` ✅ válido (plantilla + complemento XTF feb-2023, 2026-10-02; 471.104 objetos) |

Cada BD contiene dos esquemas: el origen (`cunXXXXX`, restaurado del backup pg_dump) y el
destino (`lev_cat_12`, estructura generada por ili2pg 5.5.1 a partir de los modelos .ili).

## Entorno y herramientas

- **PostgreSQL 16.9** en `localhost:5432`, usuario `postgres`. La conexión y rutas se
  configuran en `.env` (no versionado; plantilla en `.env.example`). PostGIS 3.4.2.
  SRS de trabajo: **9377** (CTM12).
- **psql / pg_dump**: `C:\Program Files\PostgreSQL\16\bin\`
- **Java 8** (requerido por ili2pg): en el PATH.
- **ili2pg 5.5.1**: `C:\ladm_col\desarrollos\creacion_modelos_fisicos\windows_version\ili2pg\ili2pg-5.5.1\ili2pg-5.5.1.jar`
- **Modelos .ili**: carpeta `LADM_COL_Lev_Cat_v1_2_docs\` (se usa como `--modeldir`).

## Estructura del proyecto

```
migracion_modelo_lev_1_2/
├── .env / .env.example           # Conexión PostgreSQL y rutas (.env no se versiona)
├── config/municipios/<mun>.env   # Parámetros por municipio (esquema, BD, prefijo, vigencia, backup, NIT)
├── scripts/migrar.sh             # Orquestador: preparar | dominios | etl | complemento | fix | exportar | verificar | todo
├── scripts/comparar_xtf.py       # Compara dos XTF (conteos por clase, llenado de atributos, predios)
├── scripts/extraer_complemento_xtf.py  # Extrae de un XTF previo datos ausentes en el backup
├── comparacion/                 # XTF de referencia e informes de comparación
├── etl/
│   ├── plantilla/                # ÚNICO ETL vigente, parametrizado con variables psql
│   │   ├── 00_check_dominios.sql
│   │   ├── 01_migracion.sql
│   │   ├── 02_fix_validacion.sql
│   │   ├── 03_verificacion.sql
│   │   └── 04_complemento_xtf.sql   # opcional: datos tomados de un XTF previo
│   └── historico/                # Scripts por municipio usados para Tibirita y Tibacuy (no usar)
├── LADM_COL_Lev_Cat_v1_2_docs/   # Modelos .ili
├── salida/                       # XTF generados + .sha256 de los válidos
├── logs/                         # Logs de restauración y export de ili2pg
├── docs/                         # Esta documentación
└── *.sql                         # Backups pg_dump de los municipios (no versionados)
```

## Convenciones clave del ETL

- **t_id** en destino = `N × 100.000.000 + id_origen`, con N por clase (predio 1, dirección 2,
  terreno 3, construcción 4, unidad 5, características 6, tipología 7, cal. no conv. 8,
  interesado 9, agrupación 10, derecho 11, fuente adm. 12, datos adicionales 13, ofertas 14,
  uebaunit 15, rrrfuente 16, miembros 17, zonas 18–21, av_tipología 22, cartografía 23–33,
  lindero 34, punto lindero 35, punto levantamiento 36, puntoccl 37, masccl 38, menosccl 39,
  fuente espacial 40, baunitfuente 41, extarchivo 42, informalidad 43, ref. registral 44,
  contacto visita 45, novedad número predial 46).
  Requiere id de origen < 100.000.000 (el ETL lo verifica y aborta si no se cumple).
  Secuencia final: `setval('lev_cat_12.t_ili2db_seq', 5000000000, false)`.
  *Tibirita y Tibacuy se generaron con offsets de 1.000.000 (scripts históricos); Vergara
  tiene id de hasta 2,5 millones y obligó al cambio.*
- **t_ili_tid** (OID UUID): `md5('<mun>_<tabla>' || id)::uuid` — el prefijo del municipio
  evita colisiones de OID entre XTF. (Tibirita se generó sin prefijo.)
- **3 baskets**: (1) Levantamiento_Catastral, (2) Avaluos, (3) LimitesOperativosCatastro.
- El esquema `lev_cat_12` se **clona** desde `BD_PLANTILLA_LEV12` (`.env`) para garantizar
  estructura y t_id de catálogos idénticos; el ETL trunca los datos y reconstruye.

> **Importante**: ili2pg escribe el XTF aunque la validación falle. `scripts/migrar.sh`
> solo da por válido el XTF si el log termina en `Info: ...export done`; en ese caso genera
> `<xtf>.sha256`. Si falla, renombra el archivo a `.INVALIDO`.

## Pendientes / ideas

- [ ] Desarrollar la herramienta de seguimiento de migraciones (ver `04_propuesta_herramienta_seguimiento.md`).
- [x] Unificar los ETL por municipio en una plantilla parametrizada (2026-10-02).
- [ ] Evaluar si los predios sin unidad espacial requieren gestión con la fuente (Tibacuy 277, Vergara 85).
- [ ] Vergara: el gestor no trae `tb_valortipologia` → `av_tipologiaconstruccion` vacía. Confirmar si hay otra fuente de valores por tipología.

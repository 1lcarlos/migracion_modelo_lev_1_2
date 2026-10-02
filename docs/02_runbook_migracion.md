# Runbook — Migrar un municipio nuevo

Proceso reproducible probado con Tibirita y Tibacuy. Tiempo estimado: 1–2 horas si los
datos vienen limpios; más si la validación INTERLIS encuentra problemas nuevos
(consultar `03_decisiones_y_lecciones.md` antes de improvisar soluciones).

Variables usadas abajo: `<MUN>` nombre del municipio (ej. `tibacuy`), `<ESQ>` esquema
origen (ej. `cun25805`), `<BD>` base destino (ej. `tibacuy_lev12`), `<PREFIJO>` prefijo
de id_operacion (ej. `TIBACUY_`).

## 1. Crear BD y restaurar el backup

```bash
export PGPASSWORD='...'
PSQL='/c/Program Files/PostgreSQL/16/bin/psql'
"$PSQL" -h localhost -U postgres -c "CREATE DATABASE <BD>;"
"$PSQL" -h localhost -U postgres -d <BD> -c 'CREATE EXTENSION IF NOT EXISTS postgis; CREATE EXTENSION IF NOT EXISTS "uuid-ossp";'
"$PSQL" -h localhost -U postgres -d <BD> -q -f <backup_municipio>.sql
```

> La extensión `uuid-ossp` es obligatoria **antes** de clonar `lev_cat_12` (sus DEFAULT usan
> `uuid_generate_v4()`; sin la extensión, la restauración del esquema falla en cascada).

Verificar la restauración:

```sql
SELECT count(*) FROM <ESQ>.gc_predio;
SELECT count(DISTINCT gc_predio_avaluo) FROM <ESQ>.extavaluo WHERE date_part('year',vigencia)=2024;
-- Confirmar relación 1:1 predio-avalúo en la vigencia (si hay duplicados, el JOIN del ETL multiplica filas)
```

## 2. Clonar el esquema destino `lev_cat_12`

Desde cualquier BD ya migrada (estructura + catálogos con t_id idénticos + metadatos ili2db):

```bash
pg_dump -h localhost -U postgres -d tibacuy_lev12 --schema=lev_cat_12 -f /tmp/lev_cat_12.sql
"$PSQL" -h localhost -U postgres -d <BD> -q -f /tmp/lev_cat_12.sql
```

El ETL trunca los datos clonados y reconstruye, pero conviene verificar al final que solo
las tablas pobladas por el ETL tengan filas.

## 3. Adaptar los scripts ETL

Partir de la versión más reciente (los `*_tibacuy.sql`, que ya incluyen el pipeline
geométrico definitivo) y reemplazar:

| Buscar | Reemplazar por |
|---|---|
| `cun25805` | `<ESQ>` |
| `'TIBACUY_'` | `'<PREFIJO>'` |
| `tibacuy_2024` | `<MUN>_2024` |
| `etl_tibacuy` | `etl_<MUN>` |
| `md5('tibacuy_` | `md5('<MUN>_` (prefijo de OID por municipio — **no omitirlo**) |

Verificar que el `max(id)` de todas las tablas origen sea < 1.000.000 (estrategia de offsets):

```sql
SELECT max(id) FROM <ESQ>.gc_predio;  -- y demás tablas grandes; Tibacuy ~184k, Tibirita ~232k
```

## 4. Chequeo de dominios (00_check_dominios)

```bash
"$PSQL" -h localhost -U postgres -d <BD> -f etl/00_check_dominios_<MUN>.sql
```

Analizar los códigos sin equivalente (`existe = false`):

- `gc_predio.tipo` con `Privado`, `Publico.*`: **falso positivo** — el ETL antepone `Predio.`.
- `tb_valortipologia.tipo_anexo`: **esperado** — el submodelo Avalúos v1.2 no contempla
  anexos; el ETL los excluye.
- Cualquier otro código nuevo: decidir homologación ANTES de migrar y documentarla en
  `03_decisiones_y_lecciones.md` (ej. `NUIP` → `Registro_Civil`).

## 5. Ejecutar la migración (01_migracion)

```bash
"$PSQL" -h localhost -U postgres -d <BD> -v ON_ERROR_STOP=1 -f etl/01_migracion_<MUN>.sql
```

Todo corre en una transacción: si falla, no queda nada a medias. Revisar el resumen de
conteos final. Errores típicos de NOT NULL (documento de identidad vacío, etc.):
ver catálogo en `03_decisiones_y_lecciones.md`.

## 6. Fix post-migración (02_fix_validacion)

```bash
"$PSQL" -h localhost -U postgres -d <BD> -v ON_ERROR_STOP=1 -f etl/02_fix_validacion_<MUN>.sql
```

Hace: dedup de `col_miembros`, TIDs de cartografía, limpieza geométrica
(MakeValid → descartar astillas <1 cm² → SnapToGrid 1 mm → RemoveRepeatedPoints 2 mm),
y NULL en geometrías opcionales que colapsan a vacío.

Tras el dedup de miembros, verificar **agrupaciones unipersonales** (el modelo exige ≥2
miembros); si hay, aplicar la corrección del punto (b) de `etl/03_fix_revalidacion_tibirita.sql`
(derecho pasa al interesado directo, se elimina la agrupación).

```sql
SELECT agrupacion FROM lev_cat_12.col_miembros GROUP BY 1 HAVING count(*) < 2;
```

## 7. Exportar y validar el XTF

```bash
java -jar <ili2pg>/ili2pg-5.5.1.jar --export --exportTid \
 --dbhost localhost --dbport 5432 --dbdatabase <BD> --dbusr postgres --dbpwd "$PGPASSWORD" \
 --dbschema lev_cat_12 --defaultSrsCode 9377 \
 --models 'Modelo_Aplicacion_LADMCOL_Lev_Cat_V1_2;Submodelo_Avaluos_V1_2;Submodelo_Cartografia_Catastral_V1_2' \
 --modeldir LADM_COL_Lev_Cat_v1_2_docs \
 --log logs/export_<MUN>.log salida/<MUN>_lev_cat_v1_2_vigencia2024.xtf
```

- ✅ Válido solo si el log termina en `Info: ...export done` (exit code 0).
- ❌ `...export failed`: el XTF se escribe igual pero está **inválido**. Corregir en BD
  (catálogo de errores en `03_decisiones_y_lecciones.md`) y re-exportar. El validador se
  detiene en el primer error de cada clase: pueden aflorar errores nuevos en cada iteración,
  por eso el fix geométrico se aplica de forma global y preventiva, no caso a caso.

## 8. Verificación final de coherencia

```sql
-- El total de avalúos debe coincidir exactamente
SELECT sum(avaluo_catastral) FROM <ESQ>.extavaluo WHERE date_part('year',vigencia)=2024;
SELECT sum(avaluo_catastral) FROM lev_cat_12.lc_predio;

-- Predios sin unidad espacial (informales/mejoras; el modelo lo permite, pero registrar el dato)
SELECT count(*) FROM lev_cat_12.lc_predio p
WHERE NOT EXISTS (SELECT 1 FROM lev_cat_12.col_uebaunit u WHERE u.baunit=p.t_id);
```

Registrar en la tabla de municipios de `01_contexto_general.md` el resultado.

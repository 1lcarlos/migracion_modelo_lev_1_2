#!/usr/bin/env bash
# ============================================================
# Orquestador de migración gestor -> LADM-COL Lev Cat v1.2
# Uso: scripts/migrar.sh <municipio> [etapa...]
#   municipio: nombre de config/municipios/<municipio>.env
#   etapas: preparar | auxiliar | dominios | etl | complemento | cancelados | operador | fix | exportar | verificar | todo (por defecto)
#   auxiliar: solo si el municipio define BACKUP_AUX/ESQ_AUX (segundo backup cargado como otro esquema)
#   complemento: solo si el municipio define XTF_COMPLEMENTO (XTF de referencia)
#   cancelados: solo si además INCLUIR_CANCELADOS=si (predios con novedad Cancelacion del XTF)
#   operador: solo si además COMPLEMENTO_OPERADOR=si (linderos, puntos, fuentes espaciales, ZHF urbanas y
#             tipologías del XTF de referencia)
# Requiere .env en la raíz (ver .env.example).
# NOTA: para el lote de 25 municipios usar scripts/lote.py (extracción desde BD de corte, controles
# que abortan, ilivalidator y manifiesto). Este script queda para las migraciones con XTF del operador.
# ============================================================
set -euo pipefail

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
cd "$RAIZ"

[[ $# -ge 1 ]] || { echo "Uso: $0 <municipio> [preparar|auxiliar|dominios|etl|complemento|cancelados|operador|fix|exportar|verificar|todo]"; exit 1; }
CFG="config/municipios/$1.env"
[[ -f .env ]] || { echo "Falta .env (copiar de .env.example)"; exit 1; }
[[ -f "$CFG" ]] || { echo "Falta $CFG"; exit 1; }
shift
ETAPAS=("${@:-todo}")

set -a; source .env; source "$CFG"; set +a
[[ -n "${PGPASSWORD:-}" ]] || { echo "PGPASSWORD vacío en .env"; exit 1; }

PSQL="$PG_BIN/psql"
PG_DUMP="$PG_BIN/pg_dump"
XTF="salida/${MUN}_lev_cat_v1_2_vigencia${VIGENCIA}.xtf"
LOG_EXPORT="logs/export_${MUN}_${VIGENCIA}.log"
mkdir -p salida logs

psql_bd() {
  "$PSQL" -d "$BD" -v ON_ERROR_STOP=1 -X \
    -v esq="$ESQ" -v mun="$MUN" -v prefijo="$PREFIJO" -v vigencia="$VIGENCIA" \
    -v razon_municipio="${RAZON_MUNICIPIO:-}" -v nit_municipio="${NIT_MUNICIPIO:-}" \
    -v esq_tipologia="${ESQ_TIPOLOGIA:-$ESQ}" -v zh_ultima="${ZH_ULTIMA_VIGENCIA:-no}" "$@"
}

etapa_preparar() {
  echo "== [preparar] BD $BD desde $BACKUP"
  if "$PSQL" -d postgres -Atc "SELECT 1 FROM pg_database WHERE datname='$BD'" | grep -q 1; then
    echo "La BD $BD ya existe; bórrela manualmente si quiere recrearla."; exit 1
  fi
  "$PSQL" -d postgres -v ON_ERROR_STOP=1 -c "CREATE DATABASE $BD;"
  "$PSQL" -d "$BD" -v ON_ERROR_STOP=1 -c 'CREATE EXTENSION IF NOT EXISTS postgis; CREATE EXTENSION IF NOT EXISTS "uuid-ossp";'
  # El backup trae "CREATE SCHEMA public" (ya existe): se tolera ese error, se revisa el resto.
  # También se toleran los triggers que llaman a attr_sync (esquema externo, no incluido en el dump).
  PGOPTIONS="-c lc_messages=C" "$PSQL" -d "$BD" -q -X -f "$BACKUP" > "logs/restore_${MUN}.log" 2>&1 || true
  if grep -v -e 'schema "public" already exists' -e 'schema "attr_sync" does not exist' "logs/restore_${MUN}.log" | grep -q ERROR; then
    echo "Errores en la restauración (ver logs/restore_${MUN}.log):"
    grep ERROR "logs/restore_${MUN}.log" | grep -v -e 'schema "public" already exists' -e 'schema "attr_sync" does not exist' | head -20
    exit 1
  fi
  echo "== [preparar] clonando lev_cat_12 desde $BD_PLANTILLA_LEV12"
  "$PG_DUMP" -d "$BD_PLANTILLA_LEV12" --schema=lev_cat_12 -f "logs/lev_cat_12_clon.sql"
  "$PSQL" -d "$BD" -q -X -v ON_ERROR_STOP=1 -f "logs/lev_cat_12_clon.sql"
  rm -f "logs/lev_cat_12_clon.sql"
}

# Carga el esquema $ESQ de un segundo backup (BACKUP_AUX) en $BD con el nombre $ESQ_AUX.
# Se restaura en una BD temporal para no duplicar las tablas de public que trae el backup.
etapa_auxiliar() {
  if [[ -z "${BACKUP_AUX:-}" || -z "${ESQ_AUX:-}" ]]; then echo "== [auxiliar] sin BACKUP_AUX/ESQ_AUX: se omite"; return; fi
  if "$PSQL" -d "$BD" -Atc "SELECT 1 FROM pg_namespace WHERE nspname='$ESQ_AUX'" | grep -q 1; then
    echo "== [auxiliar] el esquema $ESQ_AUX ya existe en $BD: se omite"; return
  fi
  local tmp="${BD}_aux"
  echo "== [auxiliar] $BACKUP_AUX -> $BD.$ESQ_AUX (vía BD temporal $tmp)"
  "$PSQL" -d postgres -v ON_ERROR_STOP=1 -c "DROP DATABASE IF EXISTS $tmp;" -c "CREATE DATABASE $tmp;"
  "$PSQL" -d "$tmp" -v ON_ERROR_STOP=1 -c 'CREATE EXTENSION IF NOT EXISTS postgis; CREATE EXTENSION IF NOT EXISTS "uuid-ossp";'
  PGOPTIONS="-c lc_messages=C" "$PSQL" -d "$tmp" -q -X -f "$BACKUP_AUX" > "logs/restore_${MUN}_aux.log" 2>&1 || true
  if grep -v 'schema "public" already exists' "logs/restore_${MUN}_aux.log" | grep -q ERROR; then
    echo "Errores en la restauración auxiliar (ver logs/restore_${MUN}_aux.log)"; exit 1
  fi
  "$PG_DUMP" -d "$tmp" -n "$ESQ" -f "logs/aux_${MUN}.sql"
  "$PSQL" -d "$BD" -X -v ON_ERROR_STOP=1 -c "ALTER SCHEMA $ESQ RENAME TO ${ESQ}_principal;"
  PGOPTIONS="-c lc_messages=C" "$PSQL" -d "$BD" -q -X -v ON_ERROR_STOP=1 -f "logs/aux_${MUN}.sql" > /dev/null || {
    "$PSQL" -d "$BD" -X -c "DROP SCHEMA IF EXISTS $ESQ CASCADE; ALTER SCHEMA ${ESQ}_principal RENAME TO $ESQ;"; exit 1; }
  "$PSQL" -d "$BD" -X -v ON_ERROR_STOP=1 -c "ALTER SCHEMA $ESQ RENAME TO $ESQ_AUX; ALTER SCHEMA ${ESQ}_principal RENAME TO $ESQ;"
  "$PSQL" -d postgres -c "DROP DATABASE $tmp;"
  rm -f "logs/aux_${MUN}.sql"
}

etapa_dominios()  { echo "== [dominios]";  psql_bd -q -f etl/plantilla/00_homologaciones.sql; psql_bd -f etl/plantilla/00_check_dominios.sql; }
etapa_etl()       { echo "== [etl]";       psql_bd -q -f etl/plantilla/00_homologaciones.sql; psql_bd -f etl/plantilla/01_migracion.sql; }
etapa_complemento() {
  if [[ -z "${XTF_COMPLEMENTO:-}" ]]; then echo "== [complemento] sin XTF_COMPLEMENTO: se omite"; return; fi
  local dir="logs/ref_xtf_${MUN}"
  echo "== [complemento] extrayendo $XTF_COMPLEMENTO"
  python scripts/extraer_complemento_xtf.py "$XTF_COMPLEMENTO" "$dir"
  psql_bd -v dir="$dir" -v avaluo_unidades="${COMPLEMENTO_AVALUO_UNIDADES:-si}" -f etl/plantilla/04_complemento_xtf.sql
}
# Clon vacío de lev_cat_12 en el esquema $1 (estructura + dominios + metadatos ili2db, sin
# baskets/datasets) con la secuencia de t_id iniciando en $2. Los dominios conservan sus t_id,
# así que lo que ili2pg importe en el clon se copia a lev_cat_12 sin traducir dominios.
clonar_lev12_vacio() {
  local esq="$1" inicio="$2" dir="logs/ref_xtf_${MUN}" tabs
  mkdir -p "$dir"
  tabs=$(psql_bd -Atc "SELECT string_agg('-t lev_cat_12.'||table_name, ' ') FROM (
      SELECT DISTINCT table_name FROM information_schema.columns WHERE table_schema='lev_cat_12' AND column_name='ilicode'
      UNION SELECT table_name FROM information_schema.tables WHERE table_schema='lev_cat_12' AND table_name LIKE 't_ili2db%'
        AND table_name NOT IN ('t_ili2db_basket','t_ili2db_dataset','t_ili2db_import','t_ili2db_import_basket','t_ili2db_import_object')) x")
  "$PG_DUMP" -d "$BD" -n lev_cat_12 -s -f "$dir/${esq}_s.sql"
  # shellcheck disable=SC2086
  "$PG_DUMP" -d "$BD" --data-only $tabs -f "$dir/${esq}_d.sql"
  cat "$dir/${esq}_s.sql" "$dir/${esq}_d.sql" | sed -e "s/\blev_cat_12\./${esq}./g" \
    -e "s/SCHEMA lev_cat_12\b/SCHEMA ${esq}/g" -e "s/'lev_cat_12'/'${esq}'/g" > "$dir/${esq}.sql"
  psql_bd -q -c "DROP SCHEMA IF EXISTS ${esq} CASCADE"
  PGOPTIONS="-c lc_messages=C" psql_bd -q -f "$dir/${esq}.sql" > "$dir/${esq}_restore.log" 2>&1
  psql_bd -Atc "SELECT setval('${esq}.t_ili2db_seq', ${inicio}, false)" > /dev/null
  rm -f "$dir/${esq}_s.sql" "$dir/${esq}_d.sql" "$dir/${esq}.sql"
}

# Importa con ili2pg el XTF $2 en el esquema $1 (clon de lev_cat_12). $3 = dataset (y nombre del
# log), $4 = modelos, $5 = opciones extra. Aborta si el log no termina en "...import done".
importar_ref() {
  local esq="$1" xtf="$2" dataset="$3" modelos="$4" extra="${5:-}" log="logs/ref_xtf_${MUN}/import_$3.log"
  # shellcheck disable=SC2086
  "$JAVA" -jar "$ILI2PG_JAR" --import --importTid $extra \
    --dbhost "$PGHOST" --dbport "$PGPORT" --dbdatabase "$BD" --dbusr "$PGUSER" --dbpwd "$PGPASSWORD" \
    --dbschema "$esq" --defaultSrsCode 9377 --dataset "$dataset" \
    --models "$modelos" --modeldir "$MODELDIR" \
    --log "$log" "$xtf" > /dev/null 2>&1 || true
  tail -n 1 "$log" | grep -q '\.\.\.import done' || {
    echo "Falló la importación de $xtf (ver $log)"; grep '^Error' "$log" | head; exit 1; }
}

# Predios con novedad Cancelacion del XTF de referencia: se importan con ili2pg en un clon vacío
# de lev_cat_12 (esquema ref_canc) y 05_cancelados_xtf.sql los copia. Re-ejecutar tras cada etl.
etapa_cancelados() {
  if [[ -z "${XTF_COMPLEMENTO:-}" || "${INCLUIR_CANCELADOS:-no}" != "si" ]]; then
    echo "== [cancelados] sin XTF_COMPLEMENTO o INCLUIR_CANCELADOS!=si: se omite"; return
  fi
  local dir="logs/ref_xtf_${MUN}"; mkdir -p "$dir"
  echo "== [cancelados] extrayendo de $XTF_COMPLEMENTO"
  psql_bd -Atc "SELECT numero_predial FROM lev_cat_12.lc_predio WHERE t_id < 6000000000" > "$dir/npn_migrados.txt"
  python scripts/extraer_cancelados_xtf.py "$XTF_COMPLEMENTO" "$dir/npn_migrados.txt" "$dir/cancelados.xtf"
  clonar_lev12_vacio ref_canc 6000000000
  importar_ref ref_canc "$dir/cancelados.xtf" cancelados Modelo_Aplicacion_LADMCOL_Lev_Cat_V1_2
  psql_bd -f etl/plantilla/05_cancelados_xtf.sql
}

# Complemento espacial y de avalúos del XTF de referencia (opcional). Se importan completos sus
# tópicos Levantamiento_Catastral, Avaluos y LimitesOperativosCatastro en un clon vacío de
# lev_cat_12 (esquema ref_ope, t_id >= 8·10⁹) y 06_complemento_operador.sql copia lo que el backup
# no trae: linderos, puntos, fuentes espaciales, ZHF urbanas y tipologías. Va después de cancelados.
etapa_operador() {
  if [[ -z "${XTF_COMPLEMENTO:-}" || "${COMPLEMENTO_OPERADOR:-no}" != "si" ]]; then
    echo "== [operador] sin XTF_COMPLEMENTO o COMPLEMENTO_OPERADOR!=si: se omite"; return
  fi
  local dir="logs/ref_xtf_${MUN}"; mkdir -p "$dir"
  echo "== [operador] importando $XTF_COMPLEMENTO en ref_ope"
  python scripts/filtrar_xtf_ref.py "$XTF_COMPLEMENTO" "$dir/ref_operador.xtf"
  clonar_lev12_vacio ref_ope 8000000000
  # Sin validación al importar: es insumo; el XTF final se valida al exportar
  importar_ref ref_ope "$dir/ref_operador.xtf" operador \
    'Modelo_Aplicacion_LADMCOL_Lev_Cat_V1_2;Submodelo_Avaluos_V1_2;Submodelo_Cartografia_Catastral_V1_2' \
    --disableValidation
  rm -f "$dir/ref_operador.xtf"
  psql_bd -f etl/plantilla/06_complemento_operador.sql
}
etapa_fix()       { echo "== [fix]";       psql_bd -f etl/plantilla/02_fix_validacion.sql; }
etapa_verificar() { echo "== [verificar]"; psql_bd -f etl/plantilla/03_verificacion.sql; }

etapa_exportar() {
  echo "== [exportar] $XTF"
  rm -f "$XTF" "$XTF.sha256" "$XTF.INVALIDO"
  "$JAVA" -jar "$ILI2PG_JAR" --export --exportTid \
    --dbhost "$PGHOST" --dbport "$PGPORT" --dbdatabase "$BD" --dbusr "$PGUSER" --dbpwd "$PGPASSWORD" \
    --dbschema lev_cat_12 --defaultSrsCode 9377 \
    --models 'Modelo_Aplicacion_LADMCOL_Lev_Cat_V1_2;Submodelo_Avaluos_V1_2;Submodelo_Cartografia_Catastral_V1_2' \
    --modeldir "$MODELDIR" --log "$LOG_EXPORT" "$XTF" || true
  # ili2pg escribe el XTF aunque la validación falle: solo es válido con "...export done"
  if tail -n 1 "$LOG_EXPORT" | grep -q '\.\.\.export done'; then
    sha256sum "$XTF" > "$XTF.sha256"
    echo "XTF VÁLIDO: $XTF ($(cut -c1-16 "$XTF.sha256")...)"
  else
    mv -f "$XTF" "$XTF.INVALIDO" 2>/dev/null || true
    echo "XTF INVÁLIDO. Errores (ver $LOG_EXPORT):"
    grep '^Error' "$LOG_EXPORT" | sort | uniq -c | sort -rn | head -20
    exit 1
  fi
}

for e in "${ETAPAS[@]}"; do
  case "$e" in
    todo) etapa_preparar; etapa_auxiliar; etapa_dominios; etapa_etl; etapa_complemento; etapa_cancelados; etapa_operador; etapa_fix; etapa_exportar; etapa_verificar ;;
    preparar|auxiliar|dominios|etl|complemento|cancelados|operador|fix|exportar|verificar) "etapa_$e" ;;
    *) echo "Etapa desconocida: $e"; exit 1 ;;
  esac
done

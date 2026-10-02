#!/usr/bin/env bash
# ============================================================
# Orquestador de migración gestor -> LADM-COL Lev Cat v1.2
# Uso: scripts/migrar.sh <municipio> [etapa...]
#   municipio: nombre de config/municipios/<municipio>.env
#   etapas: preparar | dominios | etl | complemento | fix | exportar | verificar | todo (por defecto)
#   complemento: solo si el municipio define XTF_COMPLEMENTO (XTF de referencia)
# Requiere .env en la raíz (ver .env.example).
# ============================================================
set -euo pipefail

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
cd "$RAIZ"

[[ $# -ge 1 ]] || { echo "Uso: $0 <municipio> [preparar|dominios|etl|complemento|fix|exportar|verificar|todo]"; exit 1; }
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
    -v razon_municipio="${RAZON_MUNICIPIO:-}" -v nit_municipio="${NIT_MUNICIPIO:-}" "$@"
}

etapa_preparar() {
  echo "== [preparar] BD $BD desde $BACKUP"
  if "$PSQL" -d postgres -Atc "SELECT 1 FROM pg_database WHERE datname='$BD'" | grep -q 1; then
    echo "La BD $BD ya existe; bórrela manualmente si quiere recrearla."; exit 1
  fi
  "$PSQL" -d postgres -v ON_ERROR_STOP=1 -c "CREATE DATABASE $BD;"
  "$PSQL" -d "$BD" -v ON_ERROR_STOP=1 -c 'CREATE EXTENSION IF NOT EXISTS postgis; CREATE EXTENSION IF NOT EXISTS "uuid-ossp";'
  # El backup trae "CREATE SCHEMA public" (ya existe): se tolera ese error, se revisa el resto
  PGOPTIONS="-c lc_messages=C" "$PSQL" -d "$BD" -q -X -f "$BACKUP" > "logs/restore_${MUN}.log" 2>&1 || true
  if grep -v 'schema "public" already exists' "logs/restore_${MUN}.log" | grep -q ERROR; then
    echo "Errores en la restauración (ver logs/restore_${MUN}.log):"
    grep ERROR "logs/restore_${MUN}.log" | grep -v 'schema "public" already exists' | head -20
    exit 1
  fi
  echo "== [preparar] clonando lev_cat_12 desde $BD_PLANTILLA_LEV12"
  "$PG_DUMP" -d "$BD_PLANTILLA_LEV12" --schema=lev_cat_12 -f "logs/lev_cat_12_clon.sql"
  "$PSQL" -d "$BD" -q -X -v ON_ERROR_STOP=1 -f "logs/lev_cat_12_clon.sql"
  rm -f "logs/lev_cat_12_clon.sql"
}

etapa_dominios()  { echo "== [dominios]";  psql_bd -f etl/plantilla/00_check_dominios.sql; }
etapa_etl()       { echo "== [etl]";       psql_bd -f etl/plantilla/01_migracion.sql; }
etapa_complemento() {
  if [[ -z "${XTF_COMPLEMENTO:-}" ]]; then echo "== [complemento] sin XTF_COMPLEMENTO: se omite"; return; fi
  local dir="logs/ref_xtf_${MUN}"
  echo "== [complemento] extrayendo $XTF_COMPLEMENTO"
  python scripts/extraer_complemento_xtf.py "$XTF_COMPLEMENTO" "$dir"
  psql_bd -v dir="$dir" -f etl/plantilla/04_complemento_xtf.sql
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
    todo) etapa_preparar; etapa_dominios; etapa_etl; etapa_complemento; etapa_fix; etapa_exportar; etapa_verificar ;;
    preparar|dominios|etl|complemento|fix|exportar|verificar) "etapa_$e" ;;
    *) echo "Etapa desconocida: $e"; exit 1 ;;
  esac
done

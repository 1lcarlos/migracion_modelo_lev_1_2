"""Orquestador del lote de migración gestor -> LADM-COL Lev Cat v1.2.

Lee los municipios de config/lote_25.csv y, para cada uno, ejecuta las etapas en orden:

  extraer     pg_dump del esquema cunXXXXX desde la BD de corte (bd_fuente) a insumos/lote_25/
              (+ tipologías desde bd_tipologia, si aplica). Se reutiliza si ya existe (--reextraer).
  preparar    BD de trabajo l25_<mun> (se recrea): restaura el esquema y la plantilla lev_cat_12
              versionada (etl/esquema/lev_cat_12_plantilla.sql).
  tipologias  carga tb_valortipologia/cuc_tipologiatipo de bd_tipologia en el esquema aux_tipologia.
  dominios    00_homologaciones + 00_check_dominios en modo estricto (aborta si hay códigos sin equivalente).
  etl         00_homologaciones + 01_migracion.
  fix         02_fix_validacion (aborta si algún control queda distinto de 0).
  verificar   03_verificacion (aborta si el avalúo/predios/ZH/copropiedad no cuadran; guarda métricas).
  exportar    ili2pg --export --disableValidation (ok solo si el log termina en "...export done").
  validar     ilivalidator (válido solo si el log termina en "...validation done"); genera .sha256.

Cada corrida deja salida/lote_25/<mun>/manifiesto.json (fuente, hashes, commit, herramientas, etapas,
métricas, XTF) y logs/lote_25/<mun>/<etapa>.log. Si un municipio falla se registra y se sigue con el
siguiente; el código de salida es 1 si alguno falló.

Uso:
  python scripts/lote.py chaguani quipile            # municipios por nombre corto (columna mun)
  python scripts/lote.py --piloto                    # los marcados piloto=si
  python scripts/lote.py --todos
  python scripts/lote.py nemocon --etapas etl,fix,verificar
  python scripts/lote.py nemocon --desde exportar
  python scripts/lote.py --reporte                   # consolida salida/lote_25/resumen_lote.csv
"""
import argparse
import csv
import datetime as dt
import hashlib
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
CATALOGO = RAIZ / "config" / "lote_25.csv"
SALIDA = RAIZ / "salida" / "lote_25"
LOGS = RAIZ / "logs" / "lote_25"
INSUMOS = RAIZ / "insumos" / "lote_25"
PLANTILLA_SQL = "etl/esquema/lev_cat_12_plantilla.sql"
ETAPAS = ["extraer", "preparar", "tipologias", "dominios", "etl", "fix", "verificar", "exportar", "validar"]
MODELOS = "Modelo_Aplicacion_LADMCOL_Lev_Cat_V1_2;Submodelo_Avaluos_V1_2;Submodelo_Cartografia_Catastral_V1_2"
PREFIJO_BD = "l25_"
SQL_USADOS = ["etl/plantilla/00_homologaciones.sql", "etl/plantilla/00_check_dominios.sql",
              "etl/plantilla/01_migracion.sql", "etl/plantilla/02_fix_validacion.sql",
              "etl/plantilla/03_verificacion.sql", PLANTILLA_SQL, "config/homologaciones.csv"]


class EtapaFallida(Exception):
    pass


# ---------------------------------------------------------------- utilidades
def leer_env(ruta):
    env = {}
    for linea in ruta.read_text(encoding="utf-8").splitlines():
        linea = linea.strip()
        if not linea or linea.startswith("#") or "=" not in linea:
            continue
        k, v = linea.split("=", 1)
        env[k.strip()] = v.strip().strip('"').strip("'")
    return env


def sha256(ruta):
    h = hashlib.sha256()
    with open(ruta, "rb") as f:
        for bloque in iter(lambda: f.read(1 << 20), b""):
            h.update(bloque)
    return h.hexdigest()


def ahora():
    return dt.datetime.now().isoformat(timespec="seconds")


def rel(p):
    return Path(p).relative_to(RAIZ).as_posix()


class Entorno:
    def __init__(self):
        if not (RAIZ / ".env").exists():
            sys.exit("Falta .env en la raíz (copiar de .env.example)")
        e = leer_env(RAIZ / ".env")
        if not e.get("PGPASSWORD"):
            sys.exit("PGPASSWORD vacío en .env")
        self.e = e
        bin_ = Path(e.get("PG_BIN", ""))
        self.psql_bin = str(bin_ / "psql")
        self.pg_dump = str(bin_ / "pg_dump")
        self.pg_restore = str(bin_ / "pg_restore")
        self.java = e.get("JAVA", "java")
        self.java_opts = [f"-Xmx{e['JAVA_XMX']}"] if e.get("JAVA_XMX") else []
        self.ili2pg = e.get("ILI2PG_JAR") or str(RAIZ / "ili2pg/ili2pg-5.5.1/ili2pg-5.5.1.jar")
        self.ilivalidator = e.get("ILIVALIDATOR_JAR") or str(RAIZ / "ili2pg/ilivalidator-1.15.0/ilivalidator-1.15.0.jar")
        self.modeldir = str((RAIZ / e.get("MODELDIR", "LADM_COL_Lev_Cat_v1_2_docs")).resolve())
        for jar in (self.ili2pg, self.ilivalidator):
            if not Path(jar).exists():
                sys.exit(f"No existe {jar} (ver ILI2PG_JAR / ILIVALIDATOR_JAR en .env)")
        self.proc_env = dict(os.environ)
        self.proc_env.update({k: e[k] for k in ("PGHOST", "PGPORT", "PGUSER", "PGPASSWORD") if k in e})
        self.proc_env["PGOPTIONS"] = "-c lc_messages=C"
        self.proc_env["PGCLIENTENCODING"] = "UTF8"
        self.proc_env["PGCONNECT_TIMEOUT"] = "10"

    def ejecutar(self, cmd, log, ocultar=(), stdout_a=None):
        """Ejecuta cmd (lista) con cwd=RAIZ; agrega la salida al log. Devuelve (rc, salida)."""
        mostrado = " ".join(cmd)
        for secreto in ocultar:
            mostrado = mostrado.replace(secreto, "***")
        log.parent.mkdir(parents=True, exist_ok=True)
        with open(log, "a", encoding="utf-8") as f:
            f.write(f"\n### {ahora()} $ {mostrado}\n")
        if stdout_a is not None:
            with open(stdout_a, "wb") as out:
                p = subprocess.run(cmd, cwd=RAIZ, env=self.proc_env, stdout=out, stderr=subprocess.PIPE)
            texto = p.stderr.decode("utf-8", "replace")
        else:
            p = subprocess.run(cmd, cwd=RAIZ, env=self.proc_env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            texto = p.stdout.decode("utf-8", "replace")
        with open(log, "a", encoding="utf-8") as f:
            f.write(texto)
            f.write(f"\n### rc={p.returncode}\n")
        return p.returncode, texto

    def psql(self, bd, log, args, variables=None):
        cmd = [self.psql_bin, "-d", bd, "-X", "-w", "-v", "ON_ERROR_STOP=1"]
        for k, v in (variables or {}).items():
            cmd += ["-v", f"{k}={v}"]
        rc, out = self.ejecutar(cmd + args, log)
        if rc != 0:
            errores = [l for l in out.splitlines() if "ERROR" in l or "FATAL" in l]
            raise EtapaFallida("; ".join(errores[-3:]) or f"psql rc={rc}")
        return out

    def escalar(self, bd, sql):
        p = subprocess.run([self.psql_bin, "-d", bd, "-X", "-w", "-At", "-c", sql], cwd=RAIZ,
                           env=self.proc_env, capture_output=True)
        if p.returncode != 0:
            raise EtapaFallida(p.stderr.decode("utf-8", "replace").strip())
        return p.stdout.decode("utf-8", "replace").strip()


# ---------------------------------------------------------------- municipio
class Municipio:
    def __init__(self, fila):
        self.f = fila
        self.codigo = fila["codigo"]
        self.mun = fila["mun"]
        self.nombre = fila["nombre"]
        self.vigencia = int(fila["vigencia"])
        self.esq = "cun" + self.codigo
        self.bd = PREFIJO_BD + self.mun
        self.bd_fuente = fila["bd_fuente"]
        self.bd_tipologia = fila.get("bd_tipologia") or ""
        self.salida = SALIDA / self.mun
        self.logs = LOGS / self.mun
        self.dump = INSUMOS / f"{self.mun}_{self.bd_fuente}_{self.esq}.dump"
        self.tip_valor = INSUMOS / f"{self.mun}_{self.bd_tipologia}_tb_valortipologia.tsv"
        self.tip_tipo = INSUMOS / f"{self.mun}_{self.bd_tipologia}_cuc_tipologiatipo.tsv"
        self.xtf = self.salida / f"{self.mun}_lev_cat_v1_2_vigencia{self.vigencia}.xtf"
        self.manifiesto_ruta = self.salida / "manifiesto.json"
        self.manifiesto = json.loads(self.manifiesto_ruta.read_text(encoding="utf-8")) if self.manifiesto_ruta.exists() else {}

    def variables(self):
        return {"esq": self.esq, "mun": self.mun, "prefijo": self.f["prefijo"], "vigencia": self.vigencia,
                "razon_municipio": self.f.get("razon_municipio", ""), "nit_municipio": self.f.get("nit_municipio", ""),
                "esq_tipologia": "aux_tipologia" if self.bd_tipologia else self.esq,
                "zh_ultima": self.f.get("zh_ultima_vigencia") or "no"}

    def guardar(self):
        self.salida.mkdir(parents=True, exist_ok=True)
        self.manifiesto_ruta.write_text(json.dumps(self.manifiesto, ensure_ascii=False, indent=2), encoding="utf-8")


# ---------------------------------------------------------------- etapas
def etapa_extraer(E, m, args):
    INSUMOS.mkdir(parents=True, exist_ok=True)
    log = m.logs / "extraer.log"
    if m.dump.exists() and not args.reextraer:
        print(f"   dump existente: {rel(m.dump)} (use --reextraer para regenerarlo)")
    else:
        tmp = m.dump.with_suffix(".tmp")
        rc, out = E.ejecutar([E.pg_dump, "-d", m.bd_fuente, "-w", "-n", m.esq, "-Fc", "-f", str(tmp)], log)
        if rc != 0:
            raise EtapaFallida(f"pg_dump falló (ver {rel(log)})")
        tmp.replace(m.dump)
    fuente = {"bd": m.bd_fuente, "esquema": m.esq, "dump": rel(m.dump), "dump_sha256": sha256(m.dump),
              "dump_fecha": dt.datetime.fromtimestamp(m.dump.stat().st_mtime).isoformat(timespec="seconds")}
    if m.bd_tipologia:
        consultas = {
            m.tip_valor: f"\\copy (SELECT id, tipo_tipologia, tipo_anexo, valor_m2_catastral, vigencia FROM {m.esq}.tb_valortipologia "
                         f"WHERE date_part('year', vigencia) = {m.vigencia} ORDER BY id) TO STDOUT",
            m.tip_tipo: f"\\copy (SELECT id, text_code FROM {m.esq}.cuc_tipologiatipo ORDER BY id) TO STDOUT",
        }
        for archivo, sql in consultas.items():
            rc, err = E.ejecutar([E.psql_bin, "-d", m.bd_tipologia, "-X", "-w", "-v", "ON_ERROR_STOP=1", "-c", sql], log, stdout_a=archivo)
            if rc != 0:
                raise EtapaFallida(f"extracción de tipologías falló: {err.strip()}")
        fuente["tipologias"] = {"bd": m.bd_tipologia, "vigencia": m.vigencia,
                                "registros": sum(1 for _ in open(m.tip_valor, encoding="utf-8")),
                                "sha256": {rel(m.tip_valor): sha256(m.tip_valor), rel(m.tip_tipo): sha256(m.tip_tipo)}}
    m.manifiesto["fuente"] = fuente


def etapa_preparar(E, m, args):
    if not m.bd.startswith(PREFIJO_BD):
        raise EtapaFallida(f"por seguridad solo se recrean BD con prefijo {PREFIJO_BD}")
    if not m.dump.exists():
        raise EtapaFallida("no existe el dump: correr la etapa extraer")
    log = m.logs / "preparar.log"
    E.psql("postgres", log, ["-c", f'DROP DATABASE IF EXISTS "{m.bd}" WITH (FORCE)', "-c", f'CREATE DATABASE "{m.bd}"'])
    E.psql(m.bd, log, ["-c", 'CREATE EXTENSION IF NOT EXISTS postgis; CREATE EXTENSION IF NOT EXISTS "uuid-ossp";'])
    # Triggers y funciones del gestor no se restauran: la migración solo lee datos y algunos llaman a
    # esquemas externos que no vienen en el dump (attr_sync, Sutatausa). Se registran en el manifiesto.
    p = subprocess.run([E.pg_restore, "-l", str(m.dump)], cwd=RAIZ, env=E.proc_env, capture_output=True, text=True)
    if p.returncode != 0:
        raise EtapaFallida(f"pg_restore -l falló: {p.stderr.strip()}")
    excluir = ("TRIGGER", "FUNCTION", "PROCEDURE", "RULE", "EVENT TRIGGER", "AGGREGATE")
    lista, excluidos = [], []
    for linea in p.stdout.splitlines():
        partes = linea.split()
        tipo = " ".join(partes[3:5]) if len(partes) > 4 and partes[3] == "EVENT" else (partes[3] if len(partes) > 3 else "")
        if not linea.startswith(";") and tipo in excluir:
            excluidos.append(" ".join(partes[3:]))
        else:
            lista.append(linea)
    lista_ruta = m.logs / "restore_lista.txt"
    lista_ruta.write_text(chr(10).join(lista) + chr(10), encoding="utf-8")
    m.manifiesto.setdefault("fuente", {})["objetos_no_restaurados"] = excluidos
    rc, out = E.ejecutar([E.pg_restore, "-d", m.bd, "-w", "--no-owner", "--no-privileges", "--exit-on-error",
                          "-L", str(lista_ruta), str(m.dump)], log)
    if rc != 0:
        raise EtapaFallida(f"pg_restore falló (ver {rel(log)})")
    if excluidos:
        print(f"   no restaurados (triggers/funciones del gestor): {len(excluidos)}")
    E.psql(m.bd, log, ["-q", "-f", PLANTILLA_SQL])
    n = E.escalar(m.bd, f"SELECT count(*) FROM {m.esq}.gc_predio")
    print(f"   {m.bd}: {n} predios en {m.esq}")


def etapa_tipologias(E, m, args):
    if not m.bd_tipologia:
        print(f"   tipologías del propio esquema {m.esq}")
        return
    log = m.logs / "tipologias.log"
    E.psql(m.bd, log, ["-c", "DROP SCHEMA IF EXISTS aux_tipologia CASCADE; CREATE SCHEMA aux_tipologia;"
                       "CREATE TABLE aux_tipologia.tb_valortipologia(id bigint PRIMARY KEY, tipo_tipologia bigint,"
                       " tipo_anexo bigint, valor_m2_catastral numeric, vigencia date);"
                       "CREATE TABLE aux_tipologia.cuc_tipologiatipo(id bigint PRIMARY KEY, text_code text);",
                       "-c", f"\\copy aux_tipologia.tb_valortipologia FROM '{rel(m.tip_valor)}'",
                       "-c", f"\\copy aux_tipologia.cuc_tipologiatipo FROM '{rel(m.tip_tipo)}'"])
    n = E.escalar(m.bd, "SELECT count(*) FROM aux_tipologia.tb_valortipologia")
    print(f"   aux_tipologia: {n} valores de tipología {m.vigencia} desde {m.bd_tipologia}")


def etapa_dominios(E, m, args):
    log = m.logs / "dominios.log"
    v = m.variables()
    E.psql(m.bd, log, ["-q", "-f", "etl/plantilla/00_homologaciones.sql"])
    out = E.psql(m.bd, log, ["-f", "etl/plantilla/00_check_dominios.sql"], {**v, "estricto": 1})
    avisos = re.findall(r"^\s*(zhf_\S+)\s*\|\s*(.*?)\s*\|\s*(\d+)\s*\|\s*aviso", out, re.M)
    if avisos:
        m.manifiesto.setdefault("avisos", {})["dominios_zhf_sin_equivalente"] = [
            {"uso": u, "valor": c, "n": int(n)} for u, c, n in avisos]
        print(f"   aviso: {len(avisos)} valores de zonas físicas sin equivalente (quedan NULL)")


def etapa_etl(E, m, args):
    log = m.logs / "etl.log"
    E.psql(m.bd, log, ["-q", "-f", "etl/plantilla/00_homologaciones.sql"])
    E.psql(m.bd, log, ["-f", "etl/plantilla/01_migracion.sql"], m.variables())


def etapa_fix(E, m, args):
    E.psql(m.bd, m.logs / "fix.log", ["-f", "etl/plantilla/02_fix_validacion.sql"])


def etapa_verificar(E, m, args):
    out = E.psql(m.bd, m.logs / "verificar.log", ["-f", "etl/plantilla/03_verificacion.sql"], m.variables())
    metricas = {}
    for linea in out.splitlines():
        mm = re.match(r"^([a-z_.0-9]+)\|(-?[0-9.]*)$", linea.strip())
        if mm:
            val = mm.group(2)
            metricas[mm.group(1)] = (float(val) if "." in val else int(val)) if val else None
    m.manifiesto["metricas"] = metricas
    print(f"   predios {metricas.get('predios_migrados')} | avalúo {metricas.get('avaluo_destino'):,.0f}".replace(",", "."))


def etapa_exportar(E, m, args):
    m.salida.mkdir(parents=True, exist_ok=True)
    log = m.logs / "exportar_ili2pg.log"
    # ili2pg escribe en un archivo parcial: si la corrida se interrumpe no queda un XTF truncado con el
    # nombre definitivo. Solo se renombra cuando el log termina en "...export done".
    parcial = m.xtf.with_name(m.xtf.stem + ".parcial.xtf")
    for p in (m.xtf, parcial, Path(str(m.xtf) + ".sha256"), Path(str(m.xtf) + ".INVALIDO"), log):
        p.unlink(missing_ok=True)
    pwd = E.e["PGPASSWORD"]
    # ili2pg solo escribe (--disableValidation): la validación la hace ilivalidator en la etapa validar
    # (mismo motor iox-ili, más estricto). Validar dos veces duplicaba el tiempo.
    cmd = [E.java, *E.java_opts, "-jar", E.ili2pg, "--export", "--exportTid", "--disableValidation",
           "--dbhost", E.e.get("PGHOST", "localhost"), "--dbport", E.e.get("PGPORT", "5432"),
           "--dbdatabase", m.bd, "--dbusr", E.e.get("PGUSER", "postgres"), "--dbpwd", pwd,
           "--dbschema", "lev_cat_12", "--defaultSrsCode", "9377", "--models", MODELOS,
           "--modeldir", E.modeldir, "--log", str(log), str(parcial)]
    E.ejecutar(cmd, m.logs / "exportar.log", ocultar=(pwd,))
    lineas = log.read_text(encoding="utf-8", errors="replace").splitlines() if log.exists() else []
    ok = bool(lineas) and "...export done" in lineas[-1]
    m.manifiesto["xtf"] = {"archivo": rel(m.xtf), "ili2pg": "exportado" if ok else "fallido", "log_ili2pg": rel(log)}
    if ok:
        parcial.replace(m.xtf)
    else:
        if parcial.exists():
            parcial.replace(Path(str(m.xtf) + ".INVALIDO"))
        errores = sorted({l for l in lineas if l.startswith("Error")})[:10]
        raise EtapaFallida("ili2pg: la exportación falló. " + " | ".join(errores))


def etapa_validar(E, m, args):
    if not m.xtf.exists():
        raise EtapaFallida("no existe el XTF: correr exportar")
    log = m.logs / "validar_ilivalidator.log"
    log.unlink(missing_ok=True)
    E.ejecutar([E.java, *E.java_opts, "-jar", E.ilivalidator, "--modeldir", E.modeldir, "--log", str(log), str(m.xtf)],
               m.logs / "validar.log")
    lineas = log.read_text(encoding="utf-8", errors="replace").splitlines() if log.exists() else []
    errores = [l for l in lineas if l.startswith("Error")]
    avisos = [l for l in lineas if l.startswith("Warning")]
    ok = any("...validation done" in l for l in lineas[-3:])
    x = m.manifiesto.setdefault("xtf", {"archivo": rel(m.xtf)})
    x.update({"ilivalidator": "valido" if ok else "invalido", "ilivalidator_errores": len(errores),
              "ilivalidator_avisos": len(avisos), "log_ilivalidator": rel(log)})
    if not ok:
        raise EtapaFallida(f"ilivalidator: {len(errores)} errores. " + " | ".join(errores[:5]))
    h = sha256(m.xtf)
    Path(str(m.xtf) + ".sha256").write_text(f"{h}  {m.xtf.name}\n", encoding="utf-8")
    x.update({"sha256": h, "bytes": m.xtf.stat().st_size})
    print(f"   XTF VÁLIDO (ili2pg + ilivalidator): {rel(m.xtf)} sha256 {h[:16]}…")


FUNCIONES = {e: globals()[f"etapa_{e}"] for e in ETAPAS}


# ---------------------------------------------------------------- manifiesto y ejecución
def info_codigo():
    def git(*a):
        p = subprocess.run(["git", *a], cwd=RAIZ, capture_output=True, text=True)
        return p.stdout.strip()
    sucio = [l[3:] for l in git("status", "--porcelain").splitlines() if not l.endswith(".json")]
    return {"git_commit": git("rev-parse", "HEAD"), "git_rama": git("rev-parse", "--abbrev-ref", "HEAD"),
            "git_sin_commit": sucio, "sha256_sql": {s: sha256(RAIZ / s) for s in SQL_USADOS}}


def info_herramientas(E):
    def version(cmd):
        p = subprocess.run(cmd, capture_output=True, text=True, env=E.proc_env)
        return (p.stdout + p.stderr).strip().splitlines()[0] if (p.stdout + p.stderr).strip() else ""
    return {"ili2pg": Path(E.ili2pg).name, "ilivalidator": Path(E.ilivalidator).name,
            "java": version([E.java, "-version"]), "psql": version([E.psql_bin, "--version"])}


def procesar(E, m, etapas, args, codigo, herramientas):
    print(f"\n=== {m.codigo} {m.nombre} (vigencia {m.vigencia}, {m.bd_fuente}.{m.esq} -> {m.bd})")
    m.manifiesto.update({"municipio": {k: m.f[k] for k in ("codigo", "mun", "nombre", "vigencia", "actualizacion", "prefijo")},
                         "bd_trabajo": m.bd, "codigo": codigo, "herramientas": herramientas})
    if "extraer" in etapas or "preparar" in etapas or "etl" in etapas:
        # Una corrida que rehace los datos invalida métricas y XTF anteriores
        for k in ("metricas", "xtf", "avisos"):
            m.manifiesto.pop(k, None)
    registro = m.manifiesto.setdefault("etapas", {})
    # Lo que se va a correr (y lo posterior) deja de valer hasta que termine: si la corrida se interrumpe,
    # el manifiesto no conserva estados "ok" de una corrida anterior.
    for e in ETAPAS[ETAPAS.index(etapas[0]):]:
        registro[e] = {"estado": "pendiente"}
    if "exportar" in etapas:
        m.manifiesto.pop("xtf", None)
    if "exportar" in etapas or "validar" in etapas:
        Path(str(m.xtf) + ".sha256").unlink(missing_ok=True)
        for k in ("ilivalidator", "ilivalidator_errores", "ilivalidator_avisos", "sha256", "bytes"):
            m.manifiesto.get("xtf", {}).pop(k, None)
    m.manifiesto["estado"] = "en_curso"
    m.guardar()
    for e in etapas:
        t0 = time.time()
        registro[e] = {"inicio": ahora(), "estado": "en_curso"}
        m.guardar()
        print(f"-- [{e}]")
        try:
            FUNCIONES[e](E, m, args)
        except EtapaFallida as ex:
            registro[e].update({"fin": ahora(), "segundos": round(time.time() - t0, 1), "estado": "fallida", "error": str(ex)[:2000]})
            m.manifiesto["estado"] = f"fallida en {e}"
            m.guardar()
            print(f"   FALLÓ: {str(ex)[:600]}\n   (ver {rel(m.logs)}/)")
            return False
        registro[e].update({"fin": ahora(), "segundos": round(time.time() - t0, 1), "estado": "ok"})
        m.guardar()
    completo = all(registro.get(e, {}).get("estado") == "ok" for e in ETAPAS)
    m.manifiesto["estado"] = "completo" if completo else f"parcial (ok hasta {etapas[-1]})"
    m.guardar()
    return True


def reporte(municipios):
    filas = []
    for m in municipios:
        man, met, x = m.manifiesto, m.manifiesto.get("metricas", {}), m.manifiesto.get("xtf", {})
        filas.append({
            "codigo": m.codigo, "municipio": m.nombre, "vigencia": m.vigencia, "actualizacion": m.f["actualizacion"],
            "fuente": f"{m.bd_fuente}.{m.esq}", "estado": man.get("estado", "sin_correr"),
            "predios_migrados": met.get("predios_migrados", ""), "avaluo": met.get("avaluo_destino", ""),
            "avaluo_cuadra": (met.get("avaluo_origen") == met.get("avaluo_destino")) if met else "",
            "predios_sin_unidad_espacial": met.get("predios_sin_unidad_espacial", ""),
            "interesados_excluidos": met.get("interesados_sin_derecho_migrado_excluidos", ""),
            "imputado_documento_sin_dato": met.get("imputado_documento_sin_dato", ""),
            "copropiedad_coef_distinto_1": met.get("copropiedad_matrices_coef_distinto_1", ""),
            "av_tipologias": met.get("conteo.av_tipologiaconstruccion", 0) if met else "",
            "ili2pg": x.get("ili2pg", ""), "ilivalidator": x.get("ilivalidator", ""),
            "xtf_sha256": x.get("sha256", ""), "git_commit": man.get("codigo", {}).get("git_commit", "")[:10],
        })
    SALIDA.mkdir(parents=True, exist_ok=True)
    ruta = SALIDA / "resumen_lote.csv"
    with open(ruta, "w", newline="", encoding="utf-8-sig") as f:
        w = csv.DictWriter(f, fieldnames=list(filas[0]), delimiter=";")
        w.writeheader()
        w.writerows(filas)
    ancho = max(len(f["municipio"]) for f in filas)
    for f in filas:
        print(f"{f['codigo']} {f['municipio']:<{ancho}} {f['vigencia']} {f['estado']:<28} "
              f"predios={f['predios_migrados']!s:>6} ili2pg={f['ili2pg'] or '-':<8} ilivalidator={f['ilivalidator'] or '-'}")
    print(f"\nResumen: {rel(ruta)}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("municipios", nargs="*", help="nombres cortos (columna mun de config/lote_25.csv)")
    ap.add_argument("--todos", action="store_true")
    ap.add_argument("--piloto", action="store_true")
    ap.add_argument("--etapas", help="lista separada por comas (por defecto todas)")
    ap.add_argument("--desde", choices=ETAPAS, help="ejecutar desde esta etapa hasta el final")
    ap.add_argument("--reextraer", action="store_true", help="regenerar el dump aunque exista")
    ap.add_argument("--reporte", action="store_true", help="solo consolidar resumen_lote.csv")
    args = ap.parse_args()

    with open(CATALOGO, encoding="utf-8") as f:
        catalogo = [Municipio(r) for r in csv.DictReader(f, delimiter=";")]
    por_nombre = {m.mun: m for m in catalogo}
    if args.reporte:
        reporte(catalogo)
        return 0
    if args.todos:
        sel = catalogo
    elif args.piloto:
        sel = [m for m in catalogo if m.f.get("piloto") == "si"]
    else:
        desconocidos = [n for n in args.municipios if n not in por_nombre]
        if desconocidos or not args.municipios:
            ap.error(f"municipios desconocidos o vacíos: {desconocidos}. Opciones: {', '.join(por_nombre)}")
        sel = [por_nombre[n] for n in args.municipios]

    etapas = ETAPAS
    if args.etapas:
        etapas = [e.strip() for e in args.etapas.split(",")]
        malas = [e for e in etapas if e not in ETAPAS]
        if malas:
            ap.error(f"etapas desconocidas: {malas}")
        etapas = [e for e in ETAPAS if e in etapas]  # siempre en orden
    elif args.desde:
        etapas = ETAPAS[ETAPAS.index(args.desde):]

    E = Entorno()
    codigo = info_codigo()
    if codigo["git_sin_commit"]:
        print(f"AVISO: hay cambios sin commit ({len(codigo['git_sin_commit'])} archivos); quedan registrados en el manifiesto.")
    herramientas = info_herramientas(E)
    fallidos = [m.nombre for m in sel if not procesar(E, m, etapas, args, codigo, herramientas)]
    print()
    reporte(catalogo)
    if fallidos:
        print(f"\nFALLARON: {', '.join(fallidos)}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

"""Compara un XTF LADM-COL Lev Cat v1.2 con un XML "registro_catastral" (listado de predios).

Cruce por Numero_Predial (codigo_predial_nacional) y por Codigo_Homologado (NUPRE).
En los predios que cruzan compara avalúo, matrícula, áreas, destino, condición, zona e interesados.

Uso: python scripts/comparar_registro_catastral.py <xtf> <xml_registro> <prefijo_salida>
Genera <prefijo_salida>.json (resumen) y <prefijo_salida>_predios.csv (detalle por predio).
"""
import csv
import json
import re
import sys
import unicodedata
import xml.etree.ElementTree as ET
from collections import Counter, defaultdict

NS = "{http://www.interlis.ch/INTERLIS2.3}"
TOL_AREA_REL = 0.01   # 1 % de diferencia relativa
TOL_AREA_ABS = 1.0    # o 1 m²


def loc(tag):
    return tag[len(NS):] if tag.startswith(NS) else tag


def txt(el, a):
    v = el.findtext(NS + a)
    return v.strip() if v and v.strip() else None


def norm_txt(v):
    if not v:
        return ""
    v = unicodedata.normalize("NFKD", v).encode("ascii", "ignore").decode().upper()
    return re.sub(r"[^A-Z0-9]", "", v)


def norm_doc(v):
    return re.sub(r"[^0-9A-Za-z]", "", v or "").lstrip("0").upper()


def num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def leer_xtf(ruta):
    predios, terrenos, ucons, interesados = {}, {}, {}, {}
    miembros, derechos, uebaunit = defaultdict(list), defaultdict(list), []
    prof = 0
    for ev, el in ET.iterparse(ruta, events=("start", "end")):
        if ev == "start":
            prof += 1
            continue
        if prof == 4:
            c = loc(el.tag).split(".")[-1]
            tid = el.get("TID")
            if c == "LC_Predio":
                dirs = []
                for d in el.iter(NS + "LADM_COL_V3_1.LADM_Nucleo.ExtDireccion"):
                    dirs.append(txt(d, "Texto_Direccion") or txt(d, "Nombre_Predio") or "")
                predios[tid] = {
                    "npn": txt(el, "Numero_Predial"), "homologado": txt(el, "Codigo_Homologado"),
                    "orip": txt(el, "Codigo_ORIP"), "matricula": txt(el, "Matricula_Inmobiliaria"),
                    "avaluo": num(txt(el, "Avaluo_Catastral")), "destino": txt(el, "Destinacion_Economica"),
                    "condicion": txt(el, "Condicion_Predio"), "clase_suelo": txt(el, "Clase_Suelo"),
                    "nombre": txt(el, "Nombre"), "direcciones": dirs,
                    "inicio": (txt(el, "Comienzo_Vida_Util_Version") or "")[:10]}
            elif c == "LC_Terreno":
                terrenos[tid] = num(txt(el, "Area_Terreno"))
            elif c == "LC_UnidadConstruccion":
                ucons[tid] = num(txt(el, "Area_Construida"))
            elif c == "LC_Interesado":
                interesados[tid] = (txt(el, "Documento_Identidad"), txt(el, "Tipo_Documento"))
            elif c == "col_miembros":
                miembros[el.find(NS + "agrupacion").get("REF")].append(el.find(NS + "interesado").get("REF"))
            elif c == "LC_Derecho":
                u = el.find(NS + "unidad").get("REF")
                for rol in ("interesado_lc_interesado", "interesado_lc_agrupacioninteresados", "interesado"):
                    r = el.find(NS + rol)
                    if r is not None:
                        derechos[u].append(r.get("REF"))
            elif c == "col_ueBaunit":
                uebaunit.append((el.find(NS + "ue").get("REF"), el.find(NS + "baunit").get("REF")))
            el.clear()
        prof -= 1
    for tid, p in predios.items():
        p["area_terreno"] = None
        p["area_construida"] = None
        p["docs"] = set()
    for ue, bu in uebaunit:
        p = predios.get(bu)
        if p is None:
            continue
        if ue in terrenos and terrenos[ue] is not None:
            p["area_terreno"] = (p["area_terreno"] or 0) + terrenos[ue]
        elif ue in ucons and ucons[ue] is not None:
            p["area_construida"] = (p["area_construida"] or 0) + ucons[ue]
    for u, refs in derechos.items():
        p = predios.get(u)
        if p is None:
            continue
        for r in refs:
            for i in (miembros[r] if r in miembros else [r]):
                d = norm_doc(interesados[i][0]) if i in interesados else ""
                if d:   # documentos vacíos o en cero ("0") no sirven para cruzar
                    p["docs"].add(d)
    return list(predios.values())


def leer_xml(ruta):
    out = []
    for p in ET.parse(ruta).getroot().findall("predio"):
        g = lambda t: (p.findtext(t) or "").strip() or None
        val = lambda v: None if v in (None, "None") else v
        av = p.find("avaluos_catastrales/avaluo_catastral")
        docs = {norm_doc(i.findtext("numero_documento")) for i in p.find("interesados")} - {""}
        out.append({
            "npn": g("codigo_predial_nacional"), "homologado": val(g("codigo_homologado")),
            "matricula": val(g("matricula_inmobiliaria")), "direccion": g("direccion"),
            "area_terreno": num(val(g("area_terreno"))), "area_construida": num(val(g("area_construida"))),
            "destino": g("destino_economico"), "condicion": g("condicion_predio"), "tipo_predio": g("tipo_predio"),
            "avaluo": num(av.findtext("avaluo")) if av is not None else None,
            "vigencia": av.findtext("vigencia") if av is not None else None,
            "docs": docs, "n_interesados": len(list(p.find("interesados")))})
    return out


def area_igual(a, b):
    a, b = a or 0, b or 0
    return abs(a - b) <= max(TOL_AREA_ABS, TOL_AREA_REL * max(a, b))


def mat_xtf(p):
    if not p["matricula"]:
        return None
    return f"{p['orip']}-{p['matricula']}" if p["orip"] else p["matricula"]


def norm_mat(v):
    if not v:
        return ""
    m = re.match(r"^\s*(\d+)\s*-\s*0*(\d+)\s*$", v)
    return f"{int(m.group(1))}-{m.group(2)}" if m else norm_txt(v)


def zona_npn(npn):
    return {"00": "Rural", "01": "Urbano"}.get((npn or "")[5:7], "Otra(" + (npn or "")[5:7] + ")")


def main(ruta_xtf, ruta_xml, prefijo):
    X = leer_xtf(ruta_xtf)
    R = leer_xml(ruta_xml)
    res = {"xtf": ruta_xtf, "xml": ruta_xml}

    def indice(lst, k):
        idx, dup, vac = {}, Counter(), 0
        for p in lst:
            v = p[k]
            if not v:
                vac += 1
                continue
            if v in idx:
                dup[v] += 1
            idx[v] = p
        return idx, dup, vac

    xn, xn_dup, xn_vac = indice(X, "npn")
    xh, xh_dup, xh_vac = indice(X, "homologado")
    rn, rn_dup, rn_vac = indice(R, "npn")
    rh, rh_dup, rh_vac = indice(R, "homologado")
    res["totales"] = {
        "predios_xtf": len(X), "predios_xml": len(R),
        "xtf_npn_vacio": xn_vac, "xtf_npn_duplicado": sum(xn_dup.values()),
        "xtf_homologado_vacio": xh_vac, "xtf_homologado_duplicado": sum(xh_dup.values()),
        "xml_npn_vacio": rn_vac, "xml_npn_duplicado": sum(rn_dup.values()),
        "xml_homologado_vacio": rh_vac, "xml_homologado_duplicado": sum(rh_dup.values()),
        "xml_vigencias_avaluo": dict(Counter(p["vigencia"] for p in R)),
    }

    # Cruce por cada llave
    n_comun = set(xn) & set(rn)
    h_comun = set(xh) & set(rh)
    res["cruce_numero_predial"] = {"coinciden": len(n_comun), "solo_xtf": len(set(xn) - set(rn)),
                                   "solo_xml": len(set(rn) - set(xn))}
    res["cruce_codigo_homologado"] = {"coinciden": len(h_comun), "solo_xtf": len(set(xh) - set(rh)),
                                      "solo_xml": len(set(rh) - set(xh))}

    # Clasificación combinada por predio del XML
    filas, cat = [], Counter()
    usados_xtf = set()
    for r in R:
        xp_n = xn.get(r["npn"])
        xp_h = xh.get(r["homologado"]) if r["homologado"] else None
        if xp_n is not None and xp_h is not None and xp_n is xp_h:
            c = "coincide_npn_y_homologado"
        elif xp_n is not None and xp_h is None:
            c = "coincide_solo_npn_homologado_distinto" if xp_n["homologado"] else "coincide_solo_npn_homologado_vacio_xtf"
        elif xp_n is None and xp_h is not None:
            c = "coincide_solo_homologado_npn_distinto"
        elif xp_n is not None and xp_h is not None:
            c = "conflicto_npn_y_homologado_en_predios_distintos"
        else:
            c = "solo_xml"
        cat[c] += 1
        x = xp_n if xp_n is not None else xp_h
        if x is not None:
            usados_xtf.add(id(x))
        filas.append((c, r, x))
    for x in X:
        if id(x) not in usados_xtf:
            cat["solo_xtf"] += 1
            filas.append(("solo_xtf", None, x))
    res["clasificacion_predios"] = dict(cat)

    # Comparación de atributos en predios cruzados
    cmp = Counter()
    dif_av = []
    destinos, condiciones = Counter(), Counter()
    for c, r, x in filas:
        if r is None or x is None:
            continue
        cmp["pares"] += 1
        if r["avaluo"] is not None and x["avaluo"] is not None:
            if abs(r["avaluo"] - x["avaluo"]) < 1:
                cmp["avaluo_igual"] += 1
            else:
                cmp["avaluo_distinto"] += 1
                dif_av.append(x["avaluo"] - r["avaluo"])
        mr, mx = norm_mat(r["matricula"]), norm_mat(mat_xtf(x))
        cmp["matricula_igual" if mr == mx else
            ("matricula_solo_xml" if mr and not mx else
             "matricula_solo_xtf" if mx and not mr else "matricula_distinta")] += 1
        cmp["area_terreno_igual" if area_igual(r["area_terreno"], x["area_terreno"]) else "area_terreno_distinta"] += 1
        cmp["area_construida_igual" if area_igual(r["area_construida"], x["area_construida"]) else "area_construida_distinta"] += 1
        cmp["destino_igual" if r["destino"] == x["destino"] else "destino_distinto"] += 1
        if r["destino"] != x["destino"]:
            destinos[f"{r['destino']} -> {x['destino']}"] += 1
        cmp["condicion_igual" if r["condicion"] == x["condicion"] else "condicion_distinta"] += 1
        if r["condicion"] != x["condicion"]:
            condiciones[f"{r['condicion']} -> {x['condicion']}"] += 1
        cmp["zona_igual" if r["tipo_predio"] == zona_npn(x["npn"]) else "zona_distinta"] += 1
        dirs_x = {norm_txt(d) for d in x["direcciones"]} | {norm_txt(x["nombre"])}
        cmp["direccion_igual" if norm_txt(r["direccion"]) in dirs_x else "direccion_distinta"] += 1
        if r["docs"] == x["docs"]:
            cmp["interesados_iguales"] += 1
        elif r["docs"] & x["docs"]:
            cmp["interesados_parcial"] += 1
        else:
            cmp["interesados_sin_coincidencia"] += 1
    res["comparacion_atributos"] = dict(cmp)
    res["avaluo"] = {
        "suma_xml": sum(p["avaluo"] or 0 for p in R),
        "suma_xtf": sum(p["avaluo"] or 0 for p in X),
        "suma_xml_predios_cruzados": sum((r["avaluo"] or 0) for c, r, x in filas if r and x),
        "suma_xtf_predios_cruzados": sum((x["avaluo"] or 0) for c, r, x in filas if r and x),
        "diferencias_n": len(dif_av), "diferencias_suma": sum(dif_av),
        "diferencia_max_abs": max((abs(d) for d in dif_av), default=0),
    }
    res["destino_cambios_top"] = destinos.most_common(15)
    res["condicion_cambios"] = condiciones.most_common()
    res["solo_xtf_por_fecha_inicio"] = dict(sorted(Counter(
        x["inicio"][:7] for c, r, x in filas if c == "solo_xtf").items()))
    res["solo_xtf_por_zona"] = dict(Counter(zona_npn(x["npn"]) for c, r, x in filas if c == "solo_xtf"))
    res["solo_xml_por_zona"] = dict(Counter(r["tipo_predio"] for c, r, x in filas if c == "solo_xml"))

    with open(prefijo + ".json", "w", encoding="utf-8") as f:
        json.dump(res, f, ensure_ascii=False, indent=2)
    with open(prefijo + "_predios.csv", "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f, delimiter=";")
        w.writerow(["clasificacion", "npn_xml", "npn_xtf", "homologado_xml", "homologado_xtf",
                    "avaluo_xml", "avaluo_xtf", "matricula_xml", "matricula_xtf",
                    "area_terreno_xml", "area_terreno_xtf", "area_construida_xml", "area_construida_xtf",
                    "destino_xml", "destino_xtf", "condicion_xml", "condicion_xtf",
                    "docs_xml", "docs_xtf", "inicio_vida_util_xtf"])
        for c, r, x in sorted(filas, key=lambda t: (t[0], (t[1] or t[2])["npn"] or "")):
            r = r or {}
            x = x or {}
            w.writerow([c, r.get("npn"), x.get("npn"), r.get("homologado"), x.get("homologado"),
                        r.get("avaluo"), x.get("avaluo"), r.get("matricula"), mat_xtf(x) if x else None,
                        r.get("area_terreno"), x.get("area_terreno"), r.get("area_construida"), x.get("area_construida"),
                        r.get("destino"), x.get("destino"), r.get("condicion"), x.get("condicion"),
                        "|".join(sorted(r.get("docs", []))), "|".join(sorted(x.get("docs", []))), x.get("inicio")])
    print(json.dumps(res, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])

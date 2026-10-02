"""Compara dos XTF INTERLIS 2.3 (LADM-COL): conteos por clase, llenado de atributos y predios.

Uso: python scripts/comparar_xtf.py <xtf_a> <xtf_b> [--salida informe.json]
Lee en streaming (iterparse), apto para archivos de cientos de MB.
"""
import argparse
import json
import sys
import xml.etree.ElementTree as ET
from collections import Counter, defaultdict

NS = "{http://www.interlis.ch/INTERLIS2.3}"
ATR_PREDIO = ["Numero_Predial", "Numero_Predial_Anterior", "Matricula_Inmobiliaria", "Codigo_ORIP",
              "Avaluo_Catastral", "Tipo", "Condicion_Predio", "Destinacion_Economica",
              "Clase_Suelo", "Categoria_Suelo", "Nombre", "Id_Operacion"]


def _local(tag):
    return tag[len(NS):] if tag.startswith(NS) else tag


def leer(ruta):
    clases = Counter()                 # clase -> n objetos
    llenado = defaultdict(Counter)     # clase -> atributo -> n objetos con valor
    baskets = []
    predios = {}                       # numero_predial -> atributos
    predios_dup = Counter()
    modelos = []
    profundidad = 0
    for evento, el in ET.iterparse(ruta, events=("start", "end")):
        if evento == "start":
            profundidad += 1
            if profundidad == 3 and _local(el.tag) != "MODELS":
                baskets.append(_local(el.tag))
            continue
        # end
        if _local(el.tag) == "MODEL":
            modelos.append(el.get("NAME"))
        elif profundidad == 4:  # objeto dentro de un basket
            clase = _local(el.tag).split(".")[-1]
            clases[clase] += 1
            for hijo in el:
                if (hijo.text and hijo.text.strip()) or len(hijo):
                    llenado[clase][_local(hijo.tag)] += 1
            if clase == "LC_Predio":
                d = {a: (el.findtext(NS + a) or None) for a in ATR_PREDIO}
                npn = d["Numero_Predial"]
                if npn in predios:
                    predios_dup[npn] += 1
                predios[npn] = d
            el.clear()
        profundidad -= 1
    return {"ruta": ruta, "modelos": modelos, "baskets": baskets, "clases": clases,
            "llenado": llenado, "predios": predios, "predios_dup": predios_dup}


def num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def comparar(a, b):
    out = {}
    todas = sorted(set(a["clases"]) | set(b["clases"]))
    out["clases"] = [{"clase": c, "a": a["clases"].get(c, 0), "b": b["clases"].get(c, 0),
                      "dif": b["clases"].get(c, 0) - a["clases"].get(c, 0)} for c in todas]
    # llenado de atributos en clases comunes
    llen = []
    for c in todas:
        if c in a["clases"] and c in b["clases"]:
            for at in sorted(set(a["llenado"][c]) | set(b["llenado"][c])):
                pa = a["llenado"][c][at] / a["clases"][c]
                pb = b["llenado"][c][at] / b["clases"][c]
                if abs(pa - pb) >= 0.05:
                    llen.append({"clase": c, "atributo": at, "pct_a": round(100 * pa, 1),
                                 "pct_b": round(100 * pb, 1)})
    out["llenado_diferente"] = llen
    # predios
    pa, pb = a["predios"], b["predios"]
    comunes = set(pa) & set(pb)
    solo_a, solo_b = sorted(set(pa) - set(pb)), sorted(set(pb) - set(pa))
    dif_attr = Counter()
    ejemplos = defaultdict(list)
    for npn in comunes:
        for at in ATR_PREDIO:
            if at in ("Id_Operacion",):
                continue
            va, vb = pa[npn][at], pb[npn][at]
            if at == "Avaluo_Catastral":
                igual = num(va) == num(vb)
            else:
                igual = (va or "").strip() == (vb or "").strip()
            if not igual:
                dif_attr[at] += 1
                if len(ejemplos[at]) < 5:
                    ejemplos[at].append({"npn": npn, "a": va, "b": vb})
    suma = lambda p, ks: sum(num(p[k]["Avaluo_Catastral"]) or 0 for k in ks)
    out["predios"] = {
        "a": len(pa), "b": len(pb), "comunes": len(comunes),
        "solo_a": len(solo_a), "solo_b": len(solo_b),
        "ejemplos_solo_a": solo_a[:20], "ejemplos_solo_b": solo_b[:20],
        "duplicados_a": sum(a["predios_dup"].values()), "duplicados_b": sum(b["predios_dup"].values()),
        "avaluo_total_a": suma(pa, pa), "avaluo_total_b": suma(pb, pb),
        "avaluo_comunes_a": suma(pa, comunes), "avaluo_comunes_b": suma(pb, comunes),
        "atributos_distintos_en_comunes": dict(dif_attr), "ejemplos": ejemplos,
        "solo_a_por_prefijo_zona": dict(Counter(n[5:7] for n in solo_a if n)),
        "solo_b_por_prefijo_zona": dict(Counter(n[5:7] for n in solo_b if n)),
    }
    out["modelos"] = {"a": a["modelos"], "b": b["modelos"]}
    out["baskets"] = {"a": a["baskets"], "b": b["baskets"]}
    return out


def imprimir(r, na, nb):
    print(f"A = {na}\nB = {nb}\n")
    print("Modelos A:", ", ".join(r["modelos"]["a"]))
    print("Modelos B:", ", ".join(r["modelos"]["b"]))
    print("\n== Objetos por clase")
    print(f"{'clase':45s} {'A':>9s} {'B':>9s} {'B-A':>9s}")
    for f in r["clases"]:
        print(f"{f['clase']:45s} {f['a']:>9d} {f['b']:>9d} {f['dif']:>+9d}")
    print(f"{'TOTAL':45s} {sum(f['a'] for f in r['clases']):>9d} {sum(f['b'] for f in r['clases']):>9d}")
    p = r["predios"]
    print("\n== Predios (por Numero_Predial)")
    for k in ("a", "b", "comunes", "solo_a", "solo_b", "duplicados_a", "duplicados_b"):
        print(f"  {k:14s} {p[k]}")
    print(f"  avalúo total A {p['avaluo_total_a']:,.0f} | B {p['avaluo_total_b']:,.0f}")
    print(f"  avalúo comunes A {p['avaluo_comunes_a']:,.0f} | B {p['avaluo_comunes_b']:,.0f}")
    print("  solo A por zona (pos 6-7 del NPN):", p["solo_a_por_prefijo_zona"])
    print("  solo B por zona (pos 6-7 del NPN):", p["solo_b_por_prefijo_zona"])
    print("  atributos distintos en predios comunes:", p["atributos_distintos_en_comunes"])
    for at, ej in p["ejemplos"].items():
        print(f"    {at}: {ej[:3]}")
    print("\n== Atributos con llenado distinto (>= 5 puntos)")
    for f in r["llenado_diferente"]:
        print(f"  {f['clase']}.{f['atributo']}: A {f['pct_a']}% | B {f['pct_b']}%")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("a"); ap.add_argument("b"); ap.add_argument("--salida")
    args = ap.parse_args()
    a, b = leer(args.a), leer(args.b)
    r = comparar(a, b)
    imprimir(r, args.a, args.b)
    if args.salida:
        with open(args.salida, "w", encoding="utf-8") as fh:
            json.dump(r, fh, ensure_ascii=False, indent=1, default=dict)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()

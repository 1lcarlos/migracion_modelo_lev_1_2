"""Extrae de un XTF LADM-COL de referencia los predios con novedad 'Cancelacion' que no están
en la migración, junto con todos los objetos que dependen de ellos, y los escribe en un XTF
mínimo (solo el tópico Levantamiento_Catastral) importable con ili2pg.

Uso: python scripts/extraer_cancelados_xtf.py <xtf_referencia> <npn_migrados.txt> <xtf_salida>

Cierre de objetos: LC_Predio cancelado -> LC_Derecho (unidad) -> titular (LC_Interesado o
LC_AgrupacionInteresados + col_miembros + sus interesados) -> col_rrrFuente ->
LC_FuenteAdministrativa; col_baunitFuente -> LC_FuenteEspacial; LC_DatosAdicionales... (lc_predio)
-> LC_ContactoVisita. Los objetos se copian tal cual (mismos TID y atributos).
"""
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict

NS = "{http://www.interlis.ch/INTERLIS2.3}"
MODELO = "Modelo_Aplicacion_LADMCOL_Lev_Cat_V1_2"
TOPICO = MODELO + ".Levantamiento_Catastral"


def loc(tag):
    return tag[len(NS):] if tag.startswith(NS) else tag


def main(ref, npn_migrados, salida):
    migrados = {l.strip() for l in open(npn_migrados, encoding="utf-8") if l.strip()}
    objs = {}                     # tid -> elemento (solo del tópico Levantamiento_Catastral)
    asoc = defaultdict(list)      # clase -> [elemento]
    prof, basket = 0, None
    for ev, el in ET.iterparse(ref, events=("start", "end")):
        if ev == "start":
            prof += 1
            if prof == 3:
                basket = loc(el.tag)
            continue
        if prof == 4 and basket == TOPICO:
            c = loc(el.tag).split(".")[-1]
            if el.get("TID") is not None:
                objs[el.get("TID")] = el
            elif c.startswith("col_"):
                asoc[c].append(el)
        elif prof == 4:
            el.clear()
        prof -= 1

    clase = lambda e: loc(e.tag).split(".")[-1]
    ref = lambda e, rol: (e.find(NS + rol).get("REF") if e.find(NS + rol) is not None else None)

    dla = {ref(e, "lc_predio"): e for e in objs.values()
           if clase(e) == "LC_DatosAdicionalesLevantamientoCatastral"}
    predios = {t for t, e in objs.items() if clase(e) == "LC_Predio"
               and e.findtext(NS + "Numero_Predial") not in migrados
               and t in dla and any(n.text == "Cancelacion" for n in dla[t].iter(NS + "Tipo_Novedad"))}

    sel = set(predios)
    sel |= {dla[t].get("TID") for t in predios}
    dlas = {dla[t].get("TID") for t in predios}
    sel |= {t for t, e in objs.items() if clase(e) == "LC_ContactoVisita" and ref(e, "lc_datos_adicionales") in dlas}
    derechos = {t for t, e in objs.items() if clase(e) == "LC_Derecho" and ref(e, "unidad") in predios}
    sel |= derechos
    titulares = {ref(objs[t], "interesado") for t in derechos} - {None}
    sel |= titulares
    out_asoc = []
    for a in asoc["col_miembros"]:
        if ref(a, "agrupacion") in titulares:
            out_asoc.append(a)
            sel.add(ref(a, "interesado"))
    for a in asoc["col_rrrFuente"]:
        if ref(a, "rrr") in derechos:
            out_asoc.append(a)
            sel.add(ref(a, "fuente_administrativa"))
    for a in asoc["col_baunitFuente"]:
        if ref(a, "unidad") in predios:
            out_asoc.append(a)
            sel.add(ref(a, "fuente_espacial"))

    faltan = [t for t in sel if t not in objs]
    if faltan:
        sys.exit(f"Referencias sin resolver en el XTF de referencia: {faltan[:5]}")

    with open(salida, "w", encoding="utf-8") as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>'
                '<TRANSFER xmlns="http://www.interlis.ch/INTERLIS2.3">\n'
                '<HEADERSECTION SENDER="extraer_cancelados_xtf" VERSION="2.3"><MODELS>'
                f'<MODEL NAME="{MODELO}" VERSION="V2.2.1" URI="http://www.proadmintierra.info/"></MODEL>'
                '</MODELS></HEADERSECTION>\n<DATASECTION>\n'
                f'<{TOPICO} BID="cancelados_ref">\n')
        ET.register_namespace("", NS[1:-1])
        for t, e in objs.items():   # mismo orden que la referencia
            if t in sel:
                f.write(ET.tostring(e, encoding="unicode").replace(' xmlns="http://www.interlis.ch/INTERLIS2.3"', "") + "\n")
        for a in out_asoc:
            f.write(ET.tostring(a, encoding="unicode").replace(' xmlns="http://www.interlis.ch/INTERLIS2.3"', "") + "\n")
        f.write(f"</{TOPICO}>\n</DATASECTION>\n</TRANSFER>\n")

    cuenta = defaultdict(int)
    for t in sel:
        cuenta[clase(objs[t])] += 1
    for a in out_asoc:
        cuenta[clase(a)] += 1
    print("Predios cancelados:", len(predios))
    print("Objetos extraídos:", dict(sorted(cuenta.items())))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main(*sys.argv[1:4])

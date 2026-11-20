"""Deja de un XTF LADM-COL de referencia solo los baskets de los tópicos que exporta la migración
(Levantamiento_Catastral, Avaluos y LimitesOperativosCatastro), para importarlo completo con ili2pg
en un clon vacío de lev_cat_12 (esquema ref_ope, etapa "operador" de scripts/migrar.sh).
Los baskets de los submodelos de insumos (gestor, SNR, integración) se descartan: no están en
el esquema destino. Los objetos se copian tal cual (mismos TID y atributos).

Uso: python scripts/filtrar_xtf_ref.py <xtf_referencia> <xtf_salida>
"""
import sys
from collections import Counter

from lxml import etree

NS = "{http://www.interlis.ch/INTERLIS2.3}"
TOPICOS = {
    "Modelo_Aplicacion_LADMCOL_Lev_Cat_V1_2.Levantamiento_Catastral": "Modelo_Aplicacion_LADMCOL_Lev_Cat_V1_2",
    "Submodelo_Avaluos_V1_2.Avaluos": "Submodelo_Avaluos_V1_2",
    "Submodelo_Cartografia_Catastral_V1_2.LimitesOperativosCatastro": "Submodelo_Cartografia_Catastral_V1_2",
}


def loc(tag):
    return tag[len(NS):] if tag.startswith(NS) else tag


def main(ref, salida):
    cuenta, descartados = Counter(), Counter()
    with open(salida, "w", encoding="utf-8") as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>'
                '<TRANSFER xmlns="http://www.interlis.ch/INTERLIS2.3">\n'
                '<HEADERSECTION SENDER="filtrar_xtf_ref" VERSION="2.3"><MODELS>')
        for modelo in TOPICOS.values():
            f.write(f'<MODEL NAME="{modelo}" VERSION="V2.2.1" URI="http://www.proadmintierra.info/"></MODEL>')
        f.write('</MODELS></HEADERSECTION>\n<DATASECTION>\n')
        prof, basket = 0, None
        for ev, el in etree.iterparse(ref, events=("start", "end"), huge_tree=True):
            if ev == "start":
                prof += 1
                if prof == 3:
                    basket = loc(el.tag)
                    if basket in TOPICOS:
                        f.write(f'<{basket} BID="{el.get("BID")}">\n')
                continue
            prof -= 1
            if prof == 3:                       # objeto dentro de un basket
                clase = loc(el.tag)
                if basket in TOPICOS:
                    xml = etree.tostring(el, encoding="unicode", with_tail=False)
                    f.write(xml.replace(' xmlns="http://www.interlis.ch/INTERLIS2.3"', "") + "\n")
                    cuenta[clase.split(".")[-1]] += 1
                else:
                    descartados[basket] += 1
                el.clear()
                while el.getprevious() is not None:
                    del el.getparent()[0]
            elif prof == 2 and basket in TOPICOS:   # cierre del basket
                f.write(f"</{basket}>\n")
        f.write("</DATASECTION>\n</TRANSFER>\n")
    print("Objetos copiados:", dict(sorted(cuenta.items())))
    print("Objetos descartados por basket:", dict(descartados))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main(*sys.argv[1:3])

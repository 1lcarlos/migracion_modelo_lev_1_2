"""Extrae de un XTF LADM-COL de referencia los datos que no existen en el backup del gestor
y los escribe como TSV (formato COPY de PostgreSQL) para cargarlos al esquema ref_xtf.

Uso: python scripts/extraer_complemento_xtf.py <xtf_referencia> <dir_salida>

Archivos generados:
  ref_predio.tsv     tid, numero_predial
  ref_dla.tsv        tid, predio_tid                       (LC_DatosAdicionalesLevantamientoCatastral)
  ref_novedad.tsv    dla_tid, seq, numero_predial, tipo_novedad
  ref_contacto.tsv   dla_tid, tipo_doc, num_doc, primer_nombre, segundo_nombre, primer_apellido,
                     segundo_apellido, domicilio, celular, correo, autoriza
  ref_caract.tsv     espacio_de_nombres, local_id, identificador, area_construida, anio_construccion,
                     uso, observaciones, avaluo_unidad_construccion
"""
import os
import sys
import xml.etree.ElementTree as ET

NS = "{http://www.interlis.ch/INTERLIS2.3}"


def txt(el, tag):
    v = el.findtext(NS + tag)
    return v if v not in (None, "") else None


def ref(el, tag):
    r = el.find(NS + tag)
    return r.get("REF") if r is not None else None


def esc(v):
    if v is None:
        return r"\N"
    return v.replace("\\", "\\\\").replace("\t", "\\t").replace("\n", "\\n").replace("\r", "\\r")


def main(xtf, out):
    os.makedirs(out, exist_ok=True)
    f = {n: open(os.path.join(out, f"ref_{n}.tsv"), "w", encoding="utf-8", newline="\n")
         for n in ("predio", "dla", "novedad", "contacto", "caract")}
    w = lambda n, fila: f[n].write("\t".join(esc(v) for v in fila) + "\n")
    n = {k: 0 for k in f}
    profundidad = 0
    for evento, el in ET.iterparse(xtf, events=("start", "end")):
        if evento == "start":
            profundidad += 1
            continue
        if profundidad == 4:
            clase = el.tag.split(".")[-1]
            tid = el.get("TID")
            if clase == "LC_Predio":
                w("predio", (tid, txt(el, "Numero_Predial"))); n["predio"] += 1
            elif clase == "LC_DatosAdicionalesLevantamientoCatastral":
                w("dla", (tid, ref(el, "lc_predio"))); n["dla"] += 1
                nov = el.find(NS + "Novedad_Numeros_Prediales")
                if nov is not None:
                    for seq, s in enumerate(nov):
                        w("novedad", (tid, str(seq), txt(s, "Numero_Predial"), txt(s, "Tipo_Novedad")))
                        n["novedad"] += 1
            elif clase == "LC_ContactoVisita":
                w("contacto", (ref(el, "lc_datos_adicionales"),
                               txt(el, "Tipo_Documento_Quien_Atendio"), txt(el, "Numero_Documento_Quien_Atendio"),
                               txt(el, "Primer_Nombre_Quien_Atendio"), txt(el, "Segundo_Nombre_Quien_Atendio"),
                               txt(el, "Primer_Apellido_Quien_Atendio"), txt(el, "Segundo_Apellido_Quien_Atendio"),
                               txt(el, "Domicilio_Notificaciones"), txt(el, "Celular"),
                               txt(el, "Correo_Electronico"), txt(el, "Autoriza_Notificaciones")))
                n["contacto"] += 1
            elif clase == "LC_CaracteristicasUnidadConstruccion":
                w("caract", (txt(el, "Espacio_De_Nombres"), txt(el, "Local_Id"),
                             txt(el, "Identificador"), txt(el, "Area_Construida"),
                             txt(el, "Anio_Construccion"), txt(el, "Uso"),
                             txt(el, "Observaciones"), txt(el, "Avaluo_Unidad_Construccion")))
                n["caract"] += 1
            el.clear()
        profundidad -= 1
    for h in f.values():
        h.close()
    print("Extraídos:", n)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main(sys.argv[1], sys.argv[2])

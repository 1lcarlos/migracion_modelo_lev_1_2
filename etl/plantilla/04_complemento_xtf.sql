-- ============================================================
-- Complemento desde un XTF de referencia (opcional, por municipio)
-- Carga datos que NO existen en el backup del gestor pero sí en un XTF previo del
-- municipio, extraídos con scripts/extraer_complemento_xtf.py:
--   * LC_CaracteristicasUnidadConstruccion: observaciones y avaluo_unidad_construccion
--   * LC_EstructuraNovedadNumeroPredial (novedades de números prediales, t_id 46)
--   * LC_ContactoVisita (t_id 45)
-- Cruces: características por huella (espacio, local_id, identificador, área, año, uso)
-- aceptando solo pares 1 a 1; datos adicionales por número predial del predio.
-- Parámetros psql (-v): dir (carpeta con los TSV). Ejecutar después de 01_migracion.
-- ============================================================
\set ON_ERROR_STOP 1
DROP SCHEMA IF EXISTS ref_xtf CASCADE;
CREATE SCHEMA ref_xtf;
CREATE TABLE ref_xtf.predio(tid text, numero_predial text);
CREATE TABLE ref_xtf.dla(tid text, predio_tid text);
CREATE TABLE ref_xtf.novedad(dla_tid text, seq int, numero_predial text, tipo_novedad text);
CREATE TABLE ref_xtf.contacto(dla_tid text, tipo_doc text, num_doc text, primer_nombre text,
  segundo_nombre text, primer_apellido text, segundo_apellido text, domicilio text,
  celular text, correo text, autoriza boolean);
CREATE TABLE ref_xtf.caract(espacio_de_nombres text, local_id text, identificador text,
  area_construida numeric, anio_construccion int, uso text, observaciones text, avaluo numeric);

-- \copy no interpola variables psql: se cambia al directorio de los TSV
\cd :dir
\copy ref_xtf.predio FROM 'ref_predio.tsv'
\copy ref_xtf.dla FROM 'ref_dla.tsv'
\copy ref_xtf.novedad FROM 'ref_novedad.tsv'
\copy ref_xtf.contacto FROM 'ref_contacto.tsv'
\copy ref_xtf.caract FROM 'ref_caract.tsv'

BEGIN;

-- Datos adicionales de referencia -> datos adicionales migrados (por número predial)
CREATE TEMP TABLE map_dla AS
SELECT DISTINCT ON (d.tid) d.tid AS ref_tid, ld.t_id
FROM ref_xtf.dla d
JOIN ref_xtf.predio p ON p.tid = d.predio_tid
JOIN lev_cat_12.lc_predio lp ON lp.numero_predial = p.numero_predial
JOIN lev_cat_12.lc_datosadicionaleslevantamientocatastral ld ON ld.lc_predio = lp.t_id
ORDER BY d.tid, ld.t_id;

-- 1. Características: observaciones y avalúo de la unidad
CREATE TEMP TABLE map_caract AS
WITH k AS (
  SELECT k.t_id, k.espacio_de_nombres, k.local_id, k.identificador, k.area_construida,
         k.anio_construccion, u.ilicode AS uso
  FROM lev_cat_12.lc_caracteristicasunidadconstruccion k
  LEFT JOIN lev_cat_12.lc_usouconstipo u ON u.t_id = k.uso),
r AS (SELECT row_number() OVER () AS rid, * FROM ref_xtf.caract),
m AS (
  SELECT k.t_id, r.rid, r.observaciones, r.avaluo FROM k JOIN r
    ON r.espacio_de_nombres = k.espacio_de_nombres AND r.local_id = k.local_id
   AND r.identificador IS NOT DISTINCT FROM k.identificador
   AND r.area_construida IS NOT DISTINCT FROM k.area_construida
   AND r.anio_construccion IS NOT DISTINCT FROM k.anio_construccion
   AND r.uso IS NOT DISTINCT FROM k.uso)
SELECT * FROM m
WHERE t_id IN (SELECT t_id FROM m GROUP BY 1 HAVING count(*) = 1)
  AND rid  IN (SELECT rid  FROM m GROUP BY 1 HAVING count(*) = 1);

UPDATE lev_cat_12.lc_caracteristicasunidadconstruccion k
SET observaciones = left(m.observaciones, 255), avaluo_unidad_construccion = round(m.avaluo, 1)
FROM map_caract m WHERE m.t_id = k.t_id;

-- 2. Novedades de números prediales (estructura de LC_DatosAdicionales...)
INSERT INTO lev_cat_12.lc_estructuranovedadnumeropredial
 (t_id, t_basket, t_seq, numero_predial, tipo_novedad, lc_dtsdcnlstmntctstral_novedad_numeros_prediales)
SELECT 4600000000 + (m.t_id - 1300000000) * 10 + n.seq, 1, n.seq, n.numero_predial,
  public.fx_dom('lc_estructuranovedadnumeropredial_tipo_novedad', n.tipo_novedad), m.t_id
FROM ref_xtf.novedad n JOIN map_dla m ON m.ref_tid = n.dla_tid;

-- 3. Contacto de la visita
INSERT INTO lev_cat_12.lc_contactovisita
 (t_id, t_basket, t_ili_tid, tipo_documento_quien_atendio, numero_documento_quien_atendio,
  primer_nombre_quien_atendio, segundo_nombre_quien_atendio, primer_apellido_quien_atendio,
  segundo_apellido_quien_atendio, domicilio_notificaciones, celular, correo_electronico,
  autoriza_notificaciones, lc_datos_adicionales)
SELECT 4500000000 + (m.t_id - 1300000000), 1,
  md5(:'mun'||'_lc_contacto'||(m.t_id - 1300000000))::uuid,
  public.fx_dom('lc_interesadodocumentotipo', c.tipo_doc), left(c.num_doc,50),
  left(c.primer_nombre,100), left(c.segundo_nombre,100), left(c.primer_apellido,100),
  left(c.segundo_apellido,100), left(c.domicilio,255), left(c.celular,20), left(c.correo,100),
  c.autoriza, m.t_id
FROM ref_xtf.contacto c JOIN map_dla m ON m.ref_tid = c.dla_tid;

COMMIT;

-- Resumen de cruces
SELECT 'caract_ref' k, (SELECT count(*) FROM ref_xtf.caract) ref,
       (SELECT count(*) FROM map_caract) aplicados
UNION ALL SELECT 'novedades', (SELECT count(*) FROM ref_xtf.novedad),
       (SELECT count(*) FROM lev_cat_12.lc_estructuranovedadnumeropredial)
UNION ALL SELECT 'contactos', (SELECT count(*) FROM ref_xtf.contacto),
       (SELECT count(*) FROM lev_cat_12.lc_contactovisita)
UNION ALL SELECT 'dla_cruzados', (SELECT count(*) FROM ref_xtf.dla), (SELECT count(*) FROM map_dla);

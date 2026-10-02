-- ============================================================
-- ETL Tibacuy: cun25805 (gestor) -> lev_cat_12 (LADM-COL Lev Cat v1.2)
-- Vigencia 2024. Genera datos listos para exportar a XTF con ili2pg.
-- Estrategia de IDs: t_id = offset_millon + id_origen (max id origen: 231.721)
-- t_ili_tid: UUID determinístico md5(tabla||id) para tópicos con OID UUID.
-- ============================================================
BEGIN;

-- Limpieza previa (re-ejecutable)
TRUNCATE lev_cat_12.col_uebaunit, lev_cat_12.col_rrrfuente, lev_cat_12.col_miembros,
  lev_cat_12.lc_tipologiaconstruccion, lev_cat_12.lc_calificacionnoconvencional,
  lev_cat_12.lc_unidadconstruccion, lev_cat_12.lc_caracteristicasunidadconstruccion,
  lev_cat_12.lc_construccion, lev_cat_12.lc_terreno,
  lev_cat_12.extdireccion, lev_cat_12.lc_datosadicionaleslevantamientocatastral,
  lev_cat_12.lc_ofertasmercadoinmobiliario,
  lev_cat_12.lc_derecho, lev_cat_12.lc_fuenteadministrativa,
  lev_cat_12.lc_interesado, lev_cat_12.lc_agrupacioninteresados,
  lev_cat_12.lc_predio,
  lev_cat_12.av_zonahomogeneafisicarural, lev_cat_12.av_zonahomogeneafisicaurbana,
  lev_cat_12.av_zonahomogeneageoeconomicarural, lev_cat_12.av_zonahomogeneageoeconomicaurbana,
  lev_cat_12.av_tipologiaconstruccion,
  lev_cat_12.cc_barrio, lev_cat_12.cc_centropoblado, lev_cat_12.cc_corregimiento,
  lev_cat_12.cc_limitemunicipio, lev_cat_12.cc_localidadcomuna, lev_cat_12.cc_manzana,
  lev_cat_12.cc_nomenclaturavial, lev_cat_12.cc_perimetrourbano,
  lev_cat_12.cc_sectorrural, lev_cat_12.cc_sectorurbano, lev_cat_12.cc_vereda
  CASCADE;
DELETE FROM lev_cat_12.t_ili2db_basket;
DELETE FROM lev_cat_12.t_ili2db_dataset;

-- ------------------------------------------------------------
-- Dataset y baskets
-- ------------------------------------------------------------
INSERT INTO lev_cat_12.t_ili2db_dataset(t_id, datasetname) VALUES (1,'tibacuy_2024');
INSERT INTO lev_cat_12.t_ili2db_basket(t_id, dataset, topic, t_ili_tid, attachmentkey) VALUES
 (1,1,'Modelo_Aplicacion_LADMCOL_Lev_Cat_V1_2.Levantamiento_Catastral', md5('tibacuy_basket_lev')::uuid::text,'etl_tibacuy_2024'),
 (2,1,'Submodelo_Avaluos_V1_2.Avaluos',                                 md5('tibacuy_basket_av')::uuid::text,'etl_tibacuy_2024'),
 (3,1,'Submodelo_Cartografia_Catastral_V1_2.LimitesOperativosCatastro', md5('tibacuy_basket_cc')::uuid::text,'etl_tibacuy_2024');

-- ------------------------------------------------------------
-- Universo de migración (filtro vigencia 2024 y exclusión de huérfanos)
-- ------------------------------------------------------------
DROP TABLE IF EXISTS mig_predio, mig_terreno, mig_constr, mig_uc, mig_caract, mig_fadm;

-- Predios con avalúo vigencia 2024
CREATE TEMP TABLE mig_predio AS
SELECT p.*, a.avaluo_catastral AS avaluo_2024,
       'TIBACUY_'||lpad((row_number() OVER (ORDER BY p.numero_predial))::text,5,'0') AS id_operacion
FROM cun25805.gc_predio p
JOIN cun25805.extavaluo a ON a.gc_predio_avaluo = p.id AND date_part('year',a.vigencia)=2024;

-- Terrenos ligados a un predio migrado
CREATE TEMP TABLE mig_terreno AS
SELECT DISTINCT t.id FROM cun25805.gc_terreno t
JOIN cun25805.col_uebaunit u ON u.ue_gc_terreno=t.id
JOIN mig_predio p ON p.id=u.unidad;

-- Unidades de construcción válidas: con predio directo, con construcción y características
CREATE TEMP TABLE mig_uc AS
SELECT DISTINCT uc.id FROM cun25805.gc_unidadconstruccion uc
JOIN cun25805.col_uebaunit u ON u.ue_gc_unidadconstruccion=uc.id
JOIN mig_predio p ON p.id=u.unidad
WHERE uc.gc_construccion IS NOT NULL AND uc.gc_caracteristicasunidadconstruccion IS NOT NULL;

-- Construcciones: con predio directo o rescatadas vía sus unidades migradas
CREATE TEMP TABLE mig_constr AS
SELECT DISTINCT c.id FROM cun25805.gc_construccion c
LEFT JOIN cun25805.col_uebaunit u ON u.ue_gc_construccion=c.id
LEFT JOIN mig_predio p ON p.id=u.unidad
WHERE p.id IS NOT NULL
   OR EXISTS (SELECT 1 FROM cun25805.gc_unidadconstruccion uc JOIN mig_uc m ON m.id=uc.id WHERE uc.gc_construccion=c.id);

-- Características referenciadas por unidades migradas
CREATE TEMP TABLE mig_caract AS
SELECT DISTINCT uc.gc_caracteristicasunidadconstruccion AS id
FROM cun25805.gc_unidadconstruccion uc JOIN mig_uc m ON m.id=uc.id;

-- Fuentes administrativas ligadas a derechos de predios migrados
CREATE TEMP TABLE mig_fadm AS
SELECT DISTINCT f.id FROM cun25805.gc_fuenteadministrativa f
JOIN cun25805.col_rrrfuente r ON r.fuente_administrativa=f.id
JOIN cun25805.gc_derecho d ON d.id=r.rrr_gc_derecho
JOIN mig_predio p ON p.id=d.baunit;

-- ------------------------------------------------------------
-- 1. LC_Predio  (t_id = 1M + id)
-- ------------------------------------------------------------
INSERT INTO lev_cat_12.lc_predio
 (t_id, t_basket, t_ili_tid, departamento, municipio, id_operacion, tiene_fmi, codigo_orip,
  matricula_inmobiliaria, numero_predial, numero_predial_anterior, codigo_homologado,
  interrelacionado, codigo_homologado_fmi, nupre, avaluo_catastral, valor_referencia,
  tipo, condicion_predio, destinacion_economica, clase_suelo, categoria_suelo, nombre,
  comienzo_vida_util_version, fin_vida_util_version, espacio_de_nombres, local_id)
SELECT 1000000+p.id, 1, md5('tibacuy_lc_predio'||p.id)::uuid,
  p.departamento, p.municipio, p.id_operacion,
  COALESCE(p.tiene_fmi,false), p.codigo_orip, p.matricula_inmobiliaria,
  p.numero_predial, left(p.numero_predial_anterior,20), p.nupre,
  COALESCE(p.interrelacionado,false), COALESCE(p.nupre_fmi,false),
  CASE WHEN COALESCE(p.nupre_fmi,false) THEN p.nupre END,
  p.avaluo_2024,
  (SELECT CASE WHEN v.valor ~ '^[0-9]+(\.[0-9]+)?$' THEN round(v.valor::numeric,1) END
     FROM cun25805.extvalor v WHERE v.gc_predio_valor_referencia=p.id ORDER BY v.fecha DESC NULLS LAST, v.id DESC LIMIT 1),
  (SELECT e.t_id FROM lev_cat_12.col_unidadadministrativabasicatipo e
    WHERE e.thisclass='Modelo_Aplicacion_LADMCOL_Lev_Cat_V1_2.LC_PredioTipo'
      AND e.ilicode='Predio.'||COALESCE(dt.text_code,'Privado')),
  (SELECT e.t_id FROM lev_cat_12.lc_condicionprediotipo e WHERE e.ilicode=dc.text_code),
  (SELECT e.t_id FROM lev_cat_12.lc_destinacioneconomicatipo e WHERE e.ilicode=dd.text_code),
  (SELECT e.t_id FROM lev_cat_12.lc_clasesuelotipo e WHERE e.ilicode=ds.text_code),
  (SELECT e.t_id FROM lev_cat_12.lc_categoriasuelotipo e WHERE e.ilicode=dcat.text_code),
  p.nombre,
  p.comienzo_vida_util_version, p.fin_vida_util_version,
  COALESCE(p.espacio_de_nombres,'LC_PREDIO'), COALESCE(p.local_id, p.id::text)
FROM mig_predio p
LEFT JOIN cun25805.gc_prediotipo dt ON dt.id=p.tipo
LEFT JOIN cun25805.gc_condicionprediotipo dc ON dc.id=p.condicion_predio
LEFT JOIN cun25805.gc_destinacioneconomicatipo dd ON dd.id=p.destinacion_economica
LEFT JOIN cun25805.gc_clasesuelotipo ds ON ds.id=p.clase_suelo
LEFT JOIN cun25805.gc_categoriasuelotipo dcat ON dcat.id=p.categoria_suelo;

-- ------------------------------------------------------------
-- 2. Direcciones del predio (estructura ExtDireccion, t_id = 2M + id)
-- ------------------------------------------------------------
INSERT INTO lev_cat_12.extdireccion
 (t_id, t_basket, t_seq, tipo_direccion, es_direccion_principal, localizacion, codigo_postal,
  clase_via_principal, valor_via_principal, letra_via_principal, sector_ciudad,
  valor_via_generadora, letra_via_generadora, numero_predio, sector_predio,
  complemento, nombre_predio, lc_predio_direccion)
SELECT 2000000+d.id, 1,
  row_number() OVER (PARTITION BY d.gc_predio_direccion ORDER BY d.seq NULLS LAST, d.id) - 1,
  (SELECT e.t_id FROM lev_cat_12.extdireccion_tipo_direccion e WHERE e.ilicode=td.text_code),
  d.es_direccion_principal,
  CASE WHEN d.localizacion IS NOT NULL THEN ST_Force3D(d.localizacion) END,
  d.codigo_postal,
  (SELECT e.t_id FROM lev_cat_12.extdireccion_clase_via_principal e WHERE e.ilicode=cv.text_code),
  d.valor_via_principal, d.letra_via_principal,
  (SELECT e.t_id FROM lev_cat_12.extdireccion_sector_ciudad e WHERE e.ilicode=sc.text_code),
  d.valor_via_generadora, d.letra_via_generadora, d.numero_predio,
  (SELECT e.t_id FROM lev_cat_12.extdireccion_sector_predio e WHERE e.ilicode=sp.text_code),
  d.complemento, d.nombre_predio,
  1000000+d.gc_predio_direccion
FROM cun25805.extdireccion d
JOIN mig_predio p ON p.id=d.gc_predio_direccion
LEFT JOIN cun25805.extdireccion_tipo_direccion td ON td.id=d.tipo_direccion
LEFT JOIN cun25805.extdireccion_clase_via_principal cv ON cv.id=d.clase_via_principal
LEFT JOIN cun25805.extdireccion_sector_ciudad sc ON sc.id=d.sector_ciudad
LEFT JOIN cun25805.extdireccion_sector_predio sp ON sp.id=d.sector_predio;

-- ------------------------------------------------------------
-- 3. LC_Terreno (t_id = 3M + id)
-- ------------------------------------------------------------
INSERT INTO lev_cat_12.lc_terreno
 (t_id, t_basket, t_ili_tid, area_terreno, avaluo_terreno, manzana_vereda_codigo,
  geometria, etiqueta, comienzo_vida_util_version, fin_vida_util_version,
  espacio_de_nombres, local_id)
SELECT 3000000+t.id, 1, md5('tibacuy_lc_terreno'||t.id)::uuid,
  round(t.area,1), NULL, left(t.codigo,17),
  ST_Multi(ST_CollectionExtract(ST_MakeValid(t.geometria),3)),
  t.etiqueta, t.comienzo_vida_util_version, t.fin_vida_util_version,
  COALESCE(t.espacio_de_nombres,'LC_TERRENO'), COALESCE(t.local_id, t.id::text)
FROM cun25805.gc_terreno t JOIN mig_terreno m ON m.id=t.id;

-- ------------------------------------------------------------
-- 4. LC_Construccion (t_id = 4M + id)
-- ------------------------------------------------------------
INSERT INTO lev_cat_12.lc_construccion
 (t_id, t_basket, t_ili_tid, identificador, tipo_construccion, tipo_dominio,
  numero_pisos, numero_sotanos, numero_mezanines, numero_semisotanos, anio_construccion,
  avaluo_construccion, valor_referencia_construccion, area_construccion, altura,
  observaciones, geometria, etiqueta,
  comienzo_vida_util_version, fin_vida_util_version, espacio_de_nombres, local_id)
SELECT 4000000+c.id, 1, md5('tibacuy_lc_construccion'||c.id)::uuid,
  COALESCE(c.identificador, c.codigo, c.id::text),
  (SELECT e.t_id FROM lev_cat_12.lc_construcciontipo e WHERE e.ilicode=tc.text_code),
  (SELECT e.t_id FROM lev_cat_12.lc_dominioconstrucciontipo e WHERE e.ilicode=tdo.text_code),
  COALESCE(c.numero_pisos,1), c.numero_sotanos, c.numero_mezanines, c.numero_semisotanos,
  CASE WHEN c.anio_construccion BETWEEN 1550 AND 2500 THEN c.anio_construccion END,
  NULL, c.valor_referencia, round(c.area,1),
  CASE WHEN c.altura > 0 THEN round(c.altura,2) END,
  c.observacion,
  NULLIF(ST_Multi(ST_CollectionExtract(ST_MakeValid(c.geometria),3)),
         ST_SetSRID('MULTIPOLYGON EMPTY'::geometry, 9377)),
  c.etiqueta,
  c.comienzo_vida_util_version, c.fin_vida_util_version,
  COALESCE(c.espacio_de_nombres,'LC_CONSTRUCCION'), COALESCE(c.local_id, c.id::text)
FROM cun25805.gc_construccion c
JOIN mig_constr m ON m.id=c.id
LEFT JOIN cun25805.gc_construcciontipo tc ON tc.id=c.tipo_construccion
LEFT JOIN cun25805.gc_dominioconstrucciontipo tdo ON tdo.id=c.tipo_dominio;

-- ------------------------------------------------------------
-- 5. LC_CaracteristicasUnidadConstruccion (t_id = 6M + id)
-- ------------------------------------------------------------
INSERT INTO lev_cat_12.lc_caracteristicasunidadconstruccion
 (t_id, t_basket, t_ili_tid, identificador, tipo_construccion, tipo_dominio,
  tipo_unidad_construccion, tipo_planta, total_habitaciones, total_banios, total_locales,
  total_plantas, uso, anio_construccion, avaluo_unidad_construccion, area_construida,
  area_privada_construida, observaciones,
  comienzo_vida_util_version, fin_vida_util_version, espacio_de_nombres, local_id)
SELECT 6000000+k.id, 1, md5('tibacuy_lc_caract'||k.id)::uuid,
  k.identificador,
  (SELECT e.t_id FROM lev_cat_12.lc_construcciontipo e WHERE e.ilicode=tc.text_code),
  (SELECT e.t_id FROM lev_cat_12.lc_dominioconstrucciontipo e WHERE e.ilicode=tdo.text_code),
  (SELECT e.t_id FROM lev_cat_12.lc_unidadconstrucciontipo e WHERE e.ilicode=tuc.text_code),
  (SELECT e.t_id FROM lev_cat_12.lc_construccionplantatipo e WHERE e.ilicode=tp.text_code),
  k.total_habitaciones, k.total_banios, k.total_locales, k.total_plantas,
  (SELECT e.t_id FROM lev_cat_12.lc_usouconstipo e WHERE e.ilicode=us.text_code),
  CASE WHEN k.anio_construccion BETWEEN 1512 AND 2500 THEN k.anio_construccion END,
  NULL, round(k.area,1), round(k.area_privada_construida,1), k.observacion,
  k.comienzo_vida_util_version, k.fin_vida_util_version,
  COALESCE(k.espacio_de_nombres,'LC_CARACTERISTICASUNIDADCONSTRUCCION'), COALESCE(k.local_id, k.id::text)
FROM cun25805.gc_caracteristicasunidadconstruccion k
JOIN mig_caract m ON m.id=k.id
LEFT JOIN cun25805.gc_construcciontipo tc ON tc.id=k.tipo_construccion
LEFT JOIN cun25805.gc_dominioconstrucciontipo tdo ON tdo.id=k.tipo_dominio
LEFT JOIN cun25805.gc_unidadconstrucciontipo tuc ON tuc.id=k.tipo_unidad_construccion
LEFT JOIN cun25805.gc_construccionplantatipo tp ON tp.id=k.tipo_planta
LEFT JOIN cun25805.gc_usouconstipo us ON us.id=k.uso;

-- ------------------------------------------------------------
-- 6. LC_UnidadConstruccion (t_id = 5M + id)
-- ------------------------------------------------------------
INSERT INTO lev_cat_12.lc_unidadconstruccion
 (t_id, t_basket, t_ili_tid, planta_ubicacion, area_construida, altura, geometria,
  lc_caracteristicasunidadconstruccion, lc_construccion, etiqueta,
  comienzo_vida_util_version, fin_vida_util_version, espacio_de_nombres, local_id)
SELECT 5000000+uc.id, 1, md5('tibacuy_lc_uc'||uc.id)::uuid,
  COALESCE(uc.planta_ubicacion,1), round(uc.area,1),
  CASE WHEN uc.altura >= 1 THEN round(uc.altura)::int END,
  NULLIF(ST_Multi(ST_CollectionExtract(ST_MakeValid(uc.geometria),3)),
         ST_SetSRID('MULTIPOLYGON EMPTY'::geometry, 9377)),
  6000000+uc.gc_caracteristicasunidadconstruccion, 4000000+uc.gc_construccion,
  uc.etiqueta,
  uc.comienzo_vida_util_version, uc.fin_vida_util_version,
  COALESCE(uc.espacio_de_nombres,'LC_UNIDADCONSTRUCCION'), COALESCE(uc.local_id, uc.id::text)
FROM cun25805.gc_unidadconstruccion uc JOIN mig_uc m ON m.id=uc.id;

-- ------------------------------------------------------------
-- 7. Calificaciones (tipología 7M, no convencional 8M)
-- ------------------------------------------------------------
INSERT INTO lev_cat_12.lc_tipologiaconstruccion
 (t_id, t_basket, t_ili_tid, tipo_tipologia, cual, lc_unidad_construccion)
SELECT 7000000+t.id, 1, md5('tibacuy_lc_tipologia'||t.id)::uuid,
  (SELECT e.t_id FROM lev_cat_12.lc_tipologiatipo e WHERE e.ilicode=tt.text_code),
  NULL, 6000000+t.gc_caracteristicasunidadconstruccion
FROM cun25805.cuc_tipologiaconstruccion t
JOIN mig_caract m ON m.id=t.gc_caracteristicasunidadconstruccion
LEFT JOIN cun25805.cuc_tipologiatipo tt ON tt.id=t.tipo_tipologia;

INSERT INTO lev_cat_12.lc_calificacionnoconvencional
 (t_id, t_basket, t_ili_tid, tipo_anexo, lc_unidad_construccion)
SELECT 8000000+n.id, 1, md5('tibacuy_lc_calnoconv'||n.id)::uuid,
  (SELECT e.t_id FROM lev_cat_12.lc_anexotipo e WHERE e.ilicode=ta.text_code),
  6000000+n.gc_caracteristicasunidadconstruccion
FROM cun25805.cuc_calificacionnoconvencional n
JOIN mig_caract m ON m.id=n.gc_caracteristicasunidadconstruccion
LEFT JOIN cun25805.cuc_anexotipo ta ON ta.id=n.tipo_anexo;

-- ------------------------------------------------------------
-- 8. Interesados (9M) y agrupaciones (10M) + miembros (17M)
-- ------------------------------------------------------------
INSERT INTO lev_cat_12.lc_interesado
 (t_id, t_basket, t_ili_tid, tipo, tipo_documento, documento_identidad,
  primer_nombre, segundo_nombre, primer_apellido, segundo_apellido, sexo, grupo_etnico,
  razon_social, estado_civil, nombre,
  comienzo_vida_util_version, fin_vida_util_version, espacio_de_nombres, local_id)
SELECT 9000000+i.id, 1, md5('tibacuy_lc_interesado'||i.id)::uuid,
  (SELECT e.t_id FROM lev_cat_12.lc_interesadotipo e WHERE e.ilicode=ti.text_code),
  -- NUIP no existe en LC_InteresadoDocumentoTipo v1.2: se homologa a Registro_Civil
  (SELECT e.t_id FROM lev_cat_12.lc_interesadodocumentotipo e
    WHERE e.ilicode = CASE WHEN td.text_code='NUIP' THEN 'Registro_Civil' ELSE td.text_code END),
  -- documento_identidad es MANDATORY: 2 registros del municipio vienen vacíos;
  -- NIT 800018689-5 tomado de otros registros del mismo interesado en la fuente
  COALESCE(NULLIF(btrim(i.documento_identidad),''),
    CASE WHEN i.razon_social ILIKE '%MUNICIPIO DE TIBACUY%' THEN '8000186895' ELSE 'Sin_Dato' END),
  i.primer_nombre, i.segundo_nombre, i.primer_apellido, i.segundo_apellido,
  (SELECT e.t_id FROM lev_cat_12.lc_sexotipo e WHERE e.ilicode=sx.text_code),
  (SELECT e.t_id FROM lev_cat_12.lc_grupoetnicotipo e WHERE e.ilicode=ge.text_code),
  i.razon_social,
  (SELECT e.t_id FROM lev_cat_12.lc_estadociviltipo e WHERE e.ilicode=ec.text_code),
  i.nombre,
  i.comienzo_vida_util_version, i.fin_vida_util_version,
  COALESCE(i.espacio_de_nombres,'LC_INTERESADO'), COALESCE(i.local_id, i.id::text)
FROM cun25805.gc_interesado i
LEFT JOIN cun25805.gc_interesadotipo ti ON ti.id=i.tipo
LEFT JOIN cun25805.gc_interesadodocumentotipo td ON td.id=i.tipo_documento
LEFT JOIN cun25805.gc_sexotipo sx ON sx.id=i.sexo
LEFT JOIN cun25805.gc_grupoetnicotipo ge ON ge.id=i.grupo_etnico
LEFT JOIN cun25805.gc_estadociviltipo ec ON ec.id=i.estado_civil;

INSERT INTO lev_cat_12.lc_agrupacioninteresados
 (t_id, t_basket, t_ili_tid, tipo, nombre,
  comienzo_vida_util_version, fin_vida_util_version, espacio_de_nombres, local_id)
SELECT 10000000+a.id, 1, md5('tibacuy_lc_agrupacion'||a.id)::uuid,
  (SELECT e.t_id FROM lev_cat_12.col_grupointeresadotipo e WHERE e.ilicode=tg.text_code),
  a.nombre,
  a.comienzo_vida_util_version, a.fin_vida_util_version,
  COALESCE(a.espacio_de_nombres,'LC_AGRUPACIONINTERESADOS'), COALESCE(a.local_id, a.id::text)
FROM cun25805.gc_agrupacioninteresados a
LEFT JOIN cun25805.col_grupointeresadotipo tg ON tg.id=a.tipo;

INSERT INTO lev_cat_12.col_miembros
 (t_id, t_basket, interesado_lc_interesado, agrupacion, participacion)
SELECT 17000000+m.id, 1, 9000000+m.interesado_gc_interesado, 10000000+m.agrupacion, m.participacion
FROM cun25805.col_miembros m;

-- ------------------------------------------------------------
-- 9. LC_Derecho (11M), LC_FuenteAdministrativa (12M), col_rrrfuente (16M)
-- ------------------------------------------------------------
INSERT INTO lev_cat_12.lc_derecho
 (t_id, t_basket, t_ili_tid, tipo, fraccion_derecho, fecha_inicio_tenencia, descripcion,
  interesado_lc_interesado, interesado_lc_agrupacioninteresados, unidad,
  comienzo_vida_util_version, fin_vida_util_version, espacio_de_nombres, local_id)
SELECT 11000000+d.id, 1, md5('tibacuy_lc_derecho'||d.id)::uuid,
  (SELECT e.t_id FROM lev_cat_12.lc_derechotipo e WHERE e.ilicode=dt.text_code),
  d.fraccion_derecho, d.fecha_inicio_tenencia, d.descripcion,
  CASE WHEN d.interesado_gc_interesado IS NOT NULL THEN 9000000+d.interesado_gc_interesado END,
  CASE WHEN d.interesado_gc_agrupacioninteresados IS NOT NULL THEN 10000000+d.interesado_gc_agrupacioninteresados END,
  1000000+d.baunit,
  d.comienzo_vida_util_version, d.fin_vida_util_version,
  COALESCE(d.espacio_de_nombres,'LC_DERECHO'), COALESCE(d.local_id, d.id::text)
FROM cun25805.gc_derecho d
JOIN mig_predio p ON p.id=d.baunit
LEFT JOIN cun25805.gc_derechotipo dt ON dt.id=d.tipo;

INSERT INTO lev_cat_12.lc_fuenteadministrativa
 (t_id, t_basket, t_ili_tid, tipo, ente_emisor, observacion, numero_fuente,
  estado_disponibilidad, tipo_principal, fecha_documento_fuente, espacio_de_nombres, local_id)
SELECT 12000000+f.id, 1, md5('tibacuy_lc_fadm'||f.id)::uuid,
  (SELECT e.t_id FROM lev_cat_12.col_fuenteadministrativatipo e
    WHERE e.thisclass='Modelo_Aplicacion_LADMCOL_Lev_Cat_V1_2.LC_FuenteAdministrativaTipo'
      AND e.ilicode=tf.text_code),
  f.ente_emisor, f.descripcion, left(f.numero_fuente,150),
  (SELECT e.t_id FROM lev_cat_12.col_estadodisponibilidadtipo e WHERE e.ilicode=ed.text_code),
  NULL, f.fecha_documento_fuente,
  COALESCE(f.espacio_de_nombres,'LC_FUENTEADMINISTRATIVA'), COALESCE(f.local_id, f.id::text)
FROM cun25805.gc_fuenteadministrativa f
JOIN mig_fadm m ON m.id=f.id
LEFT JOIN cun25805.gc_fuenteadministrativatipo tf ON tf.id=f.tipo
LEFT JOIN cun25805.col_estadodisponibilidadtipo ed ON ed.id=f.estado_disponibilidad;

INSERT INTO lev_cat_12.col_rrrfuente
 (t_id, t_basket, fuente_administrativa, rrr_lc_derecho)
SELECT 16000000+r.id, 1, 12000000+r.fuente_administrativa, 11000000+r.rrr_gc_derecho
FROM cun25805.col_rrrfuente r
JOIN mig_fadm f ON f.id=r.fuente_administrativa
JOIN cun25805.gc_derecho d ON d.id=r.rrr_gc_derecho
JOIN mig_predio p ON p.id=d.baunit;

-- ------------------------------------------------------------
-- 10. col_uebaunit (15M): terrenos, construcciones y unidades -> predio
-- ------------------------------------------------------------
INSERT INTO lev_cat_12.col_uebaunit
 (t_id, t_basket, ue_lc_terreno, ue_lc_construccion, ue_lc_unidadconstruccion, baunit)
SELECT 15000000+u.id, 1,
  CASE WHEN mt.id IS NOT NULL THEN 3000000+u.ue_gc_terreno END,
  CASE WHEN mc.id IS NOT NULL THEN 4000000+u.ue_gc_construccion END,
  CASE WHEN mu.id IS NOT NULL THEN 5000000+u.ue_gc_unidadconstruccion END,
  1000000+u.unidad
FROM cun25805.col_uebaunit u
JOIN mig_predio p ON p.id=u.unidad
LEFT JOIN mig_terreno mt ON mt.id=u.ue_gc_terreno
LEFT JOIN mig_constr mc ON mc.id=u.ue_gc_construccion
LEFT JOIN mig_uc mu ON mu.id=u.ue_gc_unidadconstruccion
WHERE mt.id IS NOT NULL OR mc.id IS NOT NULL OR mu.id IS NOT NULL;

-- ------------------------------------------------------------
-- 11. Datos adicionales levantamiento catastral (13M)
-- ------------------------------------------------------------
INSERT INTO lev_cat_12.lc_datosadicionaleslevantamientocatastral
 (t_id, t_basket, t_ili_tid, tiene_area_registral, area_registral_m2,
  procedimiento_catastral_registral, observaciones, fecha_visita_predial,
  tipo_documento_reconocedor, numero_documento_reconocedor,
  primer_nombre_reconocedor, segundo_nombre_reconocedor,
  primer_apellido_reconocedor, segundo_apellido_reconocedor,
  resultado_visita, otro_cual_resultado_visita, suscribe_acta_colindancia,
  despojo_abandono, estrato, otro_cual_estrato, lc_predio)
SELECT 13000000+d.id, 1, md5('tibacuy_lc_dlc'||d.id)::uuid,
  d.tiene_area_registral, round(d.area_registral_m2,2),
  (SELECT e.t_id FROM lev_cat_12.lc_procedimientocatastralregistraltipo e WHERE e.ilicode='No_Requiere'),
  left(d.observaciones,500), d.fecha_visita_predial,
  (SELECT e.t_id FROM lev_cat_12.lc_interesadodocumentotipo e WHERE e.ilicode='Cedula_Ciudadania'),
  d.numero_documento_reconocedor,
  d.primer_nombre_reconocedor, d.segundo_nombre_reconocedor,
  d.primer_apellido_reconocedor, d.segundo_apellido_reconocedor,
  (SELECT e.t_id FROM lev_cat_12.lc_resultadovisitatipo e WHERE e.ilicode=
    CASE d.resultado_visita
      WHEN 'Exitoso' THEN 'Exitoso'
      WHEN 'Otro' THEN 'Otro'
      WHEN 'Incompleto' THEN 'Incompleto'
      WHEN 'No permitieron acceso' THEN 'No_Permitieron_Acceso'
      WHEN 'No hay nadie' THEN 'No_Hay_Nadie'
      WHEN 'Menor de edad' THEN 'Menor_Edad'
      WHEN 'Zona de difícil acceso' THEN 'Zona_Dificil_Acceso'
    END),
  d.otro_cual_resultado_visita, d.suscribe_acta_colindancia,
  d.despojo_abandono, NULL, NULLIF(d.otro_cual_estrato,''),
  1000000+d.gc_predio
FROM cun25805.dlc_datosadicionaleslevantamientocatastral d
JOIN mig_predio p ON p.id=d.gc_predio;

-- ------------------------------------------------------------
-- 12. Ofertas mercado inmobiliario (14M)
-- ------------------------------------------------------------
INSERT INTO lev_cat_12.lc_ofertasmercadoinmobiliario
 (t_id, t_basket, t_ili_tid, tipo_oferta, valor_pedido, valor_negociado,
  fecha_captura_oferta, tiempo_oferta_mercado, numero_contacto_oferente,
  nombre_oferente, lc_predio)
SELECT 14000000+o.id, 1, md5('tibacuy_lc_oferta'||o.id)::uuid,
  (SELECT e.t_id FROM lev_cat_12.lc_ofertatipo e WHERE e.ilicode=o.tipo_oferta),
  o.valor_pedido, o.valor_negociado, o.fecha_captura_oferta, o.tiempo_oferta_mercado,
  COALESCE(left(o.numero_contacto_oferente,20),'Sin dato'), COALESCE(o.nombre_oferente,'Sin dato'),
  1000000+o.gc_predio
FROM cun25805.om_ofertasmercadoinmobiliario o
JOIN mig_predio p ON p.id=o.gc_predio;

-- ------------------------------------------------------------
-- 13. Submodelo Avalúos (basket 2): ZH vigencia 2024 y tipologías
-- ------------------------------------------------------------
INSERT INTO lev_cat_12.av_zonahomogeneafisicarural
 (t_id, t_basket, t_ili_tid, codigo, codigo_zona_fisica, area_homogenea_tierra,
  disponibilidad_agua, influencia_vial, uso_actual_suelo, norma_uso_suelo, vigencia, geometria)
SELECT 18000000+z.id, 2, md5('tibacuy_zhf_rural'||z.id)::uuid,
  left(z.codigo,20), left(z.codigo_zona_fisica,20), NULLIF(z.area_homogenea_tierra,'')::numeric,
  NULL, NULL, NULL, left(z.norma_uso_suelo,250), z.vigencia,
  ST_Multi(ST_CollectionExtract(ST_MakeValid(z.geometria),3))
FROM cun25805.zhf_rural z WHERE date_part('year',z.vigencia)=2024;

INSERT INTO lev_cat_12.av_zonahomogeneafisicaurbana
 (t_id, t_basket, t_ili_tid, codigo, codigo_zona_fisica, topografia, influencia_vial,
  servicio_publico, uso_actual_suelo, norma_uso_suelo, tipificacion_construccion, vigencia, geometria)
SELECT 19000000+z.id, 2, md5('tibacuy_zhf_urbana'||z.id)::uuid,
  left(z.codigo,20), left(z.codigo_zona_fisica,20), NULL, NULL, NULL, NULL,
  left(z.norma_uso_suelo,250), NULL, z.vigencia,
  ST_Multi(ST_CollectionExtract(ST_MakeValid(z.geometria),3))
FROM cun25805.zhf_urbana z WHERE date_part('year',z.vigencia)=2024;

INSERT INTO lev_cat_12.av_zonahomogeneageoeconomicarural
 (t_id, t_basket, t_ili_tid, codigo, codigo_zona_geoeconomica, valor_hectarea,
  subzona_fisica, vigencia, geometria)
SELECT 20000000+z.id, 2, md5('tibacuy_zhg_rural'||z.id)::uuid,
  left(z.codigo,20), left(z.codigo_zona_geoeconomica,20), round(z.valor_hectarea_agropecuario,1),
  z.subzona_fisica, z.vigencia,
  ST_Multi(ST_CollectionExtract(ST_MakeValid(z.geometria),3))
FROM cun25805.zhg_rural z WHERE date_part('year',z.vigencia)=2024;

INSERT INTO lev_cat_12.av_zonahomogeneageoeconomicaurbana
 (t_id, t_basket, t_ili_tid, codigo, codigo_zona_geoeconomica, valor_metro,
  subzona_fisica, vigencia, geometria)
SELECT 21000000+z.id, 2, md5('tibacuy_zhg_urbana'||z.id)::uuid,
  left(z.codigo,20), left(z.codigo_zona_geoeconomica,20), round(z.valor_m2_catastral,1),
  z.subzona_fisica, z.vigencia,
  ST_Multi(ST_CollectionExtract(ST_MakeValid(z.geometria),3))
FROM cun25805.zhg_urbana z WHERE date_part('year',z.vigencia)=2024;

-- Tipologías con valor vigencia 2024 (solo las que existen en AV_TipologiaTipo;
-- los anexos no tienen equivalente en el submodelo de avalúos v1.2)
INSERT INTO lev_cat_12.av_tipologiaconstruccion
 (t_id, t_basket, t_ili_tid, tipo_tipologia, valor_unitario)
SELECT 22000000+v.id, 2, md5('tibacuy_av_tipologia'||v.id)::uuid,
  (SELECT e.t_id FROM lev_cat_12.av_tipologiatipo e WHERE e.ilicode=tt.text_code),
  round(v.valor_m2_catastral,1)
FROM cun25805.tb_valortipologia v
JOIN cun25805.cuc_tipologiatipo tt ON tt.id=v.tipo_tipologia
WHERE date_part('year',v.vigencia)=2024
  AND EXISTS (SELECT 1 FROM lev_cat_12.av_tipologiatipo e WHERE e.ilicode=tt.text_code);

-- ------------------------------------------------------------
-- 14. Submodelo Cartografía Catastral (basket 3)
-- ------------------------------------------------------------
INSERT INTO lev_cat_12.cc_barrio (t_id, t_basket, codigo, nombre, codigo_sector, geometria)
SELECT 23000000+id, 3, codigo, nombre, codigo_sector, ST_Multi(ST_CollectionExtract(ST_MakeValid(geometria),3))
FROM cun25805.cc_barrio WHERE geometria IS NOT NULL;

INSERT INTO lev_cat_12.cc_centropoblado (t_id, t_basket, codigo, nombre, geometria)
SELECT 24000000+id, 3, codigo, nombre, ST_Multi(ST_CollectionExtract(ST_MakeValid(geometria),3))
FROM cun25805.cc_centropoblado WHERE geometria IS NOT NULL;

INSERT INTO lev_cat_12.cc_corregimiento (t_id, t_basket, codigo, nombre, geometria)
SELECT 25000000+id, 3, codigo, nombre, ST_Multi(ST_CollectionExtract(ST_MakeValid(geometria),3))
FROM cun25805.cc_corregimiento WHERE geometria IS NOT NULL;

INSERT INTO lev_cat_12.cc_limitemunicipio (t_id, t_basket, codigo_departamento, codigo_municipio, nombre_municipio, geometria)
SELECT 26000000+id, 3, codigo_departamento, codigo_municipio, nombre_municipio, ST_Multi(ST_CollectionExtract(ST_MakeValid(geometria),3))
FROM cun25805.cc_limitemunicipio WHERE geometria IS NOT NULL;

INSERT INTO lev_cat_12.cc_localidadcomuna (t_id, t_basket, codigo, nombre, geometria)
SELECT 27000000+id, 3, codigo, nombre, ST_Multi(ST_CollectionExtract(ST_MakeValid(geometria),3))
FROM cun25805.cc_localidadcomuna WHERE geometria IS NOT NULL;

INSERT INTO lev_cat_12.cc_manzana (t_id, t_basket, codigo, codigo_barrio, nombre, geometria)
SELECT 28000000+id, 3, codigo, codigo_barrio, nombre, ST_Multi(ST_CollectionExtract(ST_MakeValid(geometria),3))
FROM cun25805.cc_manzana WHERE geometria IS NOT NULL;

INSERT INTO lev_cat_12.cc_nomenclaturavial (t_id, t_basket, tipo_via, numero_via, geometria)
SELECT 29000000+n.id, 3,
  (SELECT e.t_id FROM lev_cat_12.cc_nomenclaturavial_tipo_via e WHERE e.ilicode=tv.text_code),
  n.numero_via, ST_Multi(ST_CollectionExtract(ST_MakeValid(n.geometria),2))
FROM cun25805.cc_nomenclaturavial n
LEFT JOIN cun25805.cc_nomenclaturavial_tipo_via tv ON tv.id=n.tipo_via
WHERE n.geometria IS NOT NULL;

INSERT INTO lev_cat_12.cc_perimetrourbano (t_id, t_basket, codigo_departamento, codigo_municipio, tipo_avaluo, nombre_geografico, codigo_nombre, geometria)
SELECT 30000000+id, 3, codigo_departamento, codigo_municipio, tipo_avaluo, nombre_geografico, codigo_nombre, ST_Multi(ST_CollectionExtract(ST_MakeValid(geometria),3))
FROM cun25805.cc_perimetrourbano WHERE geometria IS NOT NULL;

INSERT INTO lev_cat_12.cc_sectorrural (t_id, t_basket, codigo, geometria)
SELECT 31000000+id, 3, codigo, ST_Multi(ST_CollectionExtract(ST_MakeValid(geometria),3))
FROM cun25805.cc_sectorrural WHERE geometria IS NOT NULL;

INSERT INTO lev_cat_12.cc_sectorurbano (t_id, t_basket, codigo, geometria)
SELECT 32000000+id, 3, codigo, ST_Multi(ST_CollectionExtract(ST_MakeValid(geometria),3))
FROM cun25805.cc_sectorurbano WHERE geometria IS NOT NULL;

INSERT INTO lev_cat_12.cc_vereda (t_id, t_basket, codigo, nombre, codigo_sector, geometria)
SELECT 33000000+id, 3, codigo, nombre, codigo_sector, ST_Multi(ST_CollectionExtract(ST_MakeValid(geometria),3))
FROM cun25805.cc_vereda WHERE geometria IS NOT NULL;

-- Ajustar secuencia t_id por encima del máximo usado
SELECT setval('lev_cat_12.t_ili2db_seq', 40000000, false);

COMMIT;

-- Resumen
SELECT 'lc_predio' tabla, count(*) FROM lev_cat_12.lc_predio
UNION ALL SELECT 'extdireccion', count(*) FROM lev_cat_12.extdireccion
UNION ALL SELECT 'lc_terreno', count(*) FROM lev_cat_12.lc_terreno
UNION ALL SELECT 'lc_construccion', count(*) FROM lev_cat_12.lc_construccion
UNION ALL SELECT 'lc_unidadconstruccion', count(*) FROM lev_cat_12.lc_unidadconstruccion
UNION ALL SELECT 'lc_caracteristicas', count(*) FROM lev_cat_12.lc_caracteristicasunidadconstruccion
UNION ALL SELECT 'lc_tipologia', count(*) FROM lev_cat_12.lc_tipologiaconstruccion
UNION ALL SELECT 'lc_calnoconv', count(*) FROM lev_cat_12.lc_calificacionnoconvencional
UNION ALL SELECT 'lc_interesado', count(*) FROM lev_cat_12.lc_interesado
UNION ALL SELECT 'lc_agrupacion', count(*) FROM lev_cat_12.lc_agrupacioninteresados
UNION ALL SELECT 'col_miembros', count(*) FROM lev_cat_12.col_miembros
UNION ALL SELECT 'lc_derecho', count(*) FROM lev_cat_12.lc_derecho
UNION ALL SELECT 'lc_fuenteadministrativa', count(*) FROM lev_cat_12.lc_fuenteadministrativa
UNION ALL SELECT 'col_rrrfuente', count(*) FROM lev_cat_12.col_rrrfuente
UNION ALL SELECT 'col_uebaunit', count(*) FROM lev_cat_12.col_uebaunit
UNION ALL SELECT 'lc_datosadicionales', count(*) FROM lev_cat_12.lc_datosadicionaleslevantamientocatastral
UNION ALL SELECT 'lc_ofertas', count(*) FROM lev_cat_12.lc_ofertasmercadoinmobiliario
UNION ALL SELECT 'av_zhf_rural', count(*) FROM lev_cat_12.av_zonahomogeneafisicarural
UNION ALL SELECT 'av_zhf_urbana', count(*) FROM lev_cat_12.av_zonahomogeneafisicaurbana
UNION ALL SELECT 'av_zhg_rural', count(*) FROM lev_cat_12.av_zonahomogeneageoeconomicarural
UNION ALL SELECT 'av_zhg_urbana', count(*) FROM lev_cat_12.av_zonahomogeneageoeconomicaurbana
UNION ALL SELECT 'av_tipologia', count(*) FROM lev_cat_12.av_tipologiaconstruccion
UNION ALL SELECT 'cc_total', (SELECT count(*) FROM lev_cat_12.cc_barrio)+(SELECT count(*) FROM lev_cat_12.cc_centropoblado)
 +(SELECT count(*) FROM lev_cat_12.cc_corregimiento)+(SELECT count(*) FROM lev_cat_12.cc_limitemunicipio)
 +(SELECT count(*) FROM lev_cat_12.cc_localidadcomuna)+(SELECT count(*) FROM lev_cat_12.cc_manzana)
 +(SELECT count(*) FROM lev_cat_12.cc_nomenclaturavial)+(SELECT count(*) FROM lev_cat_12.cc_perimetrourbano)
 +(SELECT count(*) FROM lev_cat_12.cc_sectorrural)+(SELECT count(*) FROM lev_cat_12.cc_sectorurbano)
 +(SELECT count(*) FROM lev_cat_12.cc_vereda)
ORDER BY 1;

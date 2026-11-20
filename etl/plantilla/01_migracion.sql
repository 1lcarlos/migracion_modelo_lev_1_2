-- ============================================================
-- ETL plantilla: <esq> (gestor) -> lev_cat_12 (LADM-COL Lev Cat v1.2)
-- Genera datos listos para exportar a XTF con ili2pg.
-- Parámetros psql (-v): esq, mun, prefijo, vigencia, razon_municipio, nit_municipio
--   esq_tipologia (opcional): esquema del que se leen tb_valortipologia/cuc_tipologiatipo
--   (por defecto esq; Sutatausa: backup 2026 cargado como esquema auxiliar)
--   psql -v ON_ERROR_STOP=1 -v esq=cun25862 -v mun=vergara -v prefijo=VERGARA_ \
--        -v vigencia=2023 -v razon_municipio= -v nit_municipio= -f etl/plantilla/01_migracion.sql
-- Estrategia de IDs: t_id = offset_cien_millones + id_origen (exige id origen < 100.000.000).
-- t_ili_tid: UUID determinístico md5(mun||'_'||tabla||id) para tópicos con OID UUID.
-- ============================================================
\if :{?razon_municipio} \else \set razon_municipio '' \endif
\if :{?nit_municipio} \else \set nit_municipio '' \endif
\if :{?esq_tipologia} \else \set esq_tipologia :esq \endif

-- Guarda: la estrategia de offsets requiere id origen < 100.000.000 en toda tabla migrada
SELECT set_config('mig.esq', :'esq', false);
DO $$
DECLARE r record; mx bigint; esq text := current_setting('mig.esq');
BEGIN
  FOR r IN SELECT table_name FROM information_schema.columns
           WHERE table_schema = esq AND column_name = 'id'
             AND table_name IN ('gc_predio','extdireccion','gc_terreno','gc_construccion',
               'gc_unidadconstruccion','gc_caracteristicasunidadconstruccion',
               'cuc_tipologiaconstruccion','cuc_calificacionnoconvencional','gc_interesado',
               'gc_agrupacioninteresados','gc_derecho','gc_fuenteadministrativa',
               'dlc_datosadicionaleslevantamientocatastral','om_ofertasmercadoinmobiliario',
               'col_uebaunit','col_rrrfuente','col_miembros','zhf_rural','zhf_urbana',
               'zhg_rural','zhg_urbana','tb_valortipologia','cc_barrio','cc_centropoblado',
               'cc_corregimiento','cc_limitemunicipio','cc_localidadcomuna','cc_manzana',
               'cc_nomenclaturavial','cc_perimetrourbano','cc_sectorrural','cc_sectorurbano','cc_vereda',
               'gc_lindero','gc_puntolindero','gc_puntolevantamiento','col_puntoccl','col_masccl',
               'col_menosccl','gc_fuenteespacial','extarchivo','gc_predio_informalidad',
               'extreferenciaregistralsistemaantiguo','gc_datosphcondominio','gc_servidumbretransito',
               'gc_prediocopropiedad')
  LOOP
    EXECUTE format('SELECT max(id) FROM %I.%I', esq, r.table_name) INTO mx;
    IF mx >= 100000000 THEN
      RAISE EXCEPTION 'Tabla %.% tiene id % >= 100.000.000: la estrategia de offsets no aplica', esq, r.table_name, mx;
    END IF;
  END LOOP;
END $$;

-- public.fx_dom y public.fx_hom se definen en 00_homologaciones.sql (correr antes)
-- Local_Id y Espacio_De_Nombres son MANDATORY: vacío o NULL en el origen -> id / nombre de la clase
-- (Chaguaní: 2 fuentes con local_id ''; ili2pg lo exporta, ilivalidator lo rechaza)

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
  lev_cat_12.cc_sectorrural, lev_cat_12.cc_sectorurbano, lev_cat_12.cc_vereda,
  lev_cat_12.lc_lindero, lev_cat_12.lc_puntolindero, lev_cat_12.lc_puntolevantamiento,
  lev_cat_12.col_puntoccl, lev_cat_12.col_masccl, lev_cat_12.col_menosccl,
  lev_cat_12.lc_fuenteespacial, lev_cat_12.col_baunitfuente, lev_cat_12.extarchivo,
  lev_cat_12.lc_predio_informalidad, lev_cat_12.extreferenciaregistralsistemaantiguo,
  lev_cat_12.lc_contactovisita, lev_cat_12.lc_estructuranovedadnumeropredial,
  lev_cat_12.lc_datosphcondominio, lev_cat_12.lc_servidumbretransito,
  lev_cat_12.lc_predio_copropiedad
  CASCADE;
DELETE FROM lev_cat_12.t_ili2db_basket;
DELETE FROM lev_cat_12.t_ili2db_dataset;

-- ------------------------------------------------------------
-- Dataset y baskets
-- ------------------------------------------------------------
INSERT INTO lev_cat_12.t_ili2db_dataset(t_id, datasetname) VALUES (1, :'mun'||'_'||:'vigencia');
INSERT INTO lev_cat_12.t_ili2db_basket(t_id, dataset, topic, t_ili_tid, attachmentkey) VALUES
 (1,1,'Modelo_Aplicacion_LADMCOL_Lev_Cat_V1_2.Levantamiento_Catastral', md5(:'mun'||'_basket_lev')::uuid::text,'etl_'||:'mun'||'_'||:'vigencia'),
 (2,1,'Submodelo_Avaluos_V1_2.Avaluos',                                 md5(:'mun'||'_basket_av')::uuid::text,'etl_'||:'mun'||'_'||:'vigencia'),
 (3,1,'Submodelo_Cartografia_Catastral_V1_2.LimitesOperativosCatastro', md5(:'mun'||'_basket_cc')::uuid::text,'etl_'||:'mun'||'_'||:'vigencia');

-- ------------------------------------------------------------
-- Universo de migración (filtro por vigencia y exclusión de huérfanos)
-- ------------------------------------------------------------
DROP TABLE IF EXISTS mig_predio, mig_terreno, mig_constr, mig_uc, mig_caract, mig_fadm, mig_fesp, mig_serv,
  mig_agrup, mig_interesado, mig_lindero, mig_puntolindero, mig_cvu,
  map_puntotipo, map_acuerdo, map_foto, map_metodo, map_puntolev;

-- Predios con avalúo de la vigencia
CREATE TEMP TABLE mig_predio AS
SELECT p.*, a.avaluo_catastral AS avaluo_vigencia,
       :'prefijo'||lpad((row_number() OVER (ORDER BY p.numero_predial))::text,5,'0') AS id_operacion
FROM :"esq".gc_predio p
JOIN :"esq".extavaluo a ON a.gc_predio_avaluo = p.id AND date_part('year',a.vigencia)=:vigencia;

-- Terrenos ligados a un predio migrado
CREATE TEMP TABLE mig_terreno AS
SELECT DISTINCT t.id FROM :"esq".gc_terreno t
JOIN :"esq".col_uebaunit u ON u.ue_gc_terreno=t.id
JOIN mig_predio p ON p.id=u.unidad;

-- Servidumbres de tránsito ligadas a un predio migrado
CREATE TEMP TABLE mig_serv AS
SELECT DISTINCT s.id FROM :"esq".gc_servidumbretransito s
JOIN :"esq".col_uebaunit u ON u.ue_gc_servidumbretransito=s.id
JOIN mig_predio p ON p.id=u.unidad;

-- Unidades de construcción válidas: con predio directo, con construcción y características
CREATE TEMP TABLE mig_uc AS
SELECT DISTINCT uc.id FROM :"esq".gc_unidadconstruccion uc
JOIN :"esq".col_uebaunit u ON u.ue_gc_unidadconstruccion=uc.id
JOIN mig_predio p ON p.id=u.unidad
WHERE uc.gc_construccion IS NOT NULL AND uc.gc_caracteristicasunidadconstruccion IS NOT NULL;

-- Construcciones: con predio directo o rescatadas vía sus unidades migradas
CREATE TEMP TABLE mig_constr AS
SELECT DISTINCT c.id FROM :"esq".gc_construccion c
LEFT JOIN :"esq".col_uebaunit u ON u.ue_gc_construccion=c.id
LEFT JOIN mig_predio p ON p.id=u.unidad
WHERE p.id IS NOT NULL
   OR EXISTS (SELECT 1 FROM :"esq".gc_unidadconstruccion uc JOIN mig_uc m ON m.id=uc.id WHERE uc.gc_construccion=c.id);

-- Características referenciadas por unidades migradas
CREATE TEMP TABLE mig_caract AS
SELECT DISTINCT uc.gc_caracteristicasunidadconstruccion AS id
FROM :"esq".gc_unidadconstruccion uc JOIN mig_uc m ON m.id=uc.id;

-- Fuentes administrativas ligadas a derechos de predios migrados
CREATE TEMP TABLE mig_fadm AS
SELECT DISTINCT f.id FROM :"esq".gc_fuenteadministrativa f
JOIN :"esq".col_rrrfuente r ON r.fuente_administrativa=f.id
JOIN :"esq".gc_derecho d ON d.id=r.rrr_gc_derecho
JOIN mig_predio p ON p.id=d.baunit
UNION
-- ... y las ligadas directamente al predio (col_unidadfuente; Nemocón: única fuente de 2.903 derechos)
SELECT f.id FROM :"esq".gc_fuenteadministrativa f
JOIN :"esq".col_unidadfuente u ON u.fuente_administrativa=f.id
JOIN mig_predio p ON p.id=u.unidad;

-- Comienzo_Vida_Util_Version es MANDATORY. Si falta en el origen (10 de 25 municipios del lote; p. ej.
-- Quipile 30 terrenos) se hereda la fecha del predio de la unidad espacial (la menor si hay varios) o,
-- sin predio directo, el 1 de enero de la vigencia (misma regla que las servidumbres). Métrica en 03.
CREATE TEMP TABLE mig_cvu AS
SELECT 'terreno'::text AS clase, u.ue_gc_terreno AS id, min(p.comienzo_vida_util_version) AS cvu
FROM :"esq".col_uebaunit u JOIN mig_predio p ON p.id=u.unidad WHERE u.ue_gc_terreno IS NOT NULL GROUP BY 2
UNION ALL
SELECT 'construccion', u.ue_gc_construccion, min(p.comienzo_vida_util_version)
FROM :"esq".col_uebaunit u JOIN mig_predio p ON p.id=u.unidad WHERE u.ue_gc_construccion IS NOT NULL GROUP BY 2
UNION ALL
SELECT 'uc', u.ue_gc_unidadconstruccion, min(p.comienzo_vida_util_version)
FROM :"esq".col_uebaunit u JOIN mig_predio p ON p.id=u.unidad WHERE u.ue_gc_unidadconstruccion IS NOT NULL GROUP BY 2;
CREATE INDEX ON mig_cvu(clase, id);

-- Titulares: solo los de derechos de predios migrados (agrupaciones y sus miembros incluidos).
-- Antes se migraba todo gc_interesado del municipio: quedaban personas sin derecho en el XTF.
CREATE TEMP TABLE mig_agrup AS
SELECT DISTINCT d.interesado_gc_agrupacioninteresados AS id FROM :"esq".gc_derecho d
JOIN mig_predio p ON p.id=d.baunit WHERE d.interesado_gc_agrupacioninteresados IS NOT NULL;

CREATE TEMP TABLE mig_interesado AS
SELECT d.interesado_gc_interesado AS id FROM :"esq".gc_derecho d
JOIN mig_predio p ON p.id=d.baunit WHERE d.interesado_gc_interesado IS NOT NULL
UNION
SELECT m.interesado_gc_interesado FROM :"esq".col_miembros m JOIN mig_agrup a ON a.id=m.agrupacion
WHERE m.interesado_gc_interesado IS NOT NULL;

-- ------------------------------------------------------------
-- 1. LC_Predio  (t_id = 1M + id)
-- ------------------------------------------------------------
INSERT INTO lev_cat_12.lc_predio
 (t_id, t_basket, t_ili_tid, departamento, municipio, id_operacion, tiene_fmi, codigo_orip,
  matricula_inmobiliaria, numero_predial, numero_predial_anterior, codigo_homologado,
  interrelacionado, codigo_homologado_fmi, nupre, avaluo_catastral, valor_referencia,
  tipo, condicion_predio, destinacion_economica, clase_suelo, categoria_suelo, nombre,
  comienzo_vida_util_version, fin_vida_util_version, espacio_de_nombres, local_id)
SELECT 100000000+p.id, 1, md5(:'mun'||'_lc_predio'||p.id)::uuid,
  p.departamento, p.municipio, p.id_operacion,
  COALESCE(p.tiene_fmi,false), p.codigo_orip, p.matricula_inmobiliaria,
  p.numero_predial, left(p.numero_predial_anterior,20), p.nupre,
  COALESCE(p.interrelacionado,false), COALESCE(p.nupre_fmi,false),
  CASE WHEN COALESCE(p.nupre_fmi,false) THEN p.nupre END,
  p.avaluo_vigencia,
  (SELECT CASE WHEN v.valor ~ '^[0-9]+(\.[0-9]+)?$' THEN round(v.valor::numeric,1) END
     FROM :"esq".extvalor v WHERE v.gc_predio_valor_referencia=p.id ORDER BY v.fecha DESC NULLS LAST, v.id DESC LIMIT 1),
  (SELECT e.t_id FROM lev_cat_12.col_unidadadministrativabasicatipo e
    WHERE e.thisclass='Modelo_Aplicacion_LADMCOL_Lev_Cat_V1_2.LC_PredioTipo'
      AND e.ilicode='Predio.'||COALESCE(dt.text_code,'Privado')),
  -- Homologaciones en config/homologaciones.csv (p. ej. Mejora -> Informal, Nemocón)
  (SELECT e.t_id FROM lev_cat_12.lc_condicionprediotipo e
    WHERE e.ilicode=public.fx_hom('lc_condicionprediotipo', dc.text_code)),
  (SELECT e.t_id FROM lev_cat_12.lc_destinacioneconomicatipo e WHERE e.ilicode=dd.text_code),
  (SELECT e.t_id FROM lev_cat_12.lc_clasesuelotipo e WHERE e.ilicode=ds.text_code),
  (SELECT e.t_id FROM lev_cat_12.lc_categoriasuelotipo e WHERE e.ilicode=dcat.text_code),
  p.nombre,
  p.comienzo_vida_util_version, p.fin_vida_util_version,
  COALESCE(NULLIF(btrim(p.espacio_de_nombres),''),'LC_PREDIO'), COALESCE(NULLIF(btrim(p.local_id),''), p.id::text)
FROM mig_predio p
LEFT JOIN :"esq".gc_prediotipo dt ON dt.id=p.tipo
LEFT JOIN :"esq".gc_condicionprediotipo dc ON dc.id=p.condicion_predio
LEFT JOIN :"esq".gc_destinacioneconomicatipo dd ON dd.id=p.destinacion_economica
LEFT JOIN :"esq".gc_clasesuelotipo ds ON ds.id=p.clase_suelo
LEFT JOIN :"esq".gc_categoriasuelotipo dcat ON dcat.id=p.categoria_suelo;

-- ------------------------------------------------------------
-- 2. Direcciones del predio (estructura ExtDireccion, t_id = 2M + id)
-- ------------------------------------------------------------
INSERT INTO lev_cat_12.extdireccion
 (t_id, t_basket, t_seq, tipo_direccion, es_direccion_principal, localizacion, codigo_postal,
  clase_via_principal, valor_via_principal, letra_via_principal, sector_ciudad,
  valor_via_generadora, letra_via_generadora, numero_predio, sector_predio,
  complemento, nombre_predio, lc_predio_direccion)
SELECT 200000000+d.id, 1,
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
  100000000+d.gc_predio_direccion
FROM :"esq".extdireccion d
JOIN mig_predio p ON p.id=d.gc_predio_direccion
LEFT JOIN :"esq".extdireccion_tipo_direccion td ON td.id=d.tipo_direccion
LEFT JOIN :"esq".extdireccion_clase_via_principal cv ON cv.id=d.clase_via_principal
LEFT JOIN :"esq".extdireccion_sector_ciudad sc ON sc.id=d.sector_ciudad
LEFT JOIN :"esq".extdireccion_sector_predio sp ON sp.id=d.sector_predio;

-- ------------------------------------------------------------
-- 3. LC_Terreno (t_id = 3M + id)
-- ------------------------------------------------------------
INSERT INTO lev_cat_12.lc_terreno
 (t_id, t_basket, t_ili_tid, area_terreno, avaluo_terreno, manzana_vereda_codigo,
  geometria, etiqueta, comienzo_vida_util_version, fin_vida_util_version,
  espacio_de_nombres, local_id)
SELECT 300000000+t.id, 1, md5(:'mun'||'_lc_terreno'||t.id)::uuid,
  -- area_terreno es MANDATORY: si el origen no la trae se usa el área geométrica (Nemocón: 1 terreno)
  COALESCE(round(t.area,1), round(ST_Area(t.geometria)::numeric,1)), NULL, left(t.codigo,17),
  ST_Multi(ST_CollectionExtract(ST_MakeValid(t.geometria),3)),
  t.etiqueta, COALESCE(t.comienzo_vida_util_version, (SELECT x.cvu FROM mig_cvu x WHERE x.clase='terreno' AND x.id=t.id), make_date(:vigencia,1,1)), t.fin_vida_util_version,
  COALESCE(NULLIF(btrim(t.espacio_de_nombres),''),'LC_TERRENO'), COALESCE(NULLIF(btrim(t.local_id),''), t.id::text)
FROM :"esq".gc_terreno t JOIN mig_terreno m ON m.id=t.id;

-- ------------------------------------------------------------
-- 4. LC_Construccion (t_id = 4M + id)
-- ------------------------------------------------------------
INSERT INTO lev_cat_12.lc_construccion
 (t_id, t_basket, t_ili_tid, identificador, tipo_construccion, tipo_dominio,
  numero_pisos, numero_sotanos, numero_mezanines, numero_semisotanos, anio_construccion,
  avaluo_construccion, valor_referencia_construccion, area_construccion, altura,
  observaciones, geometria, etiqueta,
  comienzo_vida_util_version, fin_vida_util_version, espacio_de_nombres, local_id)
SELECT 400000000+c.id, 1, md5(:'mun'||'_lc_construccion'||c.id)::uuid,
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
  COALESCE(c.comienzo_vida_util_version, (SELECT x.cvu FROM mig_cvu x WHERE x.clase='construccion' AND x.id=c.id), make_date(:vigencia,1,1)), c.fin_vida_util_version,
  COALESCE(NULLIF(btrim(c.espacio_de_nombres),''),'LC_CONSTRUCCION'), COALESCE(NULLIF(btrim(c.local_id),''), c.id::text)
FROM :"esq".gc_construccion c
JOIN mig_constr m ON m.id=c.id
LEFT JOIN :"esq".gc_construcciontipo tc ON tc.id=c.tipo_construccion
LEFT JOIN :"esq".gc_dominioconstrucciontipo tdo ON tdo.id=c.tipo_dominio;

-- ------------------------------------------------------------
-- 5. LC_CaracteristicasUnidadConstruccion (t_id = 6M + id)
-- ------------------------------------------------------------
INSERT INTO lev_cat_12.lc_caracteristicasunidadconstruccion
 (t_id, t_basket, t_ili_tid, identificador, tipo_construccion, tipo_dominio,
  tipo_unidad_construccion, tipo_planta, total_habitaciones, total_banios, total_locales,
  total_plantas, uso, anio_construccion, avaluo_unidad_construccion, area_construida,
  area_privada_construida, observaciones,
  comienzo_vida_util_version, fin_vida_util_version, espacio_de_nombres, local_id)
SELECT 600000000+k.id, 1, md5(:'mun'||'_lc_caract'||k.id)::uuid,
  k.identificador,
  (SELECT e.t_id FROM lev_cat_12.lc_construcciontipo e WHERE e.ilicode=tc.text_code),
  (SELECT e.t_id FROM lev_cat_12.lc_dominioconstrucciontipo e WHERE e.ilicode=tdo.text_code),
  (SELECT e.t_id FROM lev_cat_12.lc_unidadconstrucciontipo e WHERE e.ilicode=tuc.text_code),
  (SELECT e.t_id FROM lev_cat_12.lc_construccionplantatipo e WHERE e.ilicode=tp.text_code),
  k.total_habitaciones, k.total_banios, k.total_locales, k.total_plantas,
  (SELECT e.t_id FROM lev_cat_12.lc_usouconstipo e WHERE e.ilicode=us.text_code),
  CASE WHEN k.anio_construccion BETWEEN 1512 AND 2500 THEN k.anio_construccion END,
  NULL, round(k.area,1), round(k.area_privada_construida,1), k.observacion,
  COALESCE(k.comienzo_vida_util_version, make_date(:vigencia,1,1)), k.fin_vida_util_version,
  COALESCE(NULLIF(btrim(k.espacio_de_nombres),''),'LC_CARACTERISTICASUNIDADCONSTRUCCION'), COALESCE(NULLIF(btrim(k.local_id),''), k.id::text)
FROM :"esq".gc_caracteristicasunidadconstruccion k
JOIN mig_caract m ON m.id=k.id
LEFT JOIN :"esq".gc_construcciontipo tc ON tc.id=k.tipo_construccion
LEFT JOIN :"esq".gc_dominioconstrucciontipo tdo ON tdo.id=k.tipo_dominio
LEFT JOIN :"esq".gc_unidadconstrucciontipo tuc ON tuc.id=k.tipo_unidad_construccion
LEFT JOIN :"esq".gc_construccionplantatipo tp ON tp.id=k.tipo_planta
LEFT JOIN :"esq".gc_usouconstipo us ON us.id=k.uso;

-- ------------------------------------------------------------
-- 6. LC_UnidadConstruccion (t_id = 5M + id)
-- ------------------------------------------------------------
INSERT INTO lev_cat_12.lc_unidadconstruccion
 (t_id, t_basket, t_ili_tid, planta_ubicacion, area_construida, altura, geometria,
  lc_caracteristicasunidadconstruccion, lc_construccion, etiqueta,
  comienzo_vida_util_version, fin_vida_util_version, espacio_de_nombres, local_id)
SELECT 500000000+uc.id, 1, md5(:'mun'||'_lc_uc'||uc.id)::uuid,
  COALESCE(uc.planta_ubicacion,1), round(uc.area,1),
  CASE WHEN uc.altura >= 1 THEN round(uc.altura)::int END,
  NULLIF(ST_Multi(ST_CollectionExtract(ST_MakeValid(uc.geometria),3)),
         ST_SetSRID('MULTIPOLYGON EMPTY'::geometry, 9377)),
  600000000+uc.gc_caracteristicasunidadconstruccion, 400000000+uc.gc_construccion,
  uc.etiqueta,
  COALESCE(uc.comienzo_vida_util_version, (SELECT x.cvu FROM mig_cvu x WHERE x.clase='uc' AND x.id=uc.id), make_date(:vigencia,1,1)), uc.fin_vida_util_version,
  COALESCE(NULLIF(btrim(uc.espacio_de_nombres),''),'LC_UNIDADCONSTRUCCION'), COALESCE(NULLIF(btrim(uc.local_id),''), uc.id::text)
FROM :"esq".gc_unidadconstruccion uc JOIN mig_uc m ON m.id=uc.id;

-- ------------------------------------------------------------
-- 7. Calificaciones (tipología 7M, no convencional 8M)
-- ------------------------------------------------------------
INSERT INTO lev_cat_12.lc_tipologiaconstruccion
 (t_id, t_basket, t_ili_tid, tipo_tipologia, cual, lc_unidad_construccion)
SELECT 700000000+t.id, 1, md5(:'mun'||'_lc_tipologia'||t.id)::uuid,
  (SELECT e.t_id FROM lev_cat_12.lc_tipologiatipo e WHERE e.ilicode=tt.text_code),
  NULL, 600000000+t.gc_caracteristicasunidadconstruccion
FROM :"esq".cuc_tipologiaconstruccion t
JOIN mig_caract m ON m.id=t.gc_caracteristicasunidadconstruccion
LEFT JOIN :"esq".cuc_tipologiatipo tt ON tt.id=t.tipo_tipologia;

INSERT INTO lev_cat_12.lc_calificacionnoconvencional
 (t_id, t_basket, t_ili_tid, tipo_anexo, lc_unidad_construccion)
SELECT 800000000+n.id, 1, md5(:'mun'||'_lc_calnoconv'||n.id)::uuid,
  (SELECT e.t_id FROM lev_cat_12.lc_anexotipo e WHERE e.ilicode=ta.text_code),
  600000000+n.gc_caracteristicasunidadconstruccion
FROM :"esq".cuc_calificacionnoconvencional n
JOIN mig_caract m ON m.id=n.gc_caracteristicasunidadconstruccion
LEFT JOIN :"esq".cuc_anexotipo ta ON ta.id=n.tipo_anexo;

-- ------------------------------------------------------------
-- 8. Interesados (9M) y agrupaciones (10M) + miembros (17M)
-- ------------------------------------------------------------
INSERT INTO lev_cat_12.lc_interesado
 (t_id, t_basket, t_ili_tid, tipo, tipo_documento, documento_identidad,
  primer_nombre, segundo_nombre, primer_apellido, segundo_apellido, sexo, grupo_etnico,
  razon_social, estado_civil, nombre,
  comienzo_vida_util_version, fin_vida_util_version, espacio_de_nombres, local_id)
SELECT 900000000+i.id, 1, md5(:'mun'||'_lc_interesado'||i.id)::uuid,
  (SELECT e.t_id FROM lev_cat_12.lc_interesadotipo e WHERE e.ilicode=ti.text_code),
  -- Homologaciones en config/homologaciones.csv (p. ej. NUIP -> Registro_Civil, Tibacuy)
  (SELECT e.t_id FROM lev_cat_12.lc_interesadodocumentotipo e
    WHERE e.ilicode = public.fx_hom('lc_interesadodocumentotipo', td.text_code)),
  -- documento_identidad es MANDATORY: si viene vacío y la razón social es la del municipio
  -- se usa el NIT del municipio (parámetro); en otro caso placeholder 'Sin_Dato'
  COALESCE(NULLIF(btrim(i.documento_identidad),''),
    CASE WHEN :'nit_municipio' <> '' AND :'razon_municipio' <> '' AND i.razon_social ILIKE '%'||:'razon_municipio'||'%'
         THEN :'nit_municipio' END,
    'Sin_Dato'),
  i.primer_nombre, i.segundo_nombre, i.primer_apellido, i.segundo_apellido,
  -- Homologaciones en config/homologaciones.csv (Otro, No_Binario -> Sin_Determinar)
  (SELECT e.t_id FROM lev_cat_12.lc_sexotipo e
   WHERE e.ilicode=public.fx_hom('lc_sexotipo', sx.text_code)),
  (SELECT e.t_id FROM lev_cat_12.lc_grupoetnicotipo e WHERE e.ilicode=ge.text_code),
  i.razon_social,
  (SELECT e.t_id FROM lev_cat_12.lc_estadociviltipo e WHERE e.ilicode=ec.text_code),
  i.nombre,
  COALESCE(i.comienzo_vida_util_version, make_date(:vigencia,1,1)), i.fin_vida_util_version,
  COALESCE(NULLIF(btrim(i.espacio_de_nombres),''),'LC_INTERESADO'), COALESCE(NULLIF(btrim(i.local_id),''), i.id::text)
FROM :"esq".gc_interesado i
JOIN mig_interesado mi ON mi.id=i.id
LEFT JOIN :"esq".gc_interesadotipo ti ON ti.id=i.tipo
LEFT JOIN :"esq".gc_interesadodocumentotipo td ON td.id=i.tipo_documento
LEFT JOIN :"esq".gc_sexotipo sx ON sx.id=i.sexo
LEFT JOIN :"esq".gc_grupoetnicotipo ge ON ge.id=i.grupo_etnico
LEFT JOIN :"esq".gc_estadociviltipo ec ON ec.id=i.estado_civil;

INSERT INTO lev_cat_12.lc_agrupacioninteresados
 (t_id, t_basket, t_ili_tid, tipo, nombre,
  comienzo_vida_util_version, fin_vida_util_version, espacio_de_nombres, local_id)
SELECT 1000000000+a.id, 1, md5(:'mun'||'_lc_agrupacion'||a.id)::uuid,
  (SELECT e.t_id FROM lev_cat_12.col_grupointeresadotipo e WHERE e.ilicode=tg.text_code),
  a.nombre,
  COALESCE(a.comienzo_vida_util_version, make_date(:vigencia,1,1)), a.fin_vida_util_version,
  COALESCE(NULLIF(btrim(a.espacio_de_nombres),''),'LC_AGRUPACIONINTERESADOS'), COALESCE(NULLIF(btrim(a.local_id),''), a.id::text)
FROM :"esq".gc_agrupacioninteresados a
JOIN mig_agrup ma ON ma.id=a.id
LEFT JOIN :"esq".col_grupointeresadotipo tg ON tg.id=a.tipo;

INSERT INTO lev_cat_12.col_miembros
 (t_id, t_basket, interesado_lc_interesado, agrupacion, participacion)
SELECT 1700000000+m.id, 1, 900000000+m.interesado_gc_interesado, 1000000000+m.agrupacion, m.participacion
FROM :"esq".col_miembros m
JOIN mig_agrup ma ON ma.id=m.agrupacion
WHERE m.interesado_gc_interesado IS NOT NULL;

-- ------------------------------------------------------------
-- 9. LC_Derecho (11M), LC_FuenteAdministrativa (12M), col_rrrfuente (16M)
-- ------------------------------------------------------------
INSERT INTO lev_cat_12.lc_derecho
 (t_id, t_basket, t_ili_tid, tipo, fraccion_derecho, fecha_inicio_tenencia, descripcion,
  interesado_lc_interesado, interesado_lc_agrupacioninteresados, unidad,
  comienzo_vida_util_version, fin_vida_util_version, espacio_de_nombres, local_id)
SELECT 1100000000+d.id, 1, md5(:'mun'||'_lc_derecho'||d.id)::uuid,
  (SELECT e.t_id FROM lev_cat_12.lc_derechotipo e WHERE e.ilicode=dt.text_code),
  d.fraccion_derecho, d.fecha_inicio_tenencia, d.descripcion,
  CASE WHEN d.interesado_gc_interesado IS NOT NULL THEN 900000000+d.interesado_gc_interesado
       -- sin interesado ni agrupación en el origen: interesado placeholder (53·10⁸ + id derecho, ver abajo)
       WHEN d.interesado_gc_agrupacioninteresados IS NULL THEN 5300000000+d.id END,
  CASE WHEN d.interesado_gc_agrupacioninteresados IS NOT NULL THEN 1000000000+d.interesado_gc_agrupacioninteresados END,
  100000000+d.baunit,
  COALESCE(d.comienzo_vida_util_version, p.comienzo_vida_util_version, make_date(:vigencia,1,1)), d.fin_vida_util_version,
  COALESCE(NULLIF(btrim(d.espacio_de_nombres),''),'LC_DERECHO'), COALESCE(NULLIF(btrim(d.local_id),''), d.id::text)
FROM :"esq".gc_derecho d
JOIN mig_predio p ON p.id=d.baunit
LEFT JOIN :"esq".gc_derechotipo dt ON dt.id=d.tipo;

-- Interesado placeholder 'SIN DATO' para derechos sin titular en el origen (Nemocón: 1, predio mejora).
-- El modelo exige titular en el derecho y >=1 derecho por predio. Decisión del usuario 2026-10-14.
INSERT INTO lev_cat_12.lc_interesado
 (t_id, t_basket, t_ili_tid, tipo, tipo_documento, documento_identidad, primer_nombre, nombre,
  comienzo_vida_util_version, espacio_de_nombres, local_id)
SELECT 5300000000+d.id, 1, md5(:'mun'||'_lc_interesado_sin_dato'||d.id)::uuid,
  (SELECT e.t_id FROM lev_cat_12.lc_interesadotipo e WHERE e.ilicode='Persona_Natural'),
  (SELECT e.t_id FROM lev_cat_12.lc_interesadodocumentotipo e WHERE e.ilicode='Secuencial'),
  'Sin_Dato', 'SIN DATO', 'SIN DATO',
  COALESCE(d.comienzo_vida_util_version, p.comienzo_vida_util_version, make_date(:vigencia,1,1)), 'LC_INTERESADO', 'SIN_DATO_'||d.id
FROM :"esq".gc_derecho d JOIN mig_predio p ON p.id=d.baunit
WHERE d.interesado_gc_interesado IS NULL AND d.interesado_gc_agrupacioninteresados IS NULL;

INSERT INTO lev_cat_12.lc_fuenteadministrativa
 (t_id, t_basket, t_ili_tid, tipo, ente_emisor, observacion, numero_fuente,
  estado_disponibilidad, tipo_principal, fecha_documento_fuente, espacio_de_nombres, local_id)
SELECT 1200000000+f.id, 1, md5(:'mun'||'_lc_fadm'||f.id)::uuid,
  (SELECT e.t_id FROM lev_cat_12.col_fuenteadministrativatipo e
    WHERE e.thisclass='Modelo_Aplicacion_LADMCOL_Lev_Cat_V1_2.LC_FuenteAdministrativaTipo'
      AND e.ilicode=tf.text_code),
  f.ente_emisor, f.descripcion, left(f.numero_fuente,150),
  (SELECT e.t_id FROM lev_cat_12.col_estadodisponibilidadtipo e WHERE e.ilicode=ed.text_code),
  -- Regla tomada del XTF de referencia de Vergara: estado Desconocido -> forma de presentación 'Otro'
  CASE WHEN ed.text_code = 'Desconocido' THEN public.fx_dom('ci_forma_presentacion_codigo','Otro') END,
  f.fecha_documento_fuente,
  COALESCE(NULLIF(btrim(f.espacio_de_nombres),''),'LC_FUENTEADMINISTRATIVA'), COALESCE(NULLIF(btrim(f.local_id),''), f.id::text)
FROM :"esq".gc_fuenteadministrativa f
JOIN mig_fadm m ON m.id=f.id
LEFT JOIN :"esq".gc_fuenteadministrativatipo tf ON tf.id=f.tipo
LEFT JOIN :"esq".col_estadodisponibilidadtipo ed ON ed.id=f.estado_disponibilidad;

INSERT INTO lev_cat_12.col_rrrfuente
 (t_id, t_basket, fuente_administrativa, rrr_lc_derecho)
SELECT 1600000000+r.id, 1, 1200000000+r.fuente_administrativa, 1100000000+r.rrr_gc_derecho
FROM :"esq".col_rrrfuente r
JOIN mig_fadm f ON f.id=r.fuente_administrativa
JOIN :"esq".gc_derecho d ON d.id=r.rrr_gc_derecho
JOIN mig_predio p ON p.id=d.baunit;

-- col_unidadfuente (t_id = 51·10⁸ + id): fuente administrativa ligada al predio
INSERT INTO lev_cat_12.col_unidadfuente (t_id, t_basket, fuente_administrativa, unidad)
SELECT 5100000000+u.id, 1, 1200000000+u.fuente_administrativa, 100000000+u.unidad
FROM :"esq".col_unidadfuente u
JOIN mig_predio p ON p.id=u.unidad
JOIN mig_fadm f ON f.id=u.fuente_administrativa;

-- Derechos sin col_rrrfuente en el origen: se les asocian las fuentes del predio en col_unidadfuente
-- (t_id = 52·10⁸ + n). El modelo exige >=1 fuente por derecho (Nemocón: 2.903). Decisión del usuario 2026-10-14.
INSERT INTO lev_cat_12.col_rrrfuente (t_id, t_basket, fuente_administrativa, rrr_lc_derecho)
SELECT 5200000000+row_number() OVER (ORDER BY d.id, u.fuente_administrativa), 1,
  1200000000+u.fuente_administrativa, 1100000000+d.id
FROM (SELECT DISTINCT d.id, d.baunit FROM :"esq".gc_derecho d JOIN mig_predio p ON p.id=d.baunit
      WHERE NOT EXISTS (SELECT 1 FROM :"esq".col_rrrfuente r JOIN mig_fadm f ON f.id=r.fuente_administrativa
                        WHERE r.rrr_gc_derecho=d.id)) d
JOIN (SELECT DISTINCT unidad, fuente_administrativa FROM :"esq".col_unidadfuente) u ON u.unidad=d.baunit
JOIN mig_fadm f ON f.id=u.fuente_administrativa;

-- ------------------------------------------------------------
-- 10. col_uebaunit (15M): terrenos, construcciones y unidades -> predio
-- La fuente puede repetir el mismo par (ue, predio) (Vergara: 143); el OID de la
-- asociación es el par, así que se conserva solo el de menor id.
-- ------------------------------------------------------------
-- 10a. LC_ServidumbreTransito (t_id = 48·10⁸ + id), antes de col_uebaunit
INSERT INTO lev_cat_12.lc_servidumbretransito
 (t_id, t_basket, t_ili_tid, area_servidumbre, etiqueta, geometria,
  comienzo_vida_util_version, fin_vida_util_version, espacio_de_nombres, local_id)
SELECT 4800000000+s.id, 1, md5(:'mun'||'_lc_servidumbre'||s.id)::uuid,
  round(COALESCE(s.area, ST_Area(s.geometria)::numeric),1), s.etiqueta,
  ST_Multi(ST_CollectionExtract(ST_MakeValid(s.geometria),3)),
  COALESCE(s.comienzo_vida_util_version, make_date(:vigencia,1,1)), s.fin_vida_util_version,
  COALESCE(NULLIF(btrim(s.espacio_de_nombres),''),'LC_SERVIDUMBRETRANSITO'), COALESCE(NULLIF(btrim(s.local_id),''), s.id::text)
FROM :"esq".gc_servidumbretransito s JOIN mig_serv m ON m.id=s.id;

INSERT INTO lev_cat_12.col_uebaunit
 (t_id, t_basket, ue_lc_terreno, ue_lc_construccion, ue_lc_unidadconstruccion, ue_lc_servidumbretransito, baunit)
SELECT DISTINCT ON (ue_lc_terreno, ue_lc_construccion, ue_lc_unidadconstruccion, ue_lc_servidumbretransito, baunit) *
FROM (
  SELECT 1500000000+u.id AS t_id, 1 AS t_basket,
    CASE WHEN mt.id IS NOT NULL THEN 300000000+u.ue_gc_terreno END AS ue_lc_terreno,
    CASE WHEN mc.id IS NOT NULL THEN 400000000+u.ue_gc_construccion END AS ue_lc_construccion,
    CASE WHEN mu.id IS NOT NULL THEN 500000000+u.ue_gc_unidadconstruccion END AS ue_lc_unidadconstruccion,
    CASE WHEN ms.id IS NOT NULL THEN 4800000000+u.ue_gc_servidumbretransito END AS ue_lc_servidumbretransito,
    100000000+u.unidad AS baunit
  FROM :"esq".col_uebaunit u
  JOIN mig_predio p ON p.id=u.unidad
  LEFT JOIN mig_terreno mt ON mt.id=u.ue_gc_terreno
  LEFT JOIN mig_constr mc ON mc.id=u.ue_gc_construccion
  LEFT JOIN mig_uc mu ON mu.id=u.ue_gc_unidadconstruccion
  LEFT JOIN mig_serv ms ON ms.id=u.ue_gc_servidumbretransito
  WHERE mt.id IS NOT NULL OR mc.id IS NOT NULL OR mu.id IS NOT NULL OR ms.id IS NOT NULL
) x
ORDER BY ue_lc_terreno, ue_lc_construccion, ue_lc_unidadconstruccion, ue_lc_servidumbretransito, baunit, t_id;

-- 10b. LC_DatosPHCondominio (t_id = 47·10⁸ + id) de predios migrados
INSERT INTO lev_cat_12.lc_datosphcondominio
 (t_id, t_basket, t_ili_tid, area_total_terreno, area_total_terreno_privada, area_total_terreno_comun,
  area_total_construida, area_total_construida_privada, area_total_construida_comun,
  numero_torres, total_unidades_privadas, lc_predio)
SELECT 4700000000+d.id, 1, md5(:'mun'||'_lc_datosph'||d.id)::uuid,
  d.area_total_terreno, d.area_total_terreno_privada, d.area_total_terreno_comun,
  d.area_total_construida, d.area_total_construida_privada, d.area_total_construida_comun,
  d.numero_torres, d.total_unidades_privadas, 100000000+d.gc_predio
FROM :"esq".gc_datosphcondominio d JOIN mig_predio p ON p.id=d.gc_predio;

-- 10c. lc_predio_copropiedad (t_id = 50·10⁸ + id): unidad predial PH/condominio -> predio matriz,
-- con su coeficiente. Solo si ambos predios se migran. Una unidad predial tiene a lo sumo una
-- matriz (UNIQUE unidad_predial en el modelo): si el origen repite la unidad se toma el menor id.
INSERT INTO lev_cat_12.lc_predio_copropiedad (t_id, t_basket, unidad_predial, matriz, coeficiente)
SELECT DISTINCT ON (c.unidad_predial)
  5000000000+c.id, 1, 100000000+c.unidad_predial, 100000000+c.matriz, round(c.coeficiente, 10)
FROM :"esq".gc_prediocopropiedad c
JOIN mig_predio pu ON pu.id=c.unidad_predial
JOIN mig_predio pm ON pm.id=c.matriz
ORDER BY c.unidad_predial, c.id;

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
SELECT 1300000000+d.id, 1, md5(:'mun'||'_lc_dlc'||d.id)::uuid,
  d.tiene_area_registral, round(d.area_registral_m2,2),
  (SELECT e.t_id FROM lev_cat_12.lc_procedimientocatastralregistraltipo e WHERE e.ilicode='No_Requiere'),
  left(d.observaciones,500), d.fecha_visita_predial,
  (SELECT e.t_id FROM lev_cat_12.lc_interesadodocumentotipo e WHERE e.ilicode='Cedula_Ciudadania'),
  d.numero_documento_reconocedor,
  d.primer_nombre_reconocedor, d.segundo_nombre_reconocedor,
  d.primer_apellido_reconocedor, d.segundo_apellido_reconocedor,
  -- Texto libre del gestor -> ilicode (config/homologaciones.csv); 00_check_dominios lo controla
  public.fx_dom('lc_resultadovisitatipo', public.fx_hom('lc_resultadovisitatipo', d.resultado_visita)),
  d.otro_cual_resultado_visita, d.suscribe_acta_colindancia,
  d.despojo_abandono, NULL, NULLIF(d.otro_cual_estrato,''),
  100000000+d.gc_predio
FROM :"esq".dlc_datosadicionaleslevantamientocatastral d
JOIN mig_predio p ON p.id=d.gc_predio;

-- ------------------------------------------------------------
-- 12. Ofertas mercado inmobiliario (14M)
-- ------------------------------------------------------------
INSERT INTO lev_cat_12.lc_ofertasmercadoinmobiliario
 (t_id, t_basket, t_ili_tid, tipo_oferta, valor_pedido, valor_negociado,
  fecha_captura_oferta, tiempo_oferta_mercado, numero_contacto_oferente,
  nombre_oferente, lc_predio)
SELECT 1400000000+o.id, 1, md5(:'mun'||'_lc_oferta'||o.id)::uuid,
  (SELECT e.t_id FROM lev_cat_12.lc_ofertatipo e WHERE e.ilicode=o.tipo_oferta),
  o.valor_pedido, o.valor_negociado, o.fecha_captura_oferta, o.tiempo_oferta_mercado,
  COALESCE(left(o.numero_contacto_oferente,20),'Sin dato'), COALESCE(o.nombre_oferente,'Sin dato'),
  100000000+o.gc_predio
FROM :"esq".om_ofertasmercadoinmobiliario o
JOIN mig_predio p ON p.id=o.gc_predio;

-- ------------------------------------------------------------
-- 12b. Topología de levantamiento: linderos (34), puntos lindero (35), puntos de
--      levantamiento (36), col_puntoccl (37), col_masccl (38), col_menosccl (39).
--      Se migran todos los linderos y puntos del municipio; las relaciones CCL solo
--      hacia unidades espaciales migradas.
-- ------------------------------------------------------------
CREATE TEMP TABLE map_puntotipo AS SELECT id, public.fx_dom('col_puntotipo', text_code) t FROM :"esq".gc_puntotipo;
CREATE TEMP TABLE map_acuerdo   AS SELECT id, public.fx_dom('lc_acuerdotipo', text_code) t FROM :"esq".gc_acuerdotipo;
CREATE TEMP TABLE map_foto      AS SELECT id, public.fx_dom('lc_fotoidentificaciontipo', text_code) t FROM :"esq".gc_fotoidentificaciontipo;
CREATE TEMP TABLE map_metodo    AS SELECT id, public.fx_dom('col_metodoproducciontipo', text_code) t FROM :"esq".col_metodoproducciontipo;
CREATE TEMP TABLE map_puntolev  AS SELECT id, public.fx_dom('lc_puntolevtipo', text_code) t FROM :"esq".gc_puntolevtipo;

-- Linderos: solo los que delimitan (col_masccl/col_menosccl) una unidad espacial migrada; puntos de
-- lindero: solo los de esos linderos (col_puntoccl). Los puntos de levantamiento se migran todos.
CREATE TEMP TABLE mig_lindero AS
SELECT c.ccl_mas AS id FROM :"esq".col_masccl c
WHERE c.ccl_mas IS NOT NULL AND (
     c.ue_mas_gc_terreno IN (SELECT id FROM mig_terreno) OR c.ue_mas_gc_construccion IN (SELECT id FROM mig_constr)
  OR c.ue_mas_gc_unidadconstruccion IN (SELECT id FROM mig_uc) OR c.ue_mas_gc_servidumbretransito IN (SELECT id FROM mig_serv))
UNION
SELECT c.ccl_menos FROM :"esq".col_menosccl c
WHERE c.ccl_menos IS NOT NULL AND (
     c.ue_menos_gc_terreno IN (SELECT id FROM mig_terreno) OR c.ue_menos_gc_construccion IN (SELECT id FROM mig_constr)
  OR c.ue_menos_gc_unidadconstruccion IN (SELECT id FROM mig_uc) OR c.ue_menos_gc_servidumbretransito IN (SELECT id FROM mig_serv));

CREATE TEMP TABLE mig_puntolindero AS
SELECT DISTINCT c.punto_gc_puntolindero AS id FROM :"esq".col_puntoccl c
JOIN mig_lindero l ON l.id=c.ccl WHERE c.punto_gc_puntolindero IS NOT NULL;

INSERT INTO lev_cat_12.lc_lindero
 (t_id, t_basket, t_ili_tid, longitud, geometria, localizacion_textual,
  comienzo_vida_util_version, fin_vida_util_version, espacio_de_nombres, local_id)
SELECT 3400000000+l.id, 1, md5(:'mun'||'_lc_lindero'||l.id)::uuid,
  round(l.longitud,1), ST_Force3D(l.geometria), left(l.localizacion_textual,255),
  COALESCE(l.comienzo_vida_util_version, make_date(:vigencia,1,1)), l.fin_vida_util_version,
  COALESCE(NULLIF(btrim(l.espacio_de_nombres),''),'LC_LINDERO'), COALESCE(NULLIF(btrim(l.local_id),''), l.id::text)
FROM :"esq".gc_lindero l JOIN mig_lindero ml ON ml.id=l.id;

INSERT INTO lev_cat_12.lc_puntolindero
 (t_id, t_basket, t_ili_tid, id_punto_lindero, puntotipo, acuerdo, fotoidentificacion,
  exactitud_horizontal, exactitud_vertical, metodoproduccion, geometria,
  comienzo_vida_util_version, fin_vida_util_version, espacio_de_nombres, local_id)
SELECT 3500000000+p.id, 1, md5(:'mun'||'_lc_puntolindero'||p.id)::uuid,
  p.id_punto, pt.t, ac.t, fo.t,
  round(p.exactitud_horizontal,3), round(p.exactitud_vertical,3), me.t, ST_Force3D(p.geometria),
  COALESCE(p.comienzo_vida_util_version, make_date(:vigencia,1,1)), p.fin_vida_util_version,
  COALESCE(NULLIF(btrim(p.espacio_de_nombres),''),'LC_PUNTOLINDERO'), COALESCE(NULLIF(btrim(p.local_id),''), p.id::text)
FROM :"esq".gc_puntolindero p
JOIN mig_puntolindero mp ON mp.id=p.id
LEFT JOIN map_puntotipo pt ON pt.id=p.punto_tipo
LEFT JOIN map_acuerdo ac ON ac.id=p.acuerdo
LEFT JOIN map_foto fo ON fo.id=p.fotoidentificacion
LEFT JOIN map_metodo me ON me.id=p.metodo_produccion;

INSERT INTO lev_cat_12.lc_puntolevantamiento
 (t_id, t_basket, t_ili_tid, id_punto_levantamiento, puntotipo, tipo_punto_levantamiento,
  fotoidentificacion, exactitud_horizontal, exactitud_vertical, metodoproduccion, geometria,
  comienzo_vida_util_version, fin_vida_util_version, espacio_de_nombres, local_id)
SELECT 3600000000+p.id, 1, md5(:'mun'||'_lc_puntolev'||p.id)::uuid,
  p.id_punto, pt.t, tl.t, fo.t,
  round(p.exactitud_horizontal,3), round(p.exactitud_vertical,3), me.t, ST_Force3D(p.geometria),
  COALESCE(p.comienzo_vida_util_version, make_date(:vigencia,1,1)), p.fin_vida_util_version,
  COALESCE(NULLIF(btrim(p.espacio_de_nombres),''),'LC_PUNTOLEVANTAMIENTO'), COALESCE(NULLIF(btrim(p.local_id),''), p.id::text)
FROM :"esq".gc_puntolevantamiento p
LEFT JOIN map_puntotipo pt ON pt.id=p.punto_tipo
LEFT JOIN map_puntolev tl ON tl.id=p.tipo_punto_levantamiento
LEFT JOIN map_foto fo ON fo.id=p.fotoidentificacion
LEFT JOIN map_metodo me ON me.id=p.metodo_produccion;

-- Los puntos de control (gc_puntocontrol) no se migran: se excluyen sus relaciones
INSERT INTO lev_cat_12.col_puntoccl
 (t_id, t_basket, punto_lc_puntolindero, punto_lc_puntolevantamiento, ccl)
SELECT 3700000000+c.id, 1,
  CASE WHEN c.punto_gc_puntolindero IS NOT NULL THEN 3500000000+c.punto_gc_puntolindero END,
  CASE WHEN c.punto_gc_puntolevantamiento IS NOT NULL THEN 3600000000+c.punto_gc_puntolevantamiento END,
  3400000000+c.ccl
FROM :"esq".col_puntoccl c
JOIN mig_lindero ml ON ml.id=c.ccl
WHERE c.punto_gc_puntolindero IS NOT NULL OR c.punto_gc_puntolevantamiento IS NOT NULL;

INSERT INTO lev_cat_12.col_masccl
 (t_id, t_basket, ccl_mas, ue_mas_lc_terreno, ue_mas_lc_construccion, ue_mas_lc_unidadconstruccion,
  ue_mas_lc_servidumbretransito)
SELECT 3800000000+c.id, 1, 3400000000+c.ccl_mas,
  CASE WHEN mt.id IS NOT NULL THEN 300000000+mt.id END,
  CASE WHEN mc.id IS NOT NULL THEN 400000000+mc.id END,
  CASE WHEN mu.id IS NOT NULL THEN 500000000+mu.id END,
  CASE WHEN ms.id IS NOT NULL THEN 4800000000+ms.id END
FROM :"esq".col_masccl c
LEFT JOIN mig_terreno mt ON mt.id=c.ue_mas_gc_terreno
LEFT JOIN mig_constr mc ON mc.id=c.ue_mas_gc_construccion
LEFT JOIN mig_uc mu ON mu.id=c.ue_mas_gc_unidadconstruccion
LEFT JOIN mig_serv ms ON ms.id=c.ue_mas_gc_servidumbretransito
WHERE c.ccl_mas IS NOT NULL AND (mt.id IS NOT NULL OR mc.id IS NOT NULL OR mu.id IS NOT NULL OR ms.id IS NOT NULL);

INSERT INTO lev_cat_12.col_menosccl
 (t_id, t_basket, ccl_menos, ue_menos_lc_terreno, ue_menos_lc_construccion, ue_menos_lc_unidadconstruccion,
  ue_menos_lc_servidumbretransito)
SELECT 3900000000+c.id, 1, 3400000000+c.ccl_menos,
  CASE WHEN mt.id IS NOT NULL THEN 300000000+mt.id END,
  CASE WHEN mc.id IS NOT NULL THEN 400000000+mc.id END,
  CASE WHEN mu.id IS NOT NULL THEN 500000000+mu.id END,
  CASE WHEN ms.id IS NOT NULL THEN 4800000000+ms.id END
FROM :"esq".col_menosccl c
LEFT JOIN mig_terreno mt ON mt.id=c.ue_menos_gc_terreno
LEFT JOIN mig_constr mc ON mc.id=c.ue_menos_gc_construccion
LEFT JOIN mig_uc mu ON mu.id=c.ue_menos_gc_unidadconstruccion
LEFT JOIN mig_serv ms ON ms.id=c.ue_menos_gc_servidumbretransito
WHERE c.ccl_menos IS NOT NULL AND (mt.id IS NOT NULL OR mc.id IS NOT NULL OR mu.id IS NOT NULL OR ms.id IS NOT NULL);

-- ------------------------------------------------------------
-- 12c. Fuentes espaciales (40), col_baunitfuente (41), ExtArchivo (42).
--      Se migran las fuentes espaciales cuya descripcion es el número predial de un
--      predio migrado; col_baunitfuente se deriva de ese vínculo (la tabla origen viene vacía).
-- ------------------------------------------------------------
CREATE TEMP TABLE mig_fesp AS
SELECT f.id, p.id AS predio
FROM :"esq".gc_fuenteespacial f
JOIN mig_predio p ON p.numero_predial = btrim(f.descripcion);

INSERT INTO lev_cat_12.lc_fuenteespacial
 (t_id, t_basket, t_ili_tid, tipo, nombre, descripcion, estado_disponibilidad, tipo_principal,
  fecha_documento_fuente, espacio_de_nombres, local_id)
SELECT 4000000000+f.id, 1, md5(:'mun'||'_lc_fesp'||f.id)::uuid,
  public.fx_dom('col_fuenteespacialtipo', tf.text_code), f.nombre, f.descripcion,
  public.fx_dom('col_estadodisponibilidadtipo', ed.text_code),
  -- Regla del XTF de referencia: registro fotográfico -> forma de presentación 'Imagen'
  CASE WHEN tf.text_code = 'Registro_Fotografico' THEN public.fx_dom('ci_forma_presentacion_codigo','Imagen') END,
  f.fecha_documento_fuente,
  COALESCE(NULLIF(btrim(f.espacio_de_nombres),''),'LC_FUENTEESPACIAL'), COALESCE(NULLIF(btrim(f.local_id),''), f.id::text)
FROM :"esq".gc_fuenteespacial f
JOIN mig_fesp m ON m.id=f.id
LEFT JOIN :"esq".gc_fuenteespacialtipo tf ON tf.id=f.tipo
LEFT JOIN :"esq".col_estadodisponibilidadtipo ed ON ed.id=f.estado_disponibilidad;

INSERT INTO lev_cat_12.col_baunitfuente (t_id, t_basket, fuente_espacial, unidad)
SELECT 4100000000+m.id, 1, 4000000000+m.id, 100000000+m.predio FROM mig_fesp m;

INSERT INTO lev_cat_12.extarchivo
 (t_id, t_basket, t_seq, fecha_aceptacion, datos, extraccion, fecha_grabacion, fecha_entrega,
  espacio_de_nombres, local_id, lc_fuenteespacial_ext_archivo_id, lc_fuenteadministrtiva_ext_archivo_id)
SELECT 4200000000+a.id, 1,
  row_number() OVER (PARTITION BY a.gc_fuenteespacial_ext_archivo_id, a.gc_fuenteadministrtiva_ext_archivo_id
                     ORDER BY a.seq NULLS LAST, a.id) - 1,
  a.fecha_aceptacion::date, left(a.datos,255), a.extraccion::date, a.fecha_grabacion::date, a.fecha_entrega::date,
  COALESCE(fe.espacio_de_nombres, fa.espacio_de_nombres, 'EXTARCHIVO'),
  COALESCE(NULLIF(btrim(fe.local_id),''), fa.local_id, a.id::text),
  fe.t_id, fa.t_id
FROM :"esq".extarchivo a
LEFT JOIN lev_cat_12.lc_fuenteespacial fe ON fe.t_id = 4000000000+a.gc_fuenteespacial_ext_archivo_id
LEFT JOIN lev_cat_12.lc_fuenteadministrativa fa ON fa.t_id = 1200000000+a.gc_fuenteadministrtiva_ext_archivo_id
WHERE fe.t_id IS NOT NULL OR fa.t_id IS NOT NULL;

-- ------------------------------------------------------------
-- 12d. Informalidad (43) y referencia registral sistema antiguo (44)
-- ------------------------------------------------------------
INSERT INTO lev_cat_12.lc_predio_informalidad (t_id, t_basket, lc_predio_formal, lc_predio_informal)
SELECT 4300000000+i.id, 1, 100000000+i.predio_formal, 100000000+i.predio_informal
FROM :"esq".gc_predio_informalidad i
JOIN mig_predio pf ON pf.id=i.predio_formal
JOIN mig_predio pi ON pi.id=i.predio_informal;

INSERT INTO lev_cat_12.extreferenciaregistralsistemaantiguo
 (t_id, t_basket, t_ili_tid, t_seq, tipo_referencia, oficina, libro, tomo, pagina, numero,
  dia, mes, anio, matricula, lc_predio_referencia_registral_sistema_antiguo)
SELECT 4400000000+r.id, 1, md5(:'mun'||'_refreg'||r.id)::uuid,
  row_number() OVER (PARTITION BY r.gc_predio_referencia_registral_sistema_antiguo ORDER BY r.seq NULLS LAST, r.id) - 1,
  public.fx_dom('extreferenciaregistralsistemaantiguo_tipo_referencia', tr.text_code),
  r.oficina, r.libro, r.tomo, r.pagina, r.numero, r.dia, r.mes, r.anio, r.matricula,
  100000000+r.gc_predio_referencia_registral_sistema_antiguo
FROM :"esq".extreferenciaregistralsistemaantiguo r
JOIN mig_predio p ON p.id=r.gc_predio_referencia_registral_sistema_antiguo
LEFT JOIN :"esq".extreferenciaregistralsistemaantiguo_tipo_referencia tr ON tr.id=r.tipo_referencia;

-- ------------------------------------------------------------
-- 13. Submodelo Avalúos (basket 2): ZH de la vigencia y tipologías
-- Las zonas homogéneas NO se modifican: valores y geometría tal cual del backup (decisión del
-- usuario 2026-10-06). 02_fix solo redondea a 1 mm (precisión del modelo); 03 lo verifica.
-- Vigencia de zonas homogéneas por tabla: la del parámetro, o con ZH_ULTIMA_VIGENCIA=si la última
-- vigencia <= :vigencia de cada tabla (Nemocón: rurales solo con vigencia 2021). Decisión del usuario 2026-10-14.
SELECT
  CASE WHEN :'zh_ultima' = 'si' THEN COALESCE((SELECT max(date_part('year',x.vigencia))::int FROM :"esq".zhf_rural x
       WHERE date_part('year',x.vigencia) <= :vigencia), :vigencia) ELSE :vigencia END AS vig_zhf_rural,
  CASE WHEN :'zh_ultima' = 'si' THEN COALESCE((SELECT max(date_part('year',x.vigencia))::int FROM :"esq".zhf_urbana x
       WHERE date_part('year',x.vigencia) <= :vigencia), :vigencia) ELSE :vigencia END AS vig_zhf_urbana,
  CASE WHEN :'zh_ultima' = 'si' THEN COALESCE((SELECT max(date_part('year',x.vigencia))::int FROM :"esq".zhg_rural x
       WHERE date_part('year',x.vigencia) <= :vigencia), :vigencia) ELSE :vigencia END AS vig_zhg_rural,
  CASE WHEN :'zh_ultima' = 'si' THEN COALESCE((SELECT max(date_part('year',x.vigencia))::int FROM :"esq".zhg_urbana x
       WHERE date_part('year',x.vigencia) <= :vigencia), :vigencia) ELSE :vigencia END AS vig_zhg_urbana
\gset

-- ------------------------------------------------------------
INSERT INTO lev_cat_12.av_zonahomogeneafisicarural
 (t_id, t_basket, t_ili_tid, codigo, codigo_zona_fisica, area_homogenea_tierra,
  disponibilidad_agua, influencia_vial, uso_actual_suelo, norma_uso_suelo, vigencia, geometria)
SELECT 1800000000+z.id, 2, md5(:'mun'||'_zhf_rural'||z.id)::uuid,
  left(z.codigo,20), left(z.codigo_zona_fisica,20),
  -- Algunos gestores (ej. Sutatausa) guardan el código AHT ('05FSb-61'), no un número: NULL
  CASE WHEN btrim(z.area_homogenea_tierra) ~ '^[0-9]+([.,][0-9]+)?$'
       THEN replace(btrim(z.area_homogenea_tierra), ',', '.')::numeric END,
  public.fx_dom('av_disponibilidadaguatipo', z.disponibilidad_agua),
  public.fx_dom('av_influenciavialruraltipo', z.influencia_vial),
  public.fx_dom('av_usosueloruraltipo', z.uso_actual_suelo),
  left(z.norma_uso_suelo,250), z.vigencia,
  ST_Force3D(ST_Multi(z.geometria))
FROM :"esq".zhf_rural z WHERE date_part('year',z.vigencia)=:vig_zhf_rural;

INSERT INTO lev_cat_12.av_zonahomogeneafisicaurbana
 (t_id, t_basket, t_ili_tid, codigo, codigo_zona_fisica, topografia, influencia_vial,
  servicio_publico, uso_actual_suelo, norma_uso_suelo, tipificacion_construccion, vigencia, geometria)
SELECT 1900000000+z.id, 2, md5(:'mun'||'_zhf_urbana'||z.id)::uuid,
  left(z.codigo,20), left(z.codigo_zona_fisica,20),
  public.fx_dom('av_topografiazonatipo', z.topografia),
  public.fx_dom('av_influenciavialurbanatipo', z.influencia_vial),
  public.fx_dom('av_serviciospublicostipo', z.servicio_publico),
  public.fx_dom('av_usosuelourbanotipo', z.uso_actual_suelo),
  left(z.norma_uso_suelo,250),
  public.fx_dom('av_tipificacionconstrucciontipo', z.tipificacion_construccion), z.vigencia,
  ST_Force3D(ST_Multi(z.geometria))
FROM :"esq".zhf_urbana z WHERE date_part('year',z.vigencia)=:vig_zhf_urbana;

INSERT INTO lev_cat_12.av_zonahomogeneageoeconomicarural
 (t_id, t_basket, t_ili_tid, codigo, codigo_zona_geoeconomica, valor_hectarea,
  subzona_fisica, vigencia, geometria)
SELECT 2000000000+z.id, 2, md5(:'mun'||'_zhg_rural'||z.id)::uuid,
  left(z.codigo,20), left(z.codigo_zona_geoeconomica,20), round(z.valor_hectarea_agropecuario,1),
  z.subzona_fisica, z.vigencia,
  ST_Force3D(ST_Multi(z.geometria))
FROM :"esq".zhg_rural z WHERE date_part('year',z.vigencia)=:vig_zhg_rural;

INSERT INTO lev_cat_12.av_zonahomogeneageoeconomicaurbana
 (t_id, t_basket, t_ili_tid, codigo, codigo_zona_geoeconomica, valor_metro,
  subzona_fisica, vigencia, geometria)
SELECT 2100000000+z.id, 2, md5(:'mun'||'_zhg_urbana'||z.id)::uuid,
  left(z.codigo,20), left(z.codigo_zona_geoeconomica,20), round(z.valor_m2_catastral,1),
  z.subzona_fisica, z.vigencia,
  ST_Force3D(ST_Multi(z.geometria))
FROM :"esq".zhg_urbana z WHERE date_part('year',z.vigencia)=:vig_zhg_urbana;

-- Tipologías con valor de la vigencia (solo las que existen en AV_TipologiaTipo;
-- los anexos no tienen equivalente en el submodelo de avalúos v1.2).
-- Algunos gestores (ej. Vergara) no traen tb_valortipologia: se omite el bloque.
-- Se leen de :esq_tipologia (por defecto :esq), p. ej. un backup auxiliar que sí las trae.
SELECT to_regclass(:'esq_tipologia'||'.tb_valortipologia') IS NOT NULL AS tiene_tb_valortipologia \gset
\if :tiene_tb_valortipologia
INSERT INTO lev_cat_12.av_tipologiaconstruccion
 (t_id, t_basket, t_ili_tid, tipo_tipologia, valor_unitario)
SELECT 2200000000+v.id, 2, md5(:'mun'||'_av_tipologia'||v.id)::uuid,
  (SELECT e.t_id FROM lev_cat_12.av_tipologiatipo e WHERE e.ilicode=tt.text_code),
  round(v.valor_m2_catastral,1)
FROM :"esq_tipologia".tb_valortipologia v
JOIN :"esq_tipologia".cuc_tipologiatipo tt ON tt.id=v.tipo_tipologia
WHERE date_part('year',v.vigencia)=:vigencia
  AND EXISTS (SELECT 1 FROM lev_cat_12.av_tipologiatipo e WHERE e.ilicode=tt.text_code);
\else
\echo 'AVISO: sin tb_valortipologia en' :esq_tipologia ': av_tipologiaconstruccion queda vacía'
\endif

-- ------------------------------------------------------------
-- 14. Submodelo Cartografía Catastral (basket 3)
-- ------------------------------------------------------------
INSERT INTO lev_cat_12.cc_barrio (t_id, t_basket, codigo, nombre, codigo_sector, geometria)
SELECT 2300000000+id, 3, codigo, nombre, codigo_sector, ST_Multi(ST_CollectionExtract(ST_MakeValid(geometria),3))
FROM :"esq".cc_barrio WHERE geometria IS NOT NULL;

INSERT INTO lev_cat_12.cc_centropoblado (t_id, t_basket, codigo, nombre, geometria)
SELECT 2400000000+id, 3, codigo, nombre, ST_Multi(ST_CollectionExtract(ST_MakeValid(geometria),3))
FROM :"esq".cc_centropoblado WHERE geometria IS NOT NULL;

INSERT INTO lev_cat_12.cc_corregimiento (t_id, t_basket, codigo, nombre, geometria)
SELECT 2500000000+id, 3, codigo, nombre, ST_Multi(ST_CollectionExtract(ST_MakeValid(geometria),3))
FROM :"esq".cc_corregimiento WHERE geometria IS NOT NULL;

INSERT INTO lev_cat_12.cc_limitemunicipio (t_id, t_basket, codigo_departamento, codigo_municipio, nombre_municipio, geometria)
SELECT 2600000000+id, 3, codigo_departamento, codigo_municipio, nombre_municipio, ST_Multi(ST_CollectionExtract(ST_MakeValid(geometria),3))
FROM :"esq".cc_limitemunicipio WHERE geometria IS NOT NULL;

INSERT INTO lev_cat_12.cc_localidadcomuna (t_id, t_basket, codigo, nombre, geometria)
SELECT 2700000000+id, 3, codigo, nombre, ST_Multi(ST_CollectionExtract(ST_MakeValid(geometria),3))
FROM :"esq".cc_localidadcomuna WHERE geometria IS NOT NULL;

INSERT INTO lev_cat_12.cc_manzana (t_id, t_basket, codigo, codigo_barrio, nombre, geometria)
SELECT 2800000000+id, 3, codigo, codigo_barrio, nombre, ST_Multi(ST_CollectionExtract(ST_MakeValid(geometria),3))
FROM :"esq".cc_manzana WHERE geometria IS NOT NULL;

INSERT INTO lev_cat_12.cc_nomenclaturavial (t_id, t_basket, tipo_via, numero_via, geometria)
SELECT 2900000000+n.id, 3,
  (SELECT e.t_id FROM lev_cat_12.cc_nomenclaturavial_tipo_via e WHERE e.ilicode=tv.text_code),
  n.numero_via, ST_Multi(ST_CollectionExtract(ST_MakeValid(n.geometria),2))
FROM :"esq".cc_nomenclaturavial n
LEFT JOIN :"esq".cc_nomenclaturavial_tipo_via tv ON tv.id=n.tipo_via
-- tipo_via y numero_via son MANDATORY: se excluyen los tramos sin tipo o sin número (Nemocón: 5 sin
-- tipo y 5 con numero_via vacío, 4 de ellos también sin tipo -> 6 de 87). ili2pg exporta '' sin
-- reclamar, pero ilivalidator lo rechaza ("Attribute Numero_Via requires a value").
WHERE n.geometria IS NOT NULL AND btrim(n.numero_via) <> ''
  AND EXISTS (SELECT 1 FROM lev_cat_12.cc_nomenclaturavial_tipo_via e WHERE e.ilicode=tv.text_code);

INSERT INTO lev_cat_12.cc_perimetrourbano (t_id, t_basket, codigo_departamento, codigo_municipio, tipo_avaluo, nombre_geografico, codigo_nombre, geometria)
SELECT 3000000000+id, 3, codigo_departamento, codigo_municipio, tipo_avaluo, nombre_geografico, codigo_nombre, ST_Multi(ST_CollectionExtract(ST_MakeValid(geometria),3))
FROM :"esq".cc_perimetrourbano WHERE geometria IS NOT NULL;

INSERT INTO lev_cat_12.cc_sectorrural (t_id, t_basket, codigo, geometria)
SELECT 3100000000+id, 3, codigo, ST_Multi(ST_CollectionExtract(ST_MakeValid(geometria),3))
FROM :"esq".cc_sectorrural WHERE geometria IS NOT NULL;

INSERT INTO lev_cat_12.cc_sectorurbano (t_id, t_basket, codigo, geometria)
SELECT 3200000000+id, 3, codigo, ST_Multi(ST_CollectionExtract(ST_MakeValid(geometria),3))
FROM :"esq".cc_sectorurbano WHERE geometria IS NOT NULL;

INSERT INTO lev_cat_12.cc_vereda (t_id, t_basket, codigo, nombre, codigo_sector, geometria)
-- codigo_sector es TEXT*2: si viene el código completo (Nemocón: '254860000') se toman los 2 últimos dígitos
SELECT 3300000000+id, 3, codigo, nombre, right(codigo_sector,2), ST_Multi(ST_CollectionExtract(ST_MakeValid(geometria),3))
FROM :"esq".cc_vereda WHERE geometria IS NOT NULL;

-- Ajustar secuencia t_id por encima del máximo usado (copropiedad 50, unidadfuente 51,
-- rrrfuente derivada 52 e interesado placeholder 53 ·10⁸)
SELECT setval('lev_cat_12.t_ili2db_seq', 5400000000, false);

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
UNION ALL SELECT 'lc_servidumbre', count(*) FROM lev_cat_12.lc_servidumbretransito
UNION ALL SELECT 'lc_datosph', count(*) FROM lev_cat_12.lc_datosphcondominio
UNION ALL SELECT 'lc_predio_copropiedad', count(*) FROM lev_cat_12.lc_predio_copropiedad
UNION ALL SELECT 'lc_datosadicionales', count(*) FROM lev_cat_12.lc_datosadicionaleslevantamientocatastral
UNION ALL SELECT 'lc_ofertas', count(*) FROM lev_cat_12.lc_ofertasmercadoinmobiliario
UNION ALL SELECT 'lc_lindero', count(*) FROM lev_cat_12.lc_lindero
UNION ALL SELECT 'lc_puntolindero', count(*) FROM lev_cat_12.lc_puntolindero
UNION ALL SELECT 'lc_puntolevantamiento', count(*) FROM lev_cat_12.lc_puntolevantamiento
UNION ALL SELECT 'col_puntoccl', count(*) FROM lev_cat_12.col_puntoccl
UNION ALL SELECT 'col_masccl', count(*) FROM lev_cat_12.col_masccl
UNION ALL SELECT 'col_menosccl', count(*) FROM lev_cat_12.col_menosccl
UNION ALL SELECT 'lc_fuenteespacial', count(*) FROM lev_cat_12.lc_fuenteespacial
UNION ALL SELECT 'col_baunitfuente', count(*) FROM lev_cat_12.col_baunitfuente
UNION ALL SELECT 'extarchivo', count(*) FROM lev_cat_12.extarchivo
UNION ALL SELECT 'lc_predio_informalidad', count(*) FROM lev_cat_12.lc_predio_informalidad
UNION ALL SELECT 'extrefregistral', count(*) FROM lev_cat_12.extreferenciaregistralsistemaantiguo
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

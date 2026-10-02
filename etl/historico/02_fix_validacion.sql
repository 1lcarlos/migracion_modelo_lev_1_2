-- Correcciones post-validación ili2pg
BEGIN;

-- 1. Deduplicar col_miembros (mismo interesado en misma agrupación repetido)
DELETE FROM lev_cat_12.col_miembros m
USING lev_cat_12.col_miembros m2
WHERE m.interesado_lc_interesado = m2.interesado_lc_interesado
  AND m.agrupacion = m2.agrupacion
  AND m.t_id > m2.t_id;

-- 2. TID para clases de cartografía (tópico sin OID declarado: TID simple)
UPDATE lev_cat_12.cc_barrio           SET t_ili_tid = 'cc'||t_id WHERE t_ili_tid IS NULL;
UPDATE lev_cat_12.cc_centropoblado    SET t_ili_tid = 'cc'||t_id WHERE t_ili_tid IS NULL;
UPDATE lev_cat_12.cc_corregimiento    SET t_ili_tid = 'cc'||t_id WHERE t_ili_tid IS NULL;
UPDATE lev_cat_12.cc_limitemunicipio  SET t_ili_tid = 'cc'||t_id WHERE t_ili_tid IS NULL;
UPDATE lev_cat_12.cc_localidadcomuna  SET t_ili_tid = 'cc'||t_id WHERE t_ili_tid IS NULL;
UPDATE lev_cat_12.cc_manzana          SET t_ili_tid = 'cc'||t_id WHERE t_ili_tid IS NULL;
UPDATE lev_cat_12.cc_nomenclaturavial SET t_ili_tid = 'cc'||t_id WHERE t_ili_tid IS NULL;
UPDATE lev_cat_12.cc_perimetrourbano  SET t_ili_tid = 'cc'||t_id WHERE t_ili_tid IS NULL;
UPDATE lev_cat_12.cc_sectorrural      SET t_ili_tid = 'cc'||t_id WHERE t_ili_tid IS NULL;
UPDATE lev_cat_12.cc_sectorurbano     SET t_ili_tid = 'cc'||t_id WHERE t_ili_tid IS NULL;
UPDATE lev_cat_12.cc_vereda           SET t_ili_tid = 'cc'||t_id WHERE t_ili_tid IS NULL;

-- 3. Limpieza de vértices repetidos (estándar INTERLIS) en todas las capas poligonales
UPDATE lev_cat_12.lc_terreno
SET geometria = ST_Force3D(ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_RemoveRepeatedPoints(geometria,0.002)),3)));
UPDATE lev_cat_12.lc_construccion
SET geometria = ST_Force3D(ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_RemoveRepeatedPoints(geometria,0.002)),3)))
WHERE geometria IS NOT NULL;
UPDATE lev_cat_12.lc_unidadconstruccion
SET geometria = ST_Force3D(ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_RemoveRepeatedPoints(geometria,0.002)),3)))
WHERE geometria IS NOT NULL;
UPDATE lev_cat_12.av_zonahomogeneafisicarural
SET geometria = ST_Force3D(ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_RemoveRepeatedPoints(geometria,0.002)),3)));
UPDATE lev_cat_12.av_zonahomogeneafisicaurbana
SET geometria = ST_Force3D(ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_RemoveRepeatedPoints(geometria,0.002)),3)));
UPDATE lev_cat_12.av_zonahomogeneageoeconomicarural
SET geometria = ST_Force3D(ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_RemoveRepeatedPoints(geometria,0.002)),3)));
UPDATE lev_cat_12.av_zonahomogeneageoeconomicaurbana
SET geometria = ST_Force3D(ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_RemoveRepeatedPoints(geometria,0.002)),3)));
UPDATE lev_cat_12.cc_barrio SET geometria = ST_Force3D(ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_RemoveRepeatedPoints(geometria,0.002)),3)));
UPDATE lev_cat_12.cc_centropoblado SET geometria = ST_Force3D(ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_RemoveRepeatedPoints(geometria,0.002)),3)));
UPDATE lev_cat_12.cc_corregimiento SET geometria = ST_Force3D(ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_RemoveRepeatedPoints(geometria,0.002)),3)));
UPDATE lev_cat_12.cc_limitemunicipio SET geometria = ST_Force3D(ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_RemoveRepeatedPoints(geometria,0.002)),3)));
UPDATE lev_cat_12.cc_localidadcomuna SET geometria = ST_Force3D(ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_RemoveRepeatedPoints(geometria,0.002)),3)));
UPDATE lev_cat_12.cc_manzana SET geometria = ST_Force3D(ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_RemoveRepeatedPoints(geometria,0.002)),3)));
UPDATE lev_cat_12.cc_perimetrourbano SET geometria = ST_Force3D(ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_RemoveRepeatedPoints(geometria,0.002)),3)));
UPDATE lev_cat_12.cc_sectorrural SET geometria = ST_Force3D(ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_RemoveRepeatedPoints(geometria,0.002)),3)));
UPDATE lev_cat_12.cc_sectorurbano SET geometria = ST_Force3D(ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_RemoveRepeatedPoints(geometria,0.002)),3)));
UPDATE lev_cat_12.cc_vereda SET geometria = ST_Force3D(ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_RemoveRepeatedPoints(geometria,0.002)),3)));
UPDATE lev_cat_12.cc_nomenclaturavial SET geometria = ST_Force3D(ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_RemoveRepeatedPoints(geometria,0.002)),2)));

-- 4. Auto-intersecciones detectadas por el validador (unión con buffer 0)
UPDATE lev_cat_12.lc_terreno
SET geometria = ST_Force3D(ST_Multi(ST_CollectionExtract(ST_RemoveRepeatedPoints(ST_Buffer(geometria,0),0.002),3)))
WHERE t_id = 3050136;
UPDATE lev_cat_12.lc_construccion
SET geometria = ST_Force3D(ST_Multi(ST_CollectionExtract(ST_RemoveRepeatedPoints(ST_Buffer(geometria,0),0.002),3)))
WHERE t_id = 4002231;

COMMIT;

SELECT 'miembros' k, count(*) FROM lev_cat_12.col_miembros
UNION ALL SELECT 'cc_sin_tid', (SELECT count(*) FROM lev_cat_12.cc_vereda WHERE t_ili_tid IS NULL)
UNION ALL SELECT 'terreno_invalid', (SELECT count(*) FROM lev_cat_12.lc_terreno WHERE NOT ST_IsValid(geometria) OR ST_IsEmpty(geometria));

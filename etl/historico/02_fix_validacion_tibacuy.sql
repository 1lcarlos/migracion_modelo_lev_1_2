-- Correcciones post-validación ili2pg (Tibacuy)
-- Nota: en Tibacuy varios registros tenían polígonos con auto-intersección; ST_MakeValid
-- los resuelve creando vértices fuera de la grilla y polígonos "astilla" de área ~0 que el
-- validador INTERLIS reporta como "duplicate coord". El orden correcto del pipeline es:
-- MakeValid -> descartar astillas (área < 1 cm²) -> SnapToGrid 1mm (precisión del XTF)
-- -> RemoveRepeatedPoints 2mm.
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

-- 3. Función de limpieza geométrica (estándar INTERLIS)
CREATE OR REPLACE FUNCTION public.fx_limpiar_poligono(geom geometry)
RETURNS geometry LANGUAGE sql IMMUTABLE AS $$
  SELECT ST_Force3D(ST_Multi(ST_RemoveRepeatedPoints(ST_SnapToGrid(comp,0.001),0.002)))
  FROM (
    SELECT ST_Collect(g) AS comp FROM (
      SELECT (ST_Dump(ST_CollectionExtract(ST_MakeValid(geom),3))).geom AS g
    ) d WHERE ST_Area(g) >= 0.01
  ) x WHERE comp IS NOT NULL
$$;

-- 4. Aplicar a todas las capas poligonales (COALESCE conserva el original si todo son astillas)
UPDATE lev_cat_12.lc_terreno SET geometria = COALESCE(public.fx_limpiar_poligono(geometria), geometria);
UPDATE lev_cat_12.lc_construccion SET geometria = public.fx_limpiar_poligono(geometria) WHERE geometria IS NOT NULL;
UPDATE lev_cat_12.lc_unidadconstruccion SET geometria = public.fx_limpiar_poligono(geometria) WHERE geometria IS NOT NULL;
UPDATE lev_cat_12.av_zonahomogeneafisicarural SET geometria = COALESCE(public.fx_limpiar_poligono(geometria), geometria);
UPDATE lev_cat_12.av_zonahomogeneafisicaurbana SET geometria = COALESCE(public.fx_limpiar_poligono(geometria), geometria);
UPDATE lev_cat_12.av_zonahomogeneageoeconomicarural SET geometria = COALESCE(public.fx_limpiar_poligono(geometria), geometria);
UPDATE lev_cat_12.av_zonahomogeneageoeconomicaurbana SET geometria = COALESCE(public.fx_limpiar_poligono(geometria), geometria);
UPDATE lev_cat_12.cc_barrio SET geometria = COALESCE(public.fx_limpiar_poligono(geometria), geometria);
UPDATE lev_cat_12.cc_centropoblado SET geometria = COALESCE(public.fx_limpiar_poligono(geometria), geometria);
UPDATE lev_cat_12.cc_corregimiento SET geometria = COALESCE(public.fx_limpiar_poligono(geometria), geometria);
UPDATE lev_cat_12.cc_limitemunicipio SET geometria = COALESCE(public.fx_limpiar_poligono(geometria), geometria);
UPDATE lev_cat_12.cc_localidadcomuna SET geometria = COALESCE(public.fx_limpiar_poligono(geometria), geometria);
UPDATE lev_cat_12.cc_manzana SET geometria = COALESCE(public.fx_limpiar_poligono(geometria), geometria);
UPDATE lev_cat_12.cc_perimetrourbano SET geometria = COALESCE(public.fx_limpiar_poligono(geometria), geometria);
UPDATE lev_cat_12.cc_sectorrural SET geometria = COALESCE(public.fx_limpiar_poligono(geometria), geometria);
UPDATE lev_cat_12.cc_sectorurbano SET geometria = COALESCE(public.fx_limpiar_poligono(geometria), geometria);
UPDATE lev_cat_12.cc_vereda SET geometria = COALESCE(public.fx_limpiar_poligono(geometria), geometria);
-- Líneas (nomenclatura vial): solo snap + dedup
UPDATE lev_cat_12.cc_nomenclaturavial
SET geometria = ST_Force3D(ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_RemoveRepeatedPoints(ST_SnapToGrid(geometria,0.001),0.002)),2)));

-- 5. Geometrías degeneradas que colapsan a vacío (área < tolerancia):
-- la geometría es opcional en construcción/unidad, se dejan en NULL
UPDATE lev_cat_12.lc_unidadconstruccion SET geometria=NULL WHERE geometria IS NOT NULL AND ST_IsEmpty(geometria);
UPDATE lev_cat_12.lc_construccion SET geometria=NULL WHERE geometria IS NOT NULL AND ST_IsEmpty(geometria);

COMMIT;

-- Verificación
SELECT 'miembros' k, count(*) FROM lev_cat_12.col_miembros
UNION ALL SELECT 'cc_sin_tid', (SELECT count(*) FROM lev_cat_12.cc_vereda WHERE t_ili_tid IS NULL)
UNION ALL SELECT 'terreno_invalid', (SELECT count(*) FROM lev_cat_12.lc_terreno WHERE NOT ST_IsValid(geometria) OR ST_IsEmpty(geometria))
UNION ALL SELECT 'constr_invalid', (SELECT count(*) FROM lev_cat_12.lc_construccion WHERE geometria IS NOT NULL AND (NOT ST_IsValid(geometria) OR ST_IsEmpty(geometria)))
UNION ALL SELECT 'uc_invalid', (SELECT count(*) FROM lev_cat_12.lc_unidadconstruccion WHERE geometria IS NOT NULL AND (NOT ST_IsValid(geometria) OR ST_IsEmpty(geometria)));

-- ============================================================
-- Correcciones post-migración (plantilla, sin parámetros: opera sobre lev_cat_12)
-- Consolida 02_fix_validacion_tibacuy.sql + 03_fix_revalidacion_tibirita.sql:
--   1. Dedup de col_miembros
--   2. Agrupaciones unipersonales (tras el dedup) -> derecho al interesado directo
--   3. TID de clases de cartografía
--   4. Limpieza geométrica: MakeValid -> descartar astillas (< 1 cm²)
--      -> SnapToGrid 1 mm (precisión del XTF) -> RemoveRepeatedPoints 2 mm
--   5. Reintento con ST_Buffer(0) para polígonos que el snap deja inválidos
--   6. Geometrías opcionales que colapsan a vacío -> NULL
-- Ver docs/03_decisiones_y_lecciones.md (catálogo de errores).
-- ============================================================
CREATE OR REPLACE FUNCTION public.fx_limpiar_poligono(geom geometry)
RETURNS geometry LANGUAGE sql IMMUTABLE AS $$
  SELECT ST_Force3D(ST_Multi(ST_RemoveRepeatedPoints(ST_SnapToGrid(comp,0.001),0.002)))
  FROM (
    SELECT ST_Collect(g) AS comp FROM (
      SELECT (ST_Dump(ST_CollectionExtract(ST_MakeValid(geom),3))).geom AS g
    ) d WHERE ST_Area(g) >= 0.01
  ) x WHERE comp IS NOT NULL
$$;

BEGIN;

-- 1. Deduplicar col_miembros (mismo interesado en misma agrupación repetido)
DELETE FROM lev_cat_12.col_miembros m
USING lev_cat_12.col_miembros m2
WHERE m.interesado_lc_interesado = m2.interesado_lc_interesado
  AND m.agrupacion = m2.agrupacion
  AND m.t_id > m2.t_id;

-- 2. Agrupaciones con un solo miembro (el modelo exige >= 2)
CREATE TEMP TABLE tmp_uni ON COMMIT DROP AS
SELECT m.agrupacion AS ag, min(m.interesado_lc_interesado) AS inte
FROM lev_cat_12.col_miembros m GROUP BY m.agrupacion HAVING count(*) = 1;

UPDATE lev_cat_12.lc_derecho d
SET interesado_lc_interesado = u.inte, interesado_lc_agrupacioninteresados = NULL
FROM tmp_uni u WHERE d.interesado_lc_agrupacioninteresados = u.ag;
DELETE FROM lev_cat_12.col_miembros m USING tmp_uni u WHERE m.agrupacion = u.ag;
DELETE FROM lev_cat_12.lc_agrupacioninteresados a USING tmp_uni u WHERE a.t_id = u.ag;

-- 3. TID para clases de cartografía (tópico sin OID declarado: TID simple)
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

-- 4. Limpieza geométrica (COALESCE conserva el original si todo son astillas)
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

-- 5. Polígonos que el snap dejó con micro auto-intersección: buffer(0) y limpiar de nuevo
UPDATE lev_cat_12.lc_terreno
SET geometria = COALESCE(public.fx_limpiar_poligono(ST_Buffer(geometria,0)), geometria)
WHERE NOT ST_IsValid(geometria);
UPDATE lev_cat_12.lc_construccion
SET geometria = public.fx_limpiar_poligono(ST_Buffer(geometria,0))
WHERE geometria IS NOT NULL AND NOT ST_IsValid(geometria);
UPDATE lev_cat_12.lc_unidadconstruccion
SET geometria = public.fx_limpiar_poligono(ST_Buffer(geometria,0))
WHERE geometria IS NOT NULL AND NOT ST_IsValid(geometria);

-- 6. Geometrías degeneradas que colapsan a vacío: opcionales en construcción/unidad -> NULL
UPDATE lev_cat_12.lc_unidadconstruccion SET geometria=NULL WHERE geometria IS NOT NULL AND ST_IsEmpty(geometria);
UPDATE lev_cat_12.lc_construccion SET geometria=NULL WHERE geometria IS NOT NULL AND ST_IsEmpty(geometria);

COMMIT;

-- Verificación (todo debe ser 0)
SELECT 'agrup_con_1_miembro' k,
 (SELECT count(*) FROM (SELECT agrupacion FROM lev_cat_12.col_miembros GROUP BY 1 HAVING count(*)<2) x) n
UNION ALL SELECT 'derechos_sin_titular',
 (SELECT count(*) FROM lev_cat_12.lc_derecho WHERE interesado_lc_interesado IS NULL AND interesado_lc_agrupacioninteresados IS NULL)
UNION ALL SELECT 'cc_sin_tid', (SELECT count(*) FROM lev_cat_12.cc_vereda WHERE t_ili_tid IS NULL)
UNION ALL SELECT 'terreno_invalido', (SELECT count(*) FROM lev_cat_12.lc_terreno WHERE NOT ST_IsValid(geometria) OR ST_IsEmpty(geometria))
UNION ALL SELECT 'constr_invalida', (SELECT count(*) FROM lev_cat_12.lc_construccion WHERE geometria IS NOT NULL AND NOT ST_IsValid(geometria))
UNION ALL SELECT 'uc_invalida', (SELECT count(*) FROM lev_cat_12.lc_unidadconstruccion WHERE geometria IS NOT NULL AND NOT ST_IsValid(geometria));

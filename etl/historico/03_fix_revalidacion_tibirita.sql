-- ============================================================
-- Fix de revalidación Tibirita (aplicado 2026-08-28 sobre tibirita_lev12)
-- Motivo: el XTF exportado el 2026-08-28 15:13 provenía de una exportación
-- FALLIDA (180 errores: duplicate coord, clases cc sin OID, col_miembros
-- duplicados). El 02_fix_validacion.sql corrigió OIDs y duplicados, pero la
-- exportación nunca se re-ejecutó y quedaban dos defectos:
--   a) Vértices casi duplicados / astillas creadas por ST_MakeValid
--      (mismo hallazgo del ETL de Tibacuy). Solución: MakeValid -> descartar
--      componentes < 1 cm² -> SnapToGrid 1mm -> RemoveRepeatedPoints 2mm.
--   b) 4 agrupaciones de interesados con 1 solo miembro tras la deduplicación
--      (la fuente traía a la misma persona repetida). El modelo exige >= 2:
--      el derecho pasa al interesado directo y la agrupación se elimina.
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

-- a) Limpieza geométrica en todas las capas poligonales
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
UPDATE lev_cat_12.cc_nomenclaturavial
SET geometria = ST_Force3D(ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_RemoveRepeatedPoints(ST_SnapToGrid(geometria,0.001),0.002)),2)));
UPDATE lev_cat_12.lc_unidadconstruccion SET geometria=NULL WHERE geometria IS NOT NULL AND ST_IsEmpty(geometria);
UPDATE lev_cat_12.lc_construccion SET geometria=NULL WHERE geometria IS NOT NULL AND ST_IsEmpty(geometria);

-- Terreno 3050136: auto-intersección que el snap reintroducía; buffer(0) previo
UPDATE lev_cat_12.lc_terreno
SET geometria = COALESCE(public.fx_limpiar_poligono(ST_Buffer(geometria,0)), geometria)
WHERE t_id = 3050136 AND NOT ST_IsValid(geometria);

-- b) Agrupaciones unipersonales -> derecho al interesado directo
WITH uni AS (
  SELECT a.t_id ag, min(m.interesado_lc_interesado) inte
  FROM lev_cat_12.lc_agrupacioninteresados a
  JOIN lev_cat_12.col_miembros m ON m.agrupacion=a.t_id
  GROUP BY a.t_id HAVING count(*)=1)
UPDATE lev_cat_12.lc_derecho d
SET interesado_lc_interesado = uni.inte, interesado_lc_agrupacioninteresados = NULL
FROM uni WHERE d.interesado_lc_agrupacioninteresados = uni.ag;
DELETE FROM lev_cat_12.col_miembros m
USING (SELECT agrupacion FROM lev_cat_12.col_miembros GROUP BY 1 HAVING count(*)=1) u
WHERE m.agrupacion=u.agrupacion;
DELETE FROM lev_cat_12.lc_agrupacioninteresados a
WHERE NOT EXISTS (SELECT 1 FROM lev_cat_12.col_miembros m WHERE m.agrupacion=a.t_id);

COMMIT;

-- Verificación
SELECT 'geom_invalidas' k,
 (SELECT count(*) FROM lev_cat_12.lc_terreno WHERE NOT ST_IsValid(geometria) OR ST_IsEmpty(geometria))
 + (SELECT count(*) FROM lev_cat_12.lc_construccion WHERE geometria IS NOT NULL AND NOT ST_IsValid(geometria))
 + (SELECT count(*) FROM lev_cat_12.lc_unidadconstruccion WHERE geometria IS NOT NULL AND NOT ST_IsValid(geometria))
UNION ALL SELECT 'agrup_con_1_miembro',
 (SELECT count(*) FROM (SELECT agrupacion FROM lev_cat_12.col_miembros GROUP BY 1 HAVING count(*)<2) x)
UNION ALL SELECT 'derechos_sin_titular',
 (SELECT count(*) FROM lev_cat_12.lc_derecho WHERE interesado_lc_interesado IS NULL AND interesado_lc_agrupacioninteresados IS NULL);

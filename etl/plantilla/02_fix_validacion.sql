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
--   7. Fin_Vida_Util_Version anterior al comienzo (ObjetoVersionado.Constraint1) -> NULL
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
UPDATE lev_cat_12.lc_servidumbretransito SET geometria = public.fx_limpiar_poligono(geometria) WHERE geometria IS NOT NULL;
-- Zonas homogéneas: NO se limpian (no se quitan astillas ni vértices). Solo se redondean a 1 mm,
-- la precisión de las coordenadas del modelo (el XTF las escribe así de todos modos).
UPDATE lev_cat_12.av_zonahomogeneafisicarural SET geometria = ST_SnapToGrid(geometria, 0.001);
UPDATE lev_cat_12.av_zonahomogeneafisicaurbana SET geometria = ST_SnapToGrid(geometria, 0.001);
UPDATE lev_cat_12.av_zonahomogeneageoeconomicarural SET geometria = ST_SnapToGrid(geometria, 0.001);
UPDATE lev_cat_12.av_zonahomogeneageoeconomicaurbana SET geometria = ST_SnapToGrid(geometria, 0.001);
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

-- Linderos (líneas) y puntos: alinear a 1 mm; un lindero que colapsa (< 2 vértices) queda NULL
UPDATE lev_cat_12.lc_lindero
SET geometria = ST_Force3D(ST_RemoveRepeatedPoints(ST_SnapToGrid(geometria,0.001),0.002))
WHERE geometria IS NOT NULL;
UPDATE lev_cat_12.lc_lindero SET geometria = NULL
WHERE geometria IS NOT NULL AND (ST_NPoints(geometria) < 2 OR ST_Length(geometria) = 0);
UPDATE lev_cat_12.lc_puntolindero SET geometria = ST_Force3D(ST_SnapToGrid(geometria,0.001));
UPDATE lev_cat_12.lc_puntolevantamiento SET geometria = ST_Force3D(ST_SnapToGrid(geometria,0.001));

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

-- 7. Fin de vida útil anterior al comienzo: viola ObjetoVersionado.Constraint1
--    (Sutatausa v2023: predio vigente con fin 2022-09-20 y comienzo 2023-01-01) -> NULL
DO $$
DECLARE r record; n bigint;
BEGIN
  FOR r IN SELECT table_name FROM information_schema.columns
           WHERE table_schema = 'lev_cat_12' AND column_name = 'fin_vida_util_version'
             AND table_name IN (SELECT table_name FROM information_schema.columns
                                WHERE table_schema = 'lev_cat_12' AND column_name = 'comienzo_vida_util_version')
  LOOP
    EXECUTE format('UPDATE lev_cat_12.%I SET fin_vida_util_version = NULL
                    WHERE fin_vida_util_version < comienzo_vida_util_version', r.table_name);
    GET DIAGNOSTICS n = ROW_COUNT;
    IF n > 0 THEN RAISE NOTICE 'fin_vida_util_version < comienzo en %: % registros -> NULL', r.table_name, n; END IF;
  END LOOP;
END $$;

-- 8. Caracteres de control (U+0001-U+001F, U+007F) en textos: el validador los rechaza en TEXT
--    de datos (Nemocón: nombre y dirección de 1 predio) -> se reemplazan por espacio y se recorta
DO $$
DECLARE r record; n bigint;
BEGIN
  FOR r IN SELECT c.table_name, c.column_name FROM information_schema.columns c
           JOIN information_schema.tables t ON t.table_schema=c.table_schema AND t.table_name=c.table_name
           WHERE c.table_schema = 'lev_cat_12' AND t.table_type = 'BASE TABLE'
             AND c.data_type IN ('character varying','text') AND c.table_name NOT LIKE 't_ili2db%'
             -- no tocar los catálogos de dominio (tablas con ilicode): sus descripciones son del modelo
             AND NOT EXISTS (SELECT 1 FROM information_schema.columns k WHERE k.table_schema=c.table_schema
                             AND k.table_name=c.table_name AND k.column_name='ilicode')
  LOOP
    EXECUTE format('UPDATE lev_cat_12.%I SET %I = btrim(regexp_replace(%I, ''[\x01-\x1f\x7f]'', '' '', ''g''))
                    WHERE %I ~ ''[\x01-\x1f\x7f]''', r.table_name, r.column_name, r.column_name, r.column_name);
    GET DIAGNOSTICS n = ROW_COUNT;
    IF n > 0 THEN RAISE NOTICE 'caracteres de control en %.%: % registros', r.table_name, r.column_name, n; END IF;
  END LOOP;
END $$;

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

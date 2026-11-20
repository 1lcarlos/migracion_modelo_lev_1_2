-- ============================================================
-- Verificación de cierre origen vs destino + métricas de la corrida
-- Parámetros psql (-v): esq, vigencia, [zh_ultima=si|no]
-- Salida: una fila "clave|valor" por control o métrica (el orquestador scripts/lote.py la guarda en el
-- manifiesto). Los CONTROLES abortan la corrida si no se cumplen; las métricas solo se informan.
-- ============================================================
\set ON_ERROR_STOP 1
\if :{?zh_ultima} \else \set zh_ultima no \endif
-- Vigencia de zonas homogéneas por tabla: la del parámetro, o con zh_ultima=si la última
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

DROP TABLE IF EXISTS tmp_verif;
CREATE TEMP TABLE tmp_verif(ord serial, k text, v numeric);

INSERT INTO tmp_verif(k, v)
-- ---------- Controles de cierre ----------
SELECT 'avaluo_origen', sum(a.avaluo_catastral)::numeric
FROM :"esq".extavaluo a JOIN :"esq".gc_predio p ON p.id = a.gc_predio_avaluo
WHERE date_part('year', a.vigencia) = :vigencia
UNION ALL SELECT 'avaluo_destino', sum(avaluo_catastral) FROM lev_cat_12.lc_predio WHERE t_id < 6000000000
UNION ALL SELECT 'predios_con_avaluo_vigencia', count(DISTINCT a.gc_predio_avaluo)
  FROM :"esq".extavaluo a JOIN :"esq".gc_predio p ON p.id = a.gc_predio_avaluo WHERE date_part('year', a.vigencia) = :vigencia
UNION ALL SELECT 'predios_migrados', count(*) FROM lev_cat_12.lc_predio WHERE t_id < 6000000000
UNION ALL SELECT 'avaluos_duplicados_vigencia', count(*) FROM (
  SELECT gc_predio_avaluo FROM :"esq".extavaluo
  WHERE date_part('year', vigencia) = :vigencia GROUP BY 1 HAVING count(*) > 1) x
-- Copropiedad: relaciones del origen entre predios migrados vs destino (deben coincidir)
UNION ALL SELECT 'copropiedad_origen', count(DISTINCT c.unidad_predial)
  FROM :"esq".gc_prediocopropiedad c
  JOIN lev_cat_12.lc_predio pu ON pu.t_id = 100000000 + c.unidad_predial
  JOIN lev_cat_12.lc_predio pm ON pm.t_id = 100000000 + c.matriz
UNION ALL SELECT 'copropiedad_destino', count(*) FROM lev_cat_12.lc_predio_copropiedad
-- Zonas homogéneas: idénticas al origen (valores y geometría redondeada a 1 mm). Debe dar 0.
UNION ALL SELECT 'zh_modificadas_vs_backup', (
  SELECT count(*) FROM :"esq".zhf_rural s
  LEFT JOIN lev_cat_12.av_zonahomogeneafisicarural d ON d.t_id = 1800000000 + s.id
  WHERE date_part('year', s.vigencia) = :vig_zhf_rural AND (d.t_id IS NULL
     OR ST_AsBinary(d.geometria) <> ST_AsBinary(ST_Force3D(ST_SnapToGrid(ST_Multi(s.geometria), 0.001)))
     OR (s.codigo, s.codigo_zona_fisica, s.vigencia) IS DISTINCT FROM (d.codigo, d.codigo_zona_fisica, d.vigencia)))
 + (SELECT count(*) FROM :"esq".zhf_urbana s
  LEFT JOIN lev_cat_12.av_zonahomogeneafisicaurbana d ON d.t_id = 1900000000 + s.id
  WHERE date_part('year', s.vigencia) = :vig_zhf_urbana AND (d.t_id IS NULL
     OR ST_AsBinary(d.geometria) <> ST_AsBinary(ST_Force3D(ST_SnapToGrid(ST_Multi(s.geometria), 0.001)))
     OR (s.codigo, s.codigo_zona_fisica, s.vigencia) IS DISTINCT FROM (d.codigo, d.codigo_zona_fisica, d.vigencia)))
 + (SELECT count(*) FROM :"esq".zhg_rural s
  LEFT JOIN lev_cat_12.av_zonahomogeneageoeconomicarural d ON d.t_id = 2000000000 + s.id
  WHERE date_part('year', s.vigencia) = :vig_zhg_rural AND (d.t_id IS NULL
     OR ST_AsBinary(d.geometria) <> ST_AsBinary(ST_Force3D(ST_SnapToGrid(ST_Multi(s.geometria), 0.001)))
     OR (s.codigo, s.codigo_zona_geoeconomica, s.vigencia, round(s.valor_hectarea_agropecuario,1))
        IS DISTINCT FROM (d.codigo, d.codigo_zona_geoeconomica, d.vigencia, d.valor_hectarea)))
 + (SELECT count(*) FROM :"esq".zhg_urbana s
  LEFT JOIN lev_cat_12.av_zonahomogeneageoeconomicaurbana d ON d.t_id = 2100000000 + s.id
  WHERE date_part('year', s.vigencia) = :vig_zhg_urbana AND (d.t_id IS NULL
     OR ST_AsBinary(d.geometria) <> ST_AsBinary(ST_Force3D(ST_SnapToGrid(ST_Multi(s.geometria), 0.001)))
     OR (s.codigo, s.codigo_zona_geoeconomica, s.vigencia, round(s.valor_m2_catastral,1))
        IS DISTINCT FROM (d.codigo, d.codigo_zona_geoeconomica, d.vigencia, d.valor_metro)))
-- ---------- Métricas (se informan, no abortan) ----------
UNION ALL SELECT 'predios_origen_total', count(*) FROM :"esq".gc_predio
UNION ALL SELECT 'predios_cancelados_xtf_ref', count(*) FROM lev_cat_12.lc_predio WHERE t_id >= 6000000000
UNION ALL SELECT 'predios_sin_unidad_espacial', count(*) FROM lev_cat_12.lc_predio p
  WHERE NOT EXISTS (SELECT 1 FROM lev_cat_12.col_uebaunit u WHERE u.baunit = p.t_id)
UNION ALL SELECT 'copropiedad_matrices_coef_distinto_1', count(*) FROM (
  SELECT matriz FROM lev_cat_12.lc_predio_copropiedad GROUP BY 1 HAVING abs(sum(coeficiente) - 1) > 0.001) x
UNION ALL SELECT 'interesados_origen_total', count(*) FROM :"esq".gc_interesado
UNION ALL SELECT 'interesados_sin_derecho_migrado_excluidos', count(*) FROM :"esq".gc_interesado i
  WHERE NOT EXISTS (SELECT 1 FROM lev_cat_12.lc_interesado d WHERE d.t_id = 900000000 + i.id)
UNION ALL SELECT 'imputado_documento_sin_dato', count(*) FROM lev_cat_12.lc_interesado WHERE documento_identidad = 'Sin_Dato'
UNION ALL SELECT 'imputado_interesado_placeholder', count(*) FROM lev_cat_12.lc_interesado
  WHERE t_id >= 5300000000 AND t_id < 5400000000
UNION ALL SELECT 'imputado_rrrfuente_desde_unidadfuente', count(*) FROM lev_cat_12.col_rrrfuente
  WHERE t_id >= 5200000000 AND t_id < 5300000000
UNION ALL SELECT 'imputado_numero_pisos_1', count(*) FROM lev_cat_12.lc_construccion c
  JOIN :"esq".gc_construccion s ON s.id = c.t_id - 400000000
  WHERE c.t_id < 500000000 AND s.numero_pisos IS NULL
UNION ALL SELECT 'imputado_comienzo_vida_util',
    (SELECT count(*) FROM lev_cat_12.lc_terreno d JOIN :"esq".gc_terreno s ON s.id = d.t_id - 300000000
      WHERE d.t_id < 400000000 AND s.comienzo_vida_util_version IS NULL)
  + (SELECT count(*) FROM lev_cat_12.lc_construccion d JOIN :"esq".gc_construccion s ON s.id = d.t_id - 400000000
      WHERE d.t_id < 500000000 AND s.comienzo_vida_util_version IS NULL)
  + (SELECT count(*) FROM lev_cat_12.lc_unidadconstruccion d JOIN :"esq".gc_unidadconstruccion s ON s.id = d.t_id - 500000000
      WHERE d.t_id < 600000000 AND s.comienzo_vida_util_version IS NULL)
  + (SELECT count(*) FROM lev_cat_12.lc_caracteristicasunidadconstruccion d JOIN :"esq".gc_caracteristicasunidadconstruccion s
      ON s.id = d.t_id - 600000000 WHERE d.t_id < 700000000 AND s.comienzo_vida_util_version IS NULL)
  + (SELECT count(*) FROM lev_cat_12.lc_interesado d JOIN :"esq".gc_interesado s ON s.id = d.t_id - 900000000
      WHERE d.t_id < 1000000000 AND s.comienzo_vida_util_version IS NULL)
  + (SELECT count(*) FROM lev_cat_12.lc_derecho d JOIN :"esq".gc_derecho s ON s.id = d.t_id - 1100000000
      WHERE d.t_id < 1200000000 AND s.comienzo_vida_util_version IS NULL)
UNION ALL SELECT 'imputado_area_construida',
    (SELECT count(*) FROM lev_cat_12.lc_construccion d JOIN :"esq".gc_construccion s ON s.id = d.t_id - 400000000
      WHERE d.t_id < 500000000 AND s.area IS NULL)
  + (SELECT count(*) FROM lev_cat_12.lc_unidadconstruccion d JOIN :"esq".gc_unidadconstruccion s ON s.id = d.t_id - 500000000
      WHERE d.t_id < 600000000 AND s.area IS NULL)
  + (SELECT count(*) FROM lev_cat_12.lc_caracteristicasunidadconstruccion d JOIN :"esq".gc_caracteristicasunidadconstruccion s
      ON s.id = d.t_id - 600000000 WHERE d.t_id < 700000000 AND s.area IS NULL)
UNION ALL SELECT 'imputado_area_terreno_geometrica', count(*) FROM lev_cat_12.lc_terreno t
  JOIN :"esq".gc_terreno s ON s.id = t.t_id - 300000000
  WHERE t.t_id < 400000000 AND s.area IS NULL
UNION ALL SELECT 'excluido_uc_sin_construccion_o_caract', count(DISTINCT uc.id) FROM :"esq".gc_unidadconstruccion uc
  JOIN :"esq".col_uebaunit u ON u.ue_gc_unidadconstruccion = uc.id
  JOIN lev_cat_12.lc_predio p ON p.t_id = 100000000 + u.unidad
  WHERE uc.gc_construccion IS NULL OR uc.gc_caracteristicasunidadconstruccion IS NULL
UNION ALL SELECT 'excluido_nomenclatura_sin_tipo_o_numero',
  (SELECT count(*) FROM :"esq".cc_nomenclaturavial WHERE geometria IS NOT NULL)
  - (SELECT count(*) FROM lev_cat_12.cc_nomenclaturavial WHERE t_id >= 2900000000 AND t_id < 3000000000)
UNION ALL SELECT 'excluido_linderos_sin_ue_migrada',
  (SELECT count(*) FROM :"esq".gc_lindero) - (SELECT count(*) FROM lev_cat_12.lc_lindero WHERE t_id < 3500000000)
UNION ALL SELECT 'excluido_linderos_menos_2_puntos', count(*) FROM :"esq".gc_lindero l
  WHERE (SELECT count(*) FROM :"esq".col_puntoccl c WHERE c.ccl = l.id
         AND (c.punto_gc_puntolindero IS NOT NULL OR c.punto_gc_puntolevantamiento IS NOT NULL)) < 2
UNION ALL SELECT 'vigencia_zhf_rural', :vig_zhf_rural
UNION ALL SELECT 'vigencia_zhf_urbana', :vig_zhf_urbana
UNION ALL SELECT 'vigencia_zhg_rural', :vig_zhg_rural
UNION ALL SELECT 'vigencia_zhg_urbana', :vig_zhg_urbana;

-- Conteo por tabla destino (sin catálogos ni metadatos ili2db)
DO $$
DECLARE r record; n bigint;
BEGIN
  FOR r IN SELECT t.table_name FROM information_schema.tables t
           WHERE t.table_schema = 'lev_cat_12' AND t.table_type = 'BASE TABLE' AND t.table_name NOT LIKE 't_ili2db%'
             AND NOT EXISTS (SELECT 1 FROM information_schema.columns c WHERE c.table_schema = t.table_schema
                             AND c.table_name = t.table_name AND c.column_name = 'ilicode')
           ORDER BY 1
  LOOP
    EXECUTE format('SELECT count(*) FROM lev_cat_12.%I', r.table_name) INTO n;
    IF n > 0 THEN INSERT INTO tmp_verif(k, v) VALUES ('conteo.' || r.table_name, n); END IF;
  END LOOP;
END $$;

\pset format unaligned
\pset tuples_only on
SELECT k || '|' || COALESCE(v::text, '') FROM tmp_verif ORDER BY ord;
\pset format aligned
\pset tuples_only off

-- Controles: abortan si no se cumplen
DO $$
DECLARE e text[] := '{}';
  ao numeric := (SELECT v FROM tmp_verif WHERE k = 'avaluo_origen');
  ad numeric := (SELECT v FROM tmp_verif WHERE k = 'avaluo_destino');
  po numeric := (SELECT v FROM tmp_verif WHERE k = 'predios_con_avaluo_vigencia');
  pd numeric := (SELECT v FROM tmp_verif WHERE k = 'predios_migrados');
  dup numeric := (SELECT v FROM tmp_verif WHERE k = 'avaluos_duplicados_vigencia');
  zh numeric := (SELECT v FROM tmp_verif WHERE k = 'zh_modificadas_vs_backup');
  co numeric := (SELECT v FROM tmp_verif WHERE k = 'copropiedad_origen');
  cd numeric := (SELECT v FROM tmp_verif WHERE k = 'copropiedad_destino');
BEGIN
  IF ao IS DISTINCT FROM ad THEN e := e || format('avalúo origen %s <> destino %s', ao, ad); END IF;
  IF po IS DISTINCT FROM pd THEN e := e || format('predios con avalúo %s <> migrados %s', po, pd); END IF;
  IF dup > 0 THEN e := e || format('%s predios con avalúo duplicado en la vigencia', dup); END IF;
  IF zh > 0 THEN e := e || format('%s zonas homogéneas distintas al origen', zh); END IF;
  IF co IS DISTINCT FROM cd THEN e := e || format('copropiedad origen %s <> destino %s', co, cd); END IF;
  IF cardinality(e) > 0 THEN
    RAISE EXCEPTION 'VERIFICACION: %', array_to_string(e, '; ');
  END IF;
  RAISE NOTICE 'VERIFICACION OK';
END $$;

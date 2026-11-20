-- ============================================================
-- Verificación de cierre origen vs destino
-- Parámetros psql (-v): esq, vigencia
-- ============================================================
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
SELECT 'avaluo_origen' k, sum(a.avaluo_catastral)::numeric v
FROM :"esq".extavaluo a JOIN :"esq".gc_predio p ON p.id = a.gc_predio_avaluo
WHERE date_part('year', a.vigencia) = :vigencia
UNION ALL SELECT 'avaluo_destino', sum(avaluo_catastral) FROM lev_cat_12.lc_predio
UNION ALL SELECT 'predios_origen_total', count(*) FROM :"esq".gc_predio
UNION ALL SELECT 'predios_con_avaluo_vigencia', count(DISTINCT a.gc_predio_avaluo)
  FROM :"esq".extavaluo a WHERE date_part('year', a.vigencia) = :vigencia
UNION ALL SELECT 'avaluos_duplicados_vigencia', count(*) FROM (
  SELECT gc_predio_avaluo FROM :"esq".extavaluo
  WHERE date_part('year', vigencia) = :vigencia GROUP BY 1 HAVING count(*) > 1) x
UNION ALL SELECT 'predios_migrados', count(*) FROM lev_cat_12.lc_predio WHERE t_id < 6000000000
UNION ALL SELECT 'predios_cancelados_xtf_ref', count(*) FROM lev_cat_12.lc_predio WHERE t_id >= 6000000000
UNION ALL SELECT 'predios_sin_unidad_espacial', count(*) FROM lev_cat_12.lc_predio p
  WHERE NOT EXISTS (SELECT 1 FROM lev_cat_12.col_uebaunit u WHERE u.baunit = p.t_id)
UNION ALL SELECT 'interesados_doc_sin_dato', count(*) FROM lev_cat_12.lc_interesado
  WHERE documento_identidad = 'Sin_Dato'
-- Copropiedad: relaciones del origen entre predios migrados vs destino (deben coincidir)
UNION ALL SELECT 'copropiedad_origen', count(DISTINCT c.unidad_predial)
  FROM :"esq".gc_prediocopropiedad c
  JOIN lev_cat_12.lc_predio pu ON pu.t_id = 100000000 + c.unidad_predial
  JOIN lev_cat_12.lc_predio pm ON pm.t_id = 100000000 + c.matriz
UNION ALL SELECT 'copropiedad_destino', count(*) FROM lev_cat_12.lc_predio_copropiedad
UNION ALL SELECT 'copropiedad_matrices_coef_distinto_1', count(*) FROM (
  SELECT matriz FROM lev_cat_12.lc_predio_copropiedad GROUP BY 1 HAVING abs(sum(coeficiente) - 1) > 0.001) x
-- Zonas homogéneas: deben ser idénticas al backup (valores y geometría redondeada a 1 mm). Debe dar 0.
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
        IS DISTINCT FROM (d.codigo, d.codigo_zona_geoeconomica, d.vigencia, d.valor_metro)));

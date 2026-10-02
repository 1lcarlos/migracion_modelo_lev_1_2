-- ============================================================
-- Verificación de cierre origen vs destino
-- Parámetros psql (-v): esq, vigencia
-- ============================================================
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
UNION ALL SELECT 'predios_migrados', count(*) FROM lev_cat_12.lc_predio
UNION ALL SELECT 'predios_sin_unidad_espacial', count(*) FROM lev_cat_12.lc_predio p
  WHERE NOT EXISTS (SELECT 1 FROM lev_cat_12.col_uebaunit u WHERE u.baunit = p.t_id)
UNION ALL SELECT 'interesados_doc_sin_dato', count(*) FROM lev_cat_12.lc_interesado
  WHERE documento_identidad = 'Sin_Dato';

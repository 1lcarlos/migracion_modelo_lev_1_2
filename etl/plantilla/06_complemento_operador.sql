-- ============================================================
-- Complemento espacial y de avalúos desde el XTF de referencia (opcional, COMPLEMENTO_OPERADOR=si)
-- Requiere el esquema ref_ope con los tópicos Levantamiento_Catastral, Avaluos y
-- LimitesOperativosCatastro del XTF importados por ili2pg (scripts/migrar.sh, etapa "operador":
-- filtrar_xtf_ref.py -> clon vacío de lev_cat_12 -> ili2pg --import, t_id >= 8·10⁹).
-- Prevalece el backup del gestor: solo se agrega lo que el backup no trae. Se conservan los t_id
-- de ref_ope y los TID del XTF de referencia.
--   1. Terrenos: cada terreno de la referencia se cruza con el migrado del mismo número predial
--      y se acepta solo si la geometría coincide (diferencia simétrica < 0,1 m²) y el par es 1 a 1.
--      Los no cruzados quedan en ref_ope.rep_terrenos_no_cruzados.
--   2. Linderos con al menos un terreno cruzado (col_masCcl/col_menosCcl reapuntados), sus
--      puntos (col_puntoCcl) y todos los LC_PuntoLevantamiento. Las referencias de los puntos a
--      unidades espaciales se reapuntan al terreno cruzado o quedan vacías (son opcionales).
--      Solo si el backup no trae linderos.
--   3. LC_FuenteEspacial (+ ExtArchivo) de predios que existen en la migración, con
--      col_baunitFuente reapuntado por número predial. Se omiten las que ya copió la etapa
--      cancelados (mismo TID).
--   4. AV_ZonaHomogeneaFisicaUrbana y AV_TipologiaConstruccion, solo si la tabla destino está
--      vacía. Las ZHG urbanas no se tocan: el backup trae las de la vigencia.
-- Re-ejecutable (borra t_id >= 8·10⁹). Correr después de 05: la etapa cancelados borra t_id >= 6·10⁹.
-- ============================================================
\set ON_ERROR_STOP 1
BEGIN;

-- Re-ejecutable: quita lo copiado en una corrida anterior
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT c.table_name FROM information_schema.columns c
           JOIN information_schema.tables t ON t.table_schema=c.table_schema AND t.table_name=c.table_name
           WHERE c.table_schema='lev_cat_12' AND c.column_name='t_id' AND t.table_type='BASE TABLE'
             AND c.table_name NOT LIKE 't_ili2db%'
  LOOP
    EXECUTE format('DELETE FROM lev_cat_12.%I WHERE t_id >= 8000000000', r.table_name);
  END LOOP;
END $$;

-- Copia genérica de ref_ope.<tabla> a lev_cat_12.<tabla> (mismas columnas: ref_ope es un clon)
-- de las filas cuyo t_id está en ids; t_basket pasa al basket destino. Devuelve las filas copiadas.
CREATE FUNCTION pg_temp.copiar(tabla text, ids bigint[], basket int) RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE cols text; sel text; n bigint;
BEGIN
  SELECT string_agg(quote_ident(column_name), ', ' ORDER BY ordinal_position),
         string_agg(CASE WHEN column_name = 't_basket' THEN basket::text ELSE quote_ident(column_name) END,
                    ', ' ORDER BY ordinal_position)
    INTO cols, sel
  FROM information_schema.columns WHERE table_schema = 'ref_ope' AND table_name = tabla;
  EXECUTE format('INSERT INTO lev_cat_12.%I (%s) SELECT %s FROM ref_ope.%I WHERE t_id = ANY ($1)',
                 tabla, cols, sel, tabla) USING ids;
  GET DIAGNOSTICS n = ROW_COUNT;
  RAISE NOTICE 'operador: % -> % filas', tabla, n;
  RETURN n;
END $$;

-- ------------------------------------------------------------
-- 1. Cruce de terrenos (referencia -> migrado) por número predial y geometría
-- ------------------------------------------------------------
CREATE TEMP TABLE ope_terreno AS
SELECT DISTINCT ON (t.t_id, p.numero_predial) t.t_id, t.t_ili_tid, p.numero_predial, t.geometria
FROM ref_ope.lc_terreno t
JOIN ref_ope.col_uebaunit u ON u.ue_lc_terreno = t.t_id
JOIN ref_ope.lc_predio p ON p.t_id = u.baunit;

CREATE TEMP TABLE mig_terreno AS
SELECT DISTINCT ON (t.t_id, p.numero_predial) t.t_id, p.numero_predial, t.geometria
FROM lev_cat_12.lc_terreno t
JOIN lev_cat_12.col_uebaunit u ON u.ue_lc_terreno = t.t_id
JOIN lev_cat_12.lc_predio p ON p.t_id = u.baunit
WHERE t.t_id < 8000000000;

CREATE TEMP TABLE cand_terreno AS
SELECT o.t_id AS ref_tid, m.t_id, o.numero_predial,
       ST_Area(ST_SymDifference(ST_MakeValid(ST_Force2D(o.geometria)), ST_MakeValid(ST_Force2D(m.geometria)))) AS dif
FROM ope_terreno o JOIN mig_terreno m USING (numero_predial);

CREATE TEMP TABLE map_terreno AS
SELECT DISTINCT ref_tid, t_id FROM cand_terreno c
WHERE dif < 0.1
  AND (SELECT count(DISTINCT x.t_id) FROM cand_terreno x WHERE x.ref_tid = c.ref_tid AND x.dif < 0.1) = 1
  AND (SELECT count(DISTINCT x.ref_tid) FROM cand_terreno x WHERE x.t_id = c.t_id AND x.dif < 0.1) = 1;

DROP TABLE IF EXISTS ref_ope.rep_terrenos_no_cruzados;
CREATE TABLE ref_ope.rep_terrenos_no_cruzados AS
SELECT o.t_id AS ref_tid, o.t_ili_tid, string_agg(DISTINCT o.numero_predial, '; ') AS numeros_prediales,
       CASE WHEN NOT EXISTS (SELECT 1 FROM cand_terreno c WHERE c.ref_tid = o.t_id)
            THEN 'Predio sin terreno en la migración'
            WHEN EXISTS (SELECT 1 FROM cand_terreno c WHERE c.ref_tid = o.t_id AND c.dif < 0.1)
            THEN 'Cruce ambiguo (no 1 a 1)'
            ELSE 'Geometría distinta a la del gestor' END AS motivo,
       (SELECT round(min(c.dif)::numeric, 2) FROM cand_terreno c WHERE c.ref_tid = o.t_id) AS dif_m2,
       round(max(ST_Area(o.geometria))::numeric, 2) AS area_ref_m2,
       (SELECT round(ST_Area(m.geometria)::numeric, 2) FROM cand_terreno c JOIN mig_terreno m ON m.t_id = c.t_id
         WHERE c.ref_tid = o.t_id ORDER BY c.dif LIMIT 1) AS area_gestor_m2
FROM ope_terreno o
WHERE o.t_id NOT IN (SELECT ref_tid FROM map_terreno)
GROUP BY o.t_id, o.t_ili_tid;

-- ------------------------------------------------------------
-- 2. Linderos y puntos (solo si el backup no trae linderos)
-- ------------------------------------------------------------
CREATE TEMP TABLE sel_lindero AS
SELECT DISTINCT ccl_mas AS t_id FROM ref_ope.col_masccl c JOIN map_terreno m ON m.ref_tid = c.ue_mas_lc_terreno
UNION
SELECT DISTINCT ccl_menos FROM ref_ope.col_menosccl c JOIN map_terreno m ON m.ref_tid = c.ue_menos_lc_terreno;
DELETE FROM sel_lindero WHERE EXISTS (SELECT 1 FROM lev_cat_12.lc_lindero);

CREATE TEMP TABLE sel_puntoccl AS
SELECT t_id FROM ref_ope.col_puntoccl WHERE ccl IN (SELECT t_id FROM sel_lindero);
CREATE TEMP TABLE sel_puntolindero AS
SELECT DISTINCT punto_lc_puntolindero AS t_id FROM ref_ope.col_puntoccl
WHERE t_id IN (SELECT t_id FROM sel_puntoccl) AND punto_lc_puntolindero IS NOT NULL;
CREATE TEMP TABLE sel_puntolev AS
SELECT t_id FROM ref_ope.lc_puntolevantamiento
WHERE NOT EXISTS (SELECT 1 FROM lev_cat_12.lc_puntolevantamiento);

SELECT pg_temp.copiar('lc_lindero', ARRAY(SELECT t_id FROM sel_lindero), 1);
SELECT pg_temp.copiar('lc_puntolindero', ARRAY(SELECT t_id FROM sel_puntolindero), 1);
SELECT pg_temp.copiar('lc_puntolevantamiento', ARRAY(SELECT t_id FROM sel_puntolev), 1);
SELECT pg_temp.copiar('col_puntoccl', ARRAY(SELECT t_id FROM sel_puntoccl), 1);

INSERT INTO lev_cat_12.col_masccl (t_id, t_basket, ccl_mas, ue_mas_lc_terreno)
SELECT c.t_id, 1, c.ccl_mas, m.t_id
FROM ref_ope.col_masccl c JOIN map_terreno m ON m.ref_tid = c.ue_mas_lc_terreno
WHERE c.ccl_mas IN (SELECT t_id FROM sel_lindero);
INSERT INTO lev_cat_12.col_menosccl (t_id, t_basket, ccl_menos, ue_menos_lc_terreno)
SELECT c.t_id, 1, c.ccl_menos, m.t_id
FROM ref_ope.col_menosccl c JOIN map_terreno m ON m.ref_tid = c.ue_menos_lc_terreno
WHERE c.ccl_menos IN (SELECT t_id FROM sel_lindero);

-- Referencia de los puntos a la unidad espacial (col_puntoReferencia, opcional): solo terrenos cruzados
DO $$
DECLARE tabla text; col text;
BEGIN
  FOREACH tabla IN ARRAY ARRAY['lc_puntolindero', 'lc_puntolevantamiento'] LOOP
    EXECUTE format('UPDATE lev_cat_12.%I p SET ue_lc_terreno = m.t_id FROM map_terreno m
                    WHERE p.t_id >= 8000000000 AND p.ue_lc_terreno = m.ref_tid', tabla);
    EXECUTE format('UPDATE lev_cat_12.%I SET ue_lc_terreno = NULL
                    WHERE t_id >= 8000000000 AND ue_lc_terreno >= 8000000000', tabla);
    FOREACH col IN ARRAY ARRAY['ue_lc_construccion', 'ue_lc_servidumbretransito', 'ue_lc_unidadconstruccion',
                               'ue_lc_nu_espaciojuridicoredservicios', 'ue_lc_nu_espaciojuridicounidadedificacion'] LOOP
      EXECUTE format('UPDATE lev_cat_12.%I SET %I = NULL WHERE t_id >= 8000000000 AND %I IS NOT NULL', tabla, col, col);
    END LOOP;
  END LOOP;
END $$;

-- ------------------------------------------------------------
-- 3. Fuentes espaciales de predios migrados (col_baunitFuente por número predial)
-- ------------------------------------------------------------
CREATE TEMP TABLE map_predio AS
SELECT DISTINCT ON (r.t_id) r.t_id AS ref_tid, l.t_id
FROM ref_ope.lc_predio r JOIN lev_cat_12.lc_predio l ON l.numero_predial = r.numero_predial
ORDER BY r.t_id, l.t_id;

CREATE TEMP TABLE sel_baunitfuente AS
SELECT b.t_id, b.fuente_espacial, m.t_id AS predio
FROM ref_ope.col_baunitfuente b
JOIN map_predio m ON m.ref_tid = b.unidad
JOIN ref_ope.lc_fuenteespacial f ON f.t_id = b.fuente_espacial
WHERE NOT EXISTS (SELECT 1 FROM lev_cat_12.lc_fuenteespacial x WHERE x.t_ili_tid = f.t_ili_tid);
CREATE TEMP TABLE sel_fuenteesp AS SELECT DISTINCT fuente_espacial AS t_id FROM sel_baunitfuente;

SELECT pg_temp.copiar('lc_fuenteespacial', ARRAY(SELECT t_id FROM sel_fuenteesp), 1);
SELECT pg_temp.copiar('extarchivo',
  ARRAY(SELECT t_id FROM ref_ope.extarchivo WHERE lc_fuenteespacial_ext_archivo_id IN (SELECT t_id FROM sel_fuenteesp)), 1);
INSERT INTO lev_cat_12.col_baunitfuente (t_id, t_basket, fuente_espacial, unidad)
SELECT t_id, 1, fuente_espacial, predio FROM sel_baunitfuente;

-- ------------------------------------------------------------
-- 4. Avalúos: ZHF urbanas y tipologías, solo si el backup no las trae (basket Avaluos)
-- ------------------------------------------------------------
SELECT pg_temp.copiar('av_zonahomogeneafisicaurbana',
  ARRAY(SELECT t_id FROM ref_ope.av_zonahomogeneafisicaurbana
        WHERE NOT EXISTS (SELECT 1 FROM lev_cat_12.av_zonahomogeneafisicaurbana)),
  (SELECT t_id FROM lev_cat_12.t_ili2db_basket WHERE topic = 'Submodelo_Avaluos_V1_2.Avaluos')::int);
SELECT pg_temp.copiar('av_tipologiaconstruccion',
  ARRAY(SELECT t_id FROM ref_ope.av_tipologiaconstruccion
        WHERE NOT EXISTS (SELECT 1 FROM lev_cat_12.av_tipologiaconstruccion)),
  (SELECT t_id FROM lev_cat_12.t_ili2db_basket WHERE topic = 'Submodelo_Avaluos_V1_2.Avaluos')::int);

SELECT setval('lev_cat_12.t_ili2db_seq', GREATEST(9000000000, (SELECT last_value FROM lev_cat_12.t_ili2db_seq)), false);
COMMIT;

-- Resumen: referencia vs copiado
SELECT 'terrenos_ref' k, (SELECT count(*) FROM ope_terreno) ref, (SELECT count(*) FROM map_terreno) copiados
UNION ALL SELECT 'terrenos_no_cruzados', (SELECT count(*) FROM ref_ope.rep_terrenos_no_cruzados), 0
UNION ALL SELECT 'lc_lindero', (SELECT count(*) FROM ref_ope.lc_lindero),
  (SELECT count(*) FROM lev_cat_12.lc_lindero WHERE t_id >= 8000000000)
UNION ALL SELECT 'col_masccl', (SELECT count(*) FROM ref_ope.col_masccl),
  (SELECT count(*) FROM lev_cat_12.col_masccl WHERE t_id >= 8000000000)
UNION ALL SELECT 'col_menosccl', (SELECT count(*) FROM ref_ope.col_menosccl),
  (SELECT count(*) FROM lev_cat_12.col_menosccl WHERE t_id >= 8000000000)
UNION ALL SELECT 'col_puntoccl', (SELECT count(*) FROM ref_ope.col_puntoccl),
  (SELECT count(*) FROM lev_cat_12.col_puntoccl WHERE t_id >= 8000000000)
UNION ALL SELECT 'lc_puntolindero', (SELECT count(*) FROM ref_ope.lc_puntolindero),
  (SELECT count(*) FROM lev_cat_12.lc_puntolindero WHERE t_id >= 8000000000)
UNION ALL SELECT 'lc_puntolevantamiento', (SELECT count(*) FROM ref_ope.lc_puntolevantamiento),
  (SELECT count(*) FROM lev_cat_12.lc_puntolevantamiento WHERE t_id >= 8000000000)
UNION ALL SELECT 'lc_fuenteespacial', (SELECT count(*) FROM ref_ope.lc_fuenteespacial),
  (SELECT count(*) FROM lev_cat_12.lc_fuenteespacial)
UNION ALL SELECT 'col_baunitfuente', (SELECT count(*) FROM ref_ope.col_baunitfuente),
  (SELECT count(*) FROM lev_cat_12.col_baunitfuente)
UNION ALL SELECT 'av_zonahomogeneafisicaurbana', (SELECT count(*) FROM ref_ope.av_zonahomogeneafisicaurbana),
  (SELECT count(*) FROM lev_cat_12.av_zonahomogeneafisicaurbana)
UNION ALL SELECT 'av_tipologiaconstruccion', (SELECT count(*) FROM ref_ope.av_tipologiaconstruccion),
  (SELECT count(*) FROM lev_cat_12.av_tipologiaconstruccion);

SELECT motivo, count(*) n FROM ref_ope.rep_terrenos_no_cruzados GROUP BY 1 ORDER BY 1;

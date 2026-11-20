-- ============================================================
-- Predios cancelados tomados de un XTF de referencia (opcional, por municipio)
-- Requiere el esquema ref_canc con los objetos importados por ili2pg (ver scripts/migrar.sh,
-- etapa "cancelados": extraer_cancelados_xtf.py -> clon vacío de lev_cat_12 -> ili2pg --import).
-- Copia a lev_cat_12 todas las tablas con datos de ref_canc (mismos t_id >= 6·10⁹ y TID):
--   * Interesados que ya existen en lev_cat_12 (mismo tipo y número de documento, distinto de 0,
--     comparado sin espacios ni espacios no separables) no se duplican: toda referencia se
--     reapunta al existente. Los repetidos dentro de la propia referencia se unen.
--   * Correcciones de calidad sobre lo copiado (observaciones SNR): direcciones repetidas,
--     una dirección principal por predio, fuentes repetidas en un derecho y tipo de agrupación.
--   * Id_Operacion (UNIQUE): <prefijo>C<consecutivo>.
-- Parámetros psql (-v): prefijo. Ejecutar después de 01_migracion (y de 04 si aplica).
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
    EXECUTE format('DELETE FROM lev_cat_12.%I WHERE t_id >= 6000000000', r.table_name);
  END LOOP;
END $$;

-- Número de documento sin espacios ni espacios no separables (U+00A0), en ambos lados del cruce
UPDATE ref_canc.lc_interesado
   SET documento_identidad = regexp_replace(documento_identidad, '[\s' || chr(160) || ']', '', 'g')
 WHERE documento_identidad ~ ('[\s' || chr(160) || ']');

-- Interesados de la referencia que ya existen en la migración (se calcula antes de copiar).
-- Si no existen, los repetidos dentro de la propia referencia se unen en el de menor t_id.
CREATE TEMP TABLE map_int ON COMMIT DROP AS
SELECT DISTINCT ON (r.t_id) r.t_id AS ref_tid, l.t_id
FROM ref_canc.lc_interesado r
JOIN lev_cat_12.lc_interesado l
  ON l.tipo_documento = r.tipo_documento
 AND regexp_replace(l.documento_identidad, '[\s' || chr(160) || ']', '', 'g') = r.documento_identidad
WHERE ltrim(r.documento_identidad, '0') <> '' AND l.t_id < 6000000000
ORDER BY r.t_id, l.t_id;

INSERT INTO map_int (ref_tid, t_id)
SELECT r.t_id, min(r.t_id) OVER (PARTITION BY r.tipo_documento, r.documento_identidad)
FROM ref_canc.lc_interesado r
WHERE ltrim(r.documento_identidad, '0') <> ''
  AND NOT EXISTS (SELECT 1 FROM map_int m WHERE m.ref_tid = r.t_id);
DELETE FROM map_int WHERE ref_tid = t_id;

-- Id_Operacion propio del municipio
UPDATE ref_canc.lc_predio p SET id_operacion = :'prefijo' || 'C' || lpad(x.n::text, 4, '0')
FROM (SELECT t_id, row_number() OVER (ORDER BY numero_predial) n FROM ref_canc.lc_predio) x
WHERE x.t_id = p.t_id;

-- Copia genérica: columnas comunes, basket -> 1 (Levantamiento_Catastral)
DO $$
DECLARE r record; cols text; sel text; n bigint;
BEGIN
  FOR r IN SELECT t.table_name FROM information_schema.tables t
           WHERE t.table_schema='ref_canc' AND t.table_type='BASE TABLE'
             AND t.table_name NOT LIKE 't_ili2db%'
             AND NOT EXISTS (SELECT 1 FROM information_schema.columns c
                             WHERE c.table_schema='ref_canc' AND c.table_name=t.table_name AND c.column_name='ilicode')
  LOOP
    EXECUTE format('SELECT count(*) FROM ref_canc.%I', r.table_name) INTO n;
    CONTINUE WHEN n = 0;
    SELECT string_agg(quote_ident(column_name), ', ' ORDER BY ordinal_position),
           string_agg(CASE WHEN column_name='t_basket' THEN '1' ELSE quote_ident(column_name) END, ', ' ORDER BY ordinal_position)
      INTO cols, sel
    FROM information_schema.columns WHERE table_schema='ref_canc' AND table_name=r.table_name;
    EXECUTE format('INSERT INTO lev_cat_12.%I (%s) SELECT %s FROM ref_canc.%I', r.table_name, cols, sel, r.table_name);
    RAISE NOTICE 'cancelados: % -> % filas', r.table_name, n;
  END LOOP;
END $$;

-- Reapuntar al interesado conservado toda referencia (derechos, miembros, contactos, etc.)
-- y quitar el duplicado copiado. Los miembros repetidos que resulten los depura 02_fix.
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT c.conrelid::regclass AS tabla, a.attname AS col
             FROM pg_constraint c
             JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)
            WHERE c.contype = 'f' AND c.confrelid = 'lev_cat_12.lc_interesado'::regclass
  LOOP
    EXECUTE format('UPDATE %s x SET %I = m.t_id FROM map_int m WHERE x.%I = m.ref_tid', r.tabla, r.col, r.col);
  END LOOP;
END $$;
DELETE FROM lev_cat_12.lc_interesado i USING map_int m WHERE i.t_id = m.ref_tid;

-- ------------------------------------------------------------
-- Correcciones de calidad sobre los objetos copiados (t_id >= 6·10⁹). El XTF de referencia
-- trae defectos que la SNR observó; se corrigen aquí porque estos predios no están en el backup.
-- ------------------------------------------------------------
-- a) Direcciones repetidas en el mismo predio: se conserva la de menor t_seq
DELETE FROM lev_cat_12.extdireccion d
USING lev_cat_12.extdireccion o
WHERE d.t_id >= 6000000000 AND o.t_id >= 6000000000
  AND o.lc_predio_direccion = d.lc_predio_direccion
  AND (o.t_seq, o.t_id) < (d.t_seq, d.t_id)
  AND (o.tipo_direccion, o.clase_via_principal, o.sector_ciudad, o.sector_predio,
       upper(trim(o.valor_via_principal)), upper(trim(o.letra_via_principal)),
       upper(trim(o.valor_via_generadora)), upper(trim(o.letra_via_generadora)),
       upper(trim(o.numero_predio)), upper(trim(o.complemento)), upper(trim(o.nombre_predio)),
       upper(trim(o.codigo_postal)))
      IS NOT DISTINCT FROM
      (d.tipo_direccion, d.clase_via_principal, d.sector_ciudad, d.sector_predio,
       upper(trim(d.valor_via_principal)), upper(trim(d.letra_via_principal)),
       upper(trim(d.valor_via_generadora)), upper(trim(d.letra_via_generadora)),
       upper(trim(d.numero_predio)), upper(trim(d.complemento)), upper(trim(d.nombre_predio)),
       upper(trim(d.codigo_postal)));

-- b) Exactamente una dirección principal por predio (la primera si no hay una sola marcada)
--    y t_seq consecutivo tras las eliminaciones
UPDATE lev_cat_12.extdireccion d
   SET es_direccion_principal = (x.orden = 1), t_seq = x.orden - 1
FROM (SELECT t_id, row_number() OVER (PARTITION BY lc_predio_direccion
                                      ORDER BY coalesce(es_direccion_principal, false) DESC, t_seq, t_id) AS orden
        FROM lev_cat_12.extdireccion
       WHERE t_id >= 6000000000 AND lc_predio_direccion IS NOT NULL) x
WHERE x.t_id = d.t_id;

-- c) Fuentes repetidas en el mismo derecho (mismo tipo, número, fecha y ente): una sola
CREATE TEMP TABLE canc_fuente_rep ON COMMIT DROP AS
SELECT r.t_id AS rrr_tid, r.fuente_administrativa AS repetida,
       min(r.fuente_administrativa) OVER (PARTITION BY r.rrr_lc_derecho, f.tipo, upper(trim(f.numero_fuente)),
                                          f.fecha_documento_fuente, upper(trim(f.ente_emisor))) AS conservada
FROM lev_cat_12.col_rrrfuente r
JOIN lev_cat_12.lc_fuenteadministrativa f ON f.t_id = r.fuente_administrativa
WHERE r.t_id >= 6000000000 AND r.rrr_lc_derecho IS NOT NULL;
DELETE FROM canc_fuente_rep WHERE repetida = conservada;
DELETE FROM lev_cat_12.col_rrrfuente r USING canc_fuente_rep x WHERE r.t_id = x.rrr_tid;
UPDATE lev_cat_12.extarchivo a SET lc_fuenteadministrtiva_ext_archivo_id = x.conservada
FROM canc_fuente_rep x
WHERE a.lc_fuenteadministrtiva_ext_archivo_id = x.repetida
  AND NOT EXISTS (SELECT 1 FROM lev_cat_12.col_rrrfuente r WHERE r.fuente_administrativa = x.repetida);
DELETE FROM lev_cat_12.col_unidadfuente u USING canc_fuente_rep x
WHERE u.fuente_administrativa = x.repetida
  AND NOT EXISTS (SELECT 1 FROM lev_cat_12.col_rrrfuente r WHERE r.fuente_administrativa = x.repetida);
DELETE FROM lev_cat_12.lc_fuenteadministrativa f USING canc_fuente_rep x
WHERE f.t_id = x.repetida AND f.t_id >= 6000000000
  AND NOT EXISTS (SELECT 1 FROM lev_cat_12.col_rrrfuente r WHERE r.fuente_administrativa = f.t_id);

-- d) Tipo de agrupación según sus miembros: solo naturales -> Grupo_Civil, solo jurídicas ->
--    Grupo_Empresarial, ambas -> Grupo_Mixto (Grupo_Etnico no se modifica)
UPDATE lev_cat_12.lc_agrupacioninteresados a
   SET tipo = (SELECT g.t_id FROM lev_cat_12.col_grupointeresadotipo g WHERE g.ilicode = x.esperado)
FROM (SELECT m.agrupacion,
             CASE WHEN bool_and(t.ilicode = 'Persona_Natural') THEN 'Grupo_Civil'
                  WHEN bool_and(t.ilicode = 'Persona_Juridica') THEN 'Grupo_Empresarial'
                  ELSE 'Grupo_Mixto' END AS esperado
        FROM lev_cat_12.col_miembros m
        JOIN lev_cat_12.lc_interesado i ON i.t_id = m.interesado_lc_interesado
        JOIN lev_cat_12.lc_interesadotipo t ON t.t_id = i.tipo
       WHERE m.agrupacion >= 6000000000
       GROUP BY m.agrupacion) x
WHERE a.t_id = x.agrupacion
  AND a.tipo IS DISTINCT FROM (SELECT g.t_id FROM lev_cat_12.col_grupointeresadotipo g WHERE g.ilicode = x.esperado)
  AND a.tipo IS DISTINCT FROM (SELECT g.t_id FROM lev_cat_12.col_grupointeresadotipo g WHERE g.ilicode = 'Grupo_Etnico');

SELECT setval('lev_cat_12.t_ili2db_seq', GREATEST(7000000000, (SELECT max(t_id)+1 FROM lev_cat_12.lc_predio)), false);
COMMIT;

-- Resumen
SELECT 'predios_cancelados' k, count(*) n FROM lev_cat_12.lc_predio WHERE t_id >= 6000000000
UNION ALL SELECT 'derechos', count(*) FROM lev_cat_12.lc_derecho WHERE t_id >= 6000000000
UNION ALL SELECT 'interesados_nuevos', count(*) FROM lev_cat_12.lc_interesado WHERE t_id >= 6000000000
UNION ALL SELECT 'derechos_a_interesado_existente', count(*) FROM lev_cat_12.lc_derecho
  WHERE t_id >= 6000000000 AND interesado_lc_interesado < 6000000000
UNION ALL SELECT 'direcciones', count(*) FROM lev_cat_12.extdireccion WHERE t_id >= 6000000000
UNION ALL SELECT 'predios_sin_1_direccion_principal', count(*) FROM lev_cat_12.lc_predio p
  WHERE p.t_id >= 6000000000 AND (SELECT count(*) FROM lev_cat_12.extdireccion d
                                   WHERE d.lc_predio_direccion = p.t_id AND d.es_direccion_principal) <> 1
UNION ALL SELECT 'novedad_cancelacion', count(*) FROM lev_cat_12.lc_estructuranovedadnumeropredial n
  JOIN lev_cat_12.lc_estructuranovedadnumeropredial_tipo_novedad e ON e.t_id = n.tipo_novedad
  WHERE e.ilicode = 'Cancelacion';

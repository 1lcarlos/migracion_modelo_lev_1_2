-- ============================================================
-- Tabla de homologaciones de dominio (config/homologaciones.csv) y función fx_hom.
-- Correr desde la raíz del proyecto antes de 00_check_dominios y de 01_migracion.
-- fx_hom(dominio_destino, valor_origen) devuelve el ilicode homologado o el mismo valor si no hay
-- regla: las reglas son explícitas, versionadas y auditables (columna decision), no CASE en el ETL.
-- ============================================================
\set ON_ERROR_STOP 1
\encoding UTF8
CREATE TABLE IF NOT EXISTS public.mig_homologacion(
  dominio text NOT NULL, valor_origen text NOT NULL, valor_destino text NOT NULL, decision text,
  PRIMARY KEY (dominio, valor_origen));
TRUNCATE public.mig_homologacion;
\copy public.mig_homologacion(dominio, valor_origen, valor_destino, decision) FROM 'config/homologaciones.csv' WITH (FORMAT csv, HEADER true, DELIMITER ';', ENCODING 'UTF8')

CREATE OR REPLACE FUNCTION public.fx_hom(p_dominio text, p_valor text)
RETURNS text LANGUAGE sql STABLE AS $f$
  SELECT COALESCE((SELECT h.valor_destino FROM public.mig_homologacion h
                   WHERE h.dominio = p_dominio AND h.valor_origen = p_valor), p_valor)
$f$;

-- Resuelve el t_id de un dominio destino a partir del valor origen: ilicode exacto,
-- ilicode con ruta (ej. 'Construccion' -> 'Catastro.Construccion') o dispname (texto libre).
CREATE OR REPLACE FUNCTION public.fx_dom(p_tabla text, p_valor text)
RETURNS bigint LANGUAGE plpgsql STABLE AS $f$
DECLARE r bigint;
BEGIN
  IF p_valor IS NULL OR btrim(p_valor) = '' THEN RETURN NULL; END IF;
  EXECUTE format($q$
    SELECT t_id FROM lev_cat_12.%I
    WHERE ilicode = $1 OR ilicode LIKE '%%.' || $1
       OR lower(regexp_replace(dispname, '[–—]', '-', 'g')) = lower(regexp_replace(btrim($1), '[–—]', '-', 'g'))
    ORDER BY (ilicode = $1) DESC, (thisclass ILIKE '%%Lev_Cat%%') DESC, t_id
    LIMIT 1$q$, p_tabla) INTO r USING p_valor;
  RETURN r;
END $f$;

-- Toda regla debe apuntar a un ilicode existente en el dominio destino
DO $$
DECLARE r record; ok boolean;
BEGIN
  FOR r IN SELECT * FROM public.mig_homologacion LOOP
    IF to_regclass('lev_cat_12.' || r.dominio) IS NULL THEN
      RAISE EXCEPTION 'Homologación: dominio destino % no existe en lev_cat_12', r.dominio;
    END IF;
    EXECUTE format('SELECT EXISTS (SELECT 1 FROM lev_cat_12.%I WHERE ilicode = $1)', r.dominio) INTO ok USING r.valor_destino;
    IF NOT ok THEN
      RAISE EXCEPTION 'Homologación: % no es ilicode de %', r.valor_destino, r.dominio;
    END IF;
  END LOOP;
END $$;
SELECT count(*) AS reglas_homologacion FROM public.mig_homologacion;

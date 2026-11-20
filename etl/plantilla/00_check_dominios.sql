-- Verifica que todo código de dominio usado en los datos origen tenga equivalente (ilicode) en el
-- dominio destino, aplicando las homologaciones de config/homologaciones.csv (fx_hom; correr antes
-- 00_homologaciones.sql). Parámetros psql: -v esq=<esquema origen> -v vigencia=<año>
--   [-v zh_ultima=si] (ZH de la última vigencia <= año, por tabla)  [-v estricto=1] (aborta si hay códigos
--   sin equivalente; las ZHF son solo aviso: decisión Nemocón 2026-10-14, no se adivinan homologaciones)
\if :{?zh_ultima} \else \set zh_ultima no \endif
SELECT set_config('mig.esq', :'esq', false);
SELECT set_config('mig.zh_ultima', :'zh_ultima', false);
DROP TABLE IF EXISTS tmp_dom_check;
CREATE TEMP TABLE tmp_dom_check(uso text, tgt_enum text, code text, n bigint, existe boolean);

DO $$
DECLARE
  r record;
  esq text := current_setting('mig.esq');
BEGIN
  FOR r IN SELECT * FROM (VALUES
   ('gc_prediotipo','col_unidadadministrativabasicatipo','gc_predio','tipo','exacto'),
   ('gc_condicionprediotipo','lc_condicionprediotipo','gc_predio','condicion_predio','exacto'),
   ('gc_destinacioneconomicatipo','lc_destinacioneconomicatipo','gc_predio','destinacion_economica','exacto'),
   ('gc_clasesuelotipo','lc_clasesuelotipo','gc_predio','clase_suelo','exacto'),
   ('gc_categoriasuelotipo','lc_categoriasuelotipo','gc_predio','categoria_suelo','exacto'),
   ('gc_derechotipo','lc_derechotipo','gc_derecho','tipo','exacto'),
   ('gc_interesadotipo','lc_interesadotipo','gc_interesado','tipo','exacto'),
   ('gc_interesadodocumentotipo','lc_interesadodocumentotipo','gc_interesado','tipo_documento','exacto'),
   ('gc_sexotipo','lc_sexotipo','gc_interesado','sexo','exacto'),
   ('gc_grupoetnicotipo','lc_grupoetnicotipo','gc_interesado','grupo_etnico','exacto'),
   ('gc_estadociviltipo','lc_estadociviltipo','gc_interesado','estado_civil','exacto'),
   ('col_grupointeresadotipo','col_grupointeresadotipo','gc_agrupacioninteresados','tipo','exacto'),
   ('gc_fuenteadministrativatipo','col_fuenteadministrativatipo','gc_fuenteadministrativa','tipo','exacto'),
   ('col_estadodisponibilidadtipo','col_estadodisponibilidadtipo','gc_fuenteadministrativa','estado_disponibilidad','exacto'),
   ('gc_construcciontipo','lc_construcciontipo','gc_construccion','tipo_construccion','exacto'),
   ('gc_dominioconstrucciontipo','lc_dominioconstrucciontipo','gc_construccion','tipo_dominio','exacto'),
   ('gc_construcciontipo','lc_construcciontipo','gc_caracteristicasunidadconstruccion','tipo_construccion','exacto'),
   ('gc_dominioconstrucciontipo','lc_dominioconstrucciontipo','gc_caracteristicasunidadconstruccion','tipo_dominio','exacto'),
   ('gc_construccionplantatipo','lc_construccionplantatipo','gc_caracteristicasunidadconstruccion','tipo_planta','exacto'),
   ('gc_unidadconstrucciontipo','lc_unidadconstrucciontipo','gc_caracteristicasunidadconstruccion','tipo_unidad_construccion','exacto'),
   ('gc_usouconstipo','lc_usouconstipo','gc_caracteristicasunidadconstruccion','uso','exacto'),
   ('cuc_tipologiatipo','lc_tipologiatipo','cuc_tipologiaconstruccion','tipo_tipologia','exacto'),
   ('cuc_anexotipo','lc_anexotipo','cuc_calificacionnoconvencional','tipo_anexo','exacto'),
   ('cuc_tipologiatipo','av_tipologiatipo','tb_valortipologia','tipo_tipologia','exacto'),
   ('cuc_anexotipo','av_tipologiatipo','tb_valortipologia','tipo_anexo','exacto'),
   ('extdireccion_tipo_direccion','extdireccion_tipo_direccion','extdireccion','tipo_direccion','exacto'),
   ('extdireccion_clase_via_principal','extdireccion_clase_via_principal','extdireccion','clase_via_principal','exacto'),
   ('extdireccion_sector_ciudad','extdireccion_sector_ciudad','extdireccion','sector_ciudad','exacto'),
   ('extdireccion_sector_predio','extdireccion_sector_predio','extdireccion','sector_predio','exacto'),
   ('cc_nomenclaturavial_tipo_via','cc_nomenclaturavial_tipo_via','cc_nomenclaturavial','tipo_via','exacto'),
   ('gc_puntotipo','col_puntotipo','gc_puntolindero','punto_tipo','fx_dom'),
   ('gc_acuerdotipo','lc_acuerdotipo','gc_puntolindero','acuerdo','fx_dom'),
   ('gc_fotoidentificaciontipo','lc_fotoidentificaciontipo','gc_puntolindero','fotoidentificacion','fx_dom'),
   ('col_metodoproducciontipo','col_metodoproducciontipo','gc_puntolindero','metodo_produccion','fx_dom'),
   ('gc_puntotipo','col_puntotipo','gc_puntolevantamiento','punto_tipo','fx_dom'),
   ('gc_puntolevtipo','lc_puntolevtipo','gc_puntolevantamiento','tipo_punto_levantamiento','fx_dom'),
   ('gc_fotoidentificaciontipo','lc_fotoidentificaciontipo','gc_puntolevantamiento','fotoidentificacion','fx_dom'),
   ('col_metodoproducciontipo','col_metodoproducciontipo','gc_puntolevantamiento','metodo_produccion','fx_dom'),
   ('gc_fuenteespacialtipo','col_fuenteespacialtipo','gc_fuenteespacial','tipo','fx_dom'),
   ('col_estadodisponibilidadtipo','col_estadodisponibilidadtipo','gc_fuenteespacial','estado_disponibilidad','fx_dom'),
   ('extreferenciaregistralsistemaantiguo_tipo_referencia','extreferenciaregistralsistemaantiguo_tipo_referencia','extreferenciaregistralsistemaantiguo','tipo_referencia','fx_dom')
  ) AS v(src_dom, tgt_enum, src_tab, src_col, metodo)
  LOOP
    IF to_regclass(format('%I.%I', esq, r.src_tab)) IS NULL THEN
      RAISE NOTICE 'Tabla origen %.% no existe: se omite', esq, r.src_tab;
      CONTINUE;
    END IF;
    EXECUTE format(
      'INSERT INTO tmp_dom_check
       SELECT %L, %L, d.text_code, count(*),
              CASE WHEN %L = ''fx_dom'' THEN public.fx_dom(%L, public.fx_hom(%L, d.text_code)) IS NOT NULL
                   ELSE EXISTS(SELECT 1 FROM lev_cat_12.%I e WHERE e.ilicode = public.fx_hom(%L, d.text_code)
                     OR (%L = ''col_unidadadministrativabasicatipo'' AND e.ilicode = ''Predio.''||d.text_code)) END
       FROM %I.%I t JOIN %I.%I d ON d.id = t.%I
       GROUP BY d.text_code',
      r.src_tab||'.'||r.src_col, r.tgt_enum, r.metodo, r.tgt_enum, r.tgt_enum, r.tgt_enum, r.tgt_enum, r.tgt_enum, esq, r.src_tab, esq, r.src_dom, r.src_col);
  END LOOP;
END $$;

-- tb_valortipologia: los códigos sin equivalente en AV_TipologiaTipo (anexos) se excluyen por diseño
SELECT uso, tgt_enum, code, n,
       CASE WHEN uso LIKE 'tb_valortipologia.%' THEN 'excluido_por_diseno' ELSE 'SIN_EQUIVALENTE' END AS estado
FROM tmp_dom_check WHERE NOT existe ORDER BY uso, code;

-- Atributos de texto libre que deben coincidir con un ilicode (tras homologación).
-- Zonas físicas: con la vigencia que usa el ETL (exacta o, con zh_ultima=si, la última <= vigencia).
SELECT set_config('mig.vig', :'vigencia', false);
DROP TABLE IF EXISTS tmp_dom_txt;
CREATE TEMP TABLE tmp_dom_txt(uso text, code text, n bigint, existe boolean, severidad text);
DO $$
DECLARE r record; esq text := current_setting('mig.esq'); vig int := current_setting('mig.vig')::int;
  vt int; filtro text;
BEGIN
  FOR r IN SELECT * FROM (VALUES
   ('zhf_rural','disponibilidad_agua','av_disponibilidadaguatipo','aviso'),
   ('zhf_rural','influencia_vial','av_influenciavialruraltipo','aviso'),
   ('zhf_rural','uso_actual_suelo','av_usosueloruraltipo','aviso'),
   ('zhf_urbana','topografia','av_topografiazonatipo','aviso'),
   ('zhf_urbana','influencia_vial','av_influenciavialurbanatipo','aviso'),
   ('zhf_urbana','servicio_publico','av_serviciospublicostipo','aviso'),
   ('zhf_urbana','uso_actual_suelo','av_usosuelourbanotipo','aviso'),
   ('zhf_urbana','tipificacion_construccion','av_tipificacionconstrucciontipo','aviso'),
   ('dlc_datosadicionaleslevantamientocatastral','resultado_visita','lc_resultadovisitatipo','error')
  ) v(tab,col,enum,sev)
  LOOP
    IF to_regclass(format('%I.%I', esq, r.tab)) IS NULL THEN CONTINUE; END IF;
    filtro := 'true';
    IF r.tab LIKE 'zhf_%' THEN
      vt := vig;
      IF current_setting('mig.zh_ultima') = 'si' THEN
        EXECUTE format('SELECT COALESCE(max(date_part(''year'',vigencia))::int, %s) FROM %I.%I WHERE date_part(''year'',vigencia) <= %s',
                       vig, esq, r.tab, vig) INTO vt;
      END IF;
      filtro := format('date_part(''year'', t.vigencia) = %s', vt);
    END IF;
    -- igual que fx_dom en el ETL: ilicode exacto/con ruta o dispname
    EXECUTE format(
      'INSERT INTO tmp_dom_txt SELECT %L, t.%I, count(*),
         EXISTS(SELECT 1 FROM lev_cat_12.%I e WHERE e.ilicode = public.fx_hom(%L, t.%I) OR e.ilicode LIKE ''%%.''||public.fx_hom(%L, t.%I)
                OR lower(e.dispname) = lower(btrim(t.%I))), %L
       FROM %I.%I t WHERE t.%I IS NOT NULL AND btrim(t.%I) <> '''' AND %s GROUP BY t.%I',
      r.tab||'.'||r.col, r.col, r.enum, r.enum, r.col, r.enum, r.col, r.col, r.sev,
      esq, r.tab, r.col, r.col, filtro, r.col);
  END LOOP;
END $$;
SELECT uso, code, n, severidad FROM tmp_dom_txt WHERE NOT existe ORDER BY 1,2;
SELECT count(*) AS total_pares_ok FROM tmp_dom_check WHERE existe;

\if :{?estricto}
DO $$
DECLARE n_err bigint; det text;
BEGIN
  SELECT count(*), string_agg(format('%s=%s (%s)', uso, code, n), '; ') INTO n_err, det FROM (
    SELECT uso, code, n FROM tmp_dom_check WHERE NOT existe AND uso NOT LIKE 'tb_valortipologia.%'
    UNION ALL SELECT uso, code, n FROM tmp_dom_txt WHERE NOT existe AND severidad = 'error') x;
  IF n_err > 0 THEN
    RAISE EXCEPTION 'DOMINIOS: % código(s) sin equivalente en v1.2: %. Decidir la homologación, registrarla en config/homologaciones.csv y documentarla en docs/03', n_err, det;
  END IF;
  RAISE NOTICE 'DOMINIOS OK';
END $$;
\endif

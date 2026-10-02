-- Verifica que todo código de dominio usado en los datos origen exista como ilicode en el enum destino
-- Parámetros psql: -v esq=<esquema origen> -v vigencia=<año>
SELECT set_config('mig.esq', :'esq', false);
DROP TABLE IF EXISTS tmp_dom_check;
CREATE TABLE tmp_dom_check(uso text, tgt_enum text, code text, n bigint, existe boolean);

DO $$
DECLARE
  r record;
  esq text := current_setting('mig.esq');
BEGIN
  FOR r IN SELECT * FROM (VALUES
   ('gc_prediotipo','col_unidadadministrativabasicatipo','gc_predio','tipo'),
   ('gc_condicionprediotipo','lc_condicionprediotipo','gc_predio','condicion_predio'),
   ('gc_destinacioneconomicatipo','lc_destinacioneconomicatipo','gc_predio','destinacion_economica'),
   ('gc_clasesuelotipo','lc_clasesuelotipo','gc_predio','clase_suelo'),
   ('gc_categoriasuelotipo','lc_categoriasuelotipo','gc_predio','categoria_suelo'),
   ('gc_derechotipo','lc_derechotipo','gc_derecho','tipo'),
   ('gc_interesadotipo','lc_interesadotipo','gc_interesado','tipo'),
   ('gc_interesadodocumentotipo','lc_interesadodocumentotipo','gc_interesado','tipo_documento'),
   ('gc_sexotipo','lc_sexotipo','gc_interesado','sexo'),
   ('gc_grupoetnicotipo','lc_grupoetnicotipo','gc_interesado','grupo_etnico'),
   ('gc_estadociviltipo','lc_estadociviltipo','gc_interesado','estado_civil'),
   ('col_grupointeresadotipo','col_grupointeresadotipo','gc_agrupacioninteresados','tipo'),
   ('gc_fuenteadministrativatipo','col_fuenteadministrativatipo','gc_fuenteadministrativa','tipo'),
   ('col_estadodisponibilidadtipo','col_estadodisponibilidadtipo','gc_fuenteadministrativa','estado_disponibilidad'),
   ('gc_construcciontipo','lc_construcciontipo','gc_construccion','tipo_construccion'),
   ('gc_dominioconstrucciontipo','lc_dominioconstrucciontipo','gc_construccion','tipo_dominio'),
   ('gc_construcciontipo','lc_construcciontipo','gc_caracteristicasunidadconstruccion','tipo_construccion'),
   ('gc_dominioconstrucciontipo','lc_dominioconstrucciontipo','gc_caracteristicasunidadconstruccion','tipo_dominio'),
   ('gc_construccionplantatipo','lc_construccionplantatipo','gc_caracteristicasunidadconstruccion','tipo_planta'),
   ('gc_unidadconstrucciontipo','lc_unidadconstrucciontipo','gc_caracteristicasunidadconstruccion','tipo_unidad_construccion'),
   ('gc_usouconstipo','lc_usouconstipo','gc_caracteristicasunidadconstruccion','uso'),
   ('cuc_tipologiatipo','lc_tipologiatipo','cuc_tipologiaconstruccion','tipo_tipologia'),
   ('cuc_anexotipo','lc_anexotipo','cuc_calificacionnoconvencional','tipo_anexo'),
   ('cuc_tipologiatipo','av_tipologiatipo','tb_valortipologia','tipo_tipologia'),
   ('cuc_anexotipo','av_tipologiatipo','tb_valortipologia','tipo_anexo'),
   ('extdireccion_tipo_direccion','extdireccion_tipo_direccion','extdireccion','tipo_direccion'),
   ('extdireccion_clase_via_principal','extdireccion_clase_via_principal','extdireccion','clase_via_principal'),
   ('extdireccion_sector_ciudad','extdireccion_sector_ciudad','extdireccion','sector_ciudad'),
   ('extdireccion_sector_predio','extdireccion_sector_predio','extdireccion','sector_predio'),
   ('cc_nomenclaturavial_tipo_via','cc_nomenclaturavial_tipo_via','cc_nomenclaturavial','tipo_via'),
   ('gc_puntotipo','col_puntotipo','gc_puntolindero','punto_tipo'),
   ('gc_acuerdotipo','lc_acuerdotipo','gc_puntolindero','acuerdo'),
   ('gc_fotoidentificaciontipo','lc_fotoidentificaciontipo','gc_puntolindero','fotoidentificacion'),
   ('col_metodoproducciontipo','col_metodoproducciontipo','gc_puntolindero','metodo_produccion'),
   ('gc_puntotipo','col_puntotipo','gc_puntolevantamiento','punto_tipo'),
   ('gc_puntolevtipo','lc_puntolevtipo','gc_puntolevantamiento','tipo_punto_levantamiento'),
   ('gc_fotoidentificaciontipo','lc_fotoidentificaciontipo','gc_puntolevantamiento','fotoidentificacion'),
   ('col_metodoproducciontipo','col_metodoproducciontipo','gc_puntolevantamiento','metodo_produccion'),
   ('gc_fuenteespacialtipo','col_fuenteespacialtipo','gc_fuenteespacial','tipo'),
   ('col_estadodisponibilidadtipo','col_estadodisponibilidadtipo','gc_fuenteespacial','estado_disponibilidad'),
   ('extreferenciaregistralsistemaantiguo_tipo_referencia','extreferenciaregistralsistemaantiguo_tipo_referencia','extreferenciaregistralsistemaantiguo','tipo_referencia')
  ) AS v(src_dom, tgt_enum, src_tab, src_col)
  LOOP
    IF to_regclass(format('%I.%I', esq, r.src_tab)) IS NULL THEN
      RAISE NOTICE 'Tabla origen %.% no existe: se omite', esq, r.src_tab;
      CONTINUE;
    END IF;
    EXECUTE format(
      'INSERT INTO tmp_dom_check
       SELECT %L, %L, d.text_code, count(*),
              EXISTS(SELECT 1 FROM lev_cat_12.%I e WHERE e.ilicode = d.text_code)
       FROM %I.%I t JOIN %I.%I d ON d.id = t.%I
       GROUP BY d.text_code',
      r.src_tab||'.'||r.src_col, r.tgt_enum, r.tgt_enum, esq, r.src_tab, esq, r.src_dom, r.src_col);
  END LOOP;
END $$;

SELECT uso, tgt_enum, code, n FROM tmp_dom_check WHERE NOT existe ORDER BY uso, code;

-- Zonas físicas: atributos de texto libre que deben coincidir con un ilicode del dominio destino
SELECT set_config('mig.vig', :'vigencia', false);
DROP TABLE IF EXISTS tmp_dom_zhf;
CREATE TABLE tmp_dom_zhf(uso text, code text, n bigint, existe boolean);
DO $$
DECLARE r record; esq text := current_setting('mig.esq');
BEGIN
  FOR r IN SELECT * FROM (VALUES
   ('zhf_rural','disponibilidad_agua','av_disponibilidadaguatipo'),
   ('zhf_rural','influencia_vial','av_influenciavialruraltipo'),
   ('zhf_rural','uso_actual_suelo','av_usosueloruraltipo'),
   ('zhf_urbana','topografia','av_topografiazonatipo'),
   ('zhf_urbana','influencia_vial','av_influenciavialurbanatipo'),
   ('zhf_urbana','servicio_publico','av_serviciospublicostipo'),
   ('zhf_urbana','uso_actual_suelo','av_usosuelourbanotipo'),
   ('zhf_urbana','tipificacion_construccion','av_tipificacionconstrucciontipo')) v(tab,col,enum)
  LOOP
    EXECUTE format(
      'INSERT INTO tmp_dom_zhf SELECT %L, t.%I, count(*),
         EXISTS(SELECT 1 FROM lev_cat_12.%I e WHERE e.ilicode = t.%I)
       FROM %I.%I t WHERE t.%I IS NOT NULL AND date_part(''year'', t.vigencia) = %s GROUP BY t.%I',
      r.tab||'.'||r.col, r.col, r.enum, r.col, esq, r.tab, r.col, current_setting('mig.vig'), r.col);
  END LOOP;
END $$;
SELECT uso, code, n FROM tmp_dom_zhf WHERE NOT existe ORDER BY 1,2;
SELECT count(*) AS total_pares_ok FROM tmp_dom_check WHERE existe;

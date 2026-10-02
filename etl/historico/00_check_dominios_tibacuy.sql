-- Verifica que todo código de dominio usado en los datos origen exista como ilicode en el enum destino
DROP TABLE IF EXISTS tmp_dom_check;
CREATE TABLE tmp_dom_check(uso text, tgt_enum text, code text, n bigint, existe boolean);

DO $$
DECLARE
  r record;
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
   ('cc_nomenclaturavial_tipo_via','cc_nomenclaturavial_tipo_via','cc_nomenclaturavial','tipo_via')
  ) AS v(src_dom, tgt_enum, src_tab, src_col)
  LOOP
    EXECUTE format(
      'INSERT INTO tmp_dom_check
       SELECT %L, %L, d.text_code, count(*),
              EXISTS(SELECT 1 FROM lev_cat_12.%I e WHERE e.ilicode = d.text_code)
       FROM cun25805.%I t JOIN cun25805.%I d ON d.id = t.%I
       GROUP BY d.text_code',
      r.src_tab||'.'||r.src_col, r.tgt_enum, r.tgt_enum, r.src_tab, r.src_dom, r.src_col);
  END LOOP;
END $$;

SELECT uso, tgt_enum, code, n FROM tmp_dom_check WHERE NOT existe ORDER BY uso, code;
SELECT count(*) AS total_pares_ok FROM tmp_dom_check WHERE existe;

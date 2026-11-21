# Decisiones sobre datos y lecciones aprendidas

Registro de las decisiones de homologación tomadas por municipio y el catálogo de errores
de validación con su causa raíz y solución probada. **Consultar antes de resolver un error
nuevo**: casi todo lo que falla ya falló antes.

Las secciones por municipio (Tibacuy, Tibirita, Vergara, Sutatausa, Nemocón) registran las migraciones hechas
con el flujo heredado (`scripts/migrar.sh`, backups y XTF del operador). Las reglas que hoy aplican a todos están
en "Comunes a todos los municipios" y "Reglas globales del lote de 25 municipios"; donde una regla del lote
reemplaza lo dicho en una sección por municipio, se indica.

## Decisiones de homologación

### Comunes a todos los municipios

| Situación | Decisión | Justificación |
|---|---|---|
| `tb_valortipologia.tipo_anexo` (anexos: pozos, silos, tanques…) | Se excluyen del submodelo Avalúos | `AV_TipologiaTipo` v1.2 no contempla anexos; solo se migran tipologías con equivalente |
| `gc_predio.tipo` (`Privado`, `Publico.*`) | Se antepone `Predio.` al ilicode | El dominio destino `col_unidadadministrativabasicatipo` usa ruta completa (`Predio.Privado`) |
| Predios sin terreno/construcción en `col_uebaunit` | Se migran igual | El modelo permite predios sin unidad espacial (informales, mejoras); queda registrado el conteo |
| Geometrías vacías tras limpieza (área < tolerancia) en construcción/unidad | `geometria = NULL` | El atributo es opcional en esas clases; eran astillas degeneradas sin valor catastral |
| `resultado_visita` (texto libre) | Homologación a ilicodes (`No permitieron acceso` → `No_Permitieron_Acceso`, etc.) | Reglas en `config/homologaciones.csv` (antes un `CASE` en el ETL) |

### Reglas globales del lote de 25 municipios (2026-11-20)

Ver `05_lote_25_municipios.md` §2–3. Todas dejan una métrica en el manifiesto (`verificar`).

| Situación | Decisión |
|---|---|
| Homologaciones de dominio | Ya no son `CASE` en el SQL: `config/homologaciones.csv` (con la decisión que las originó) + `public.fx_hom`. Una regla cuyo destino no sea ilicode del dominio aborta la corrida |
| Interesados, agrupaciones y miembros | Solo los titulares de derechos de predios migrados (antes: todo `gc_interesado` del municipio). Métrica `interesados_sin_derecho_migrado_excluidos` |
| Linderos y puntos de lindero | Solo los que delimitan una unidad espacial migrada (`col_masccl`/`col_menosccl`) y sus puntos. Los puntos de levantamiento se migran todos. Métrica `excluido_linderos_sin_ue_migrada`. Reemplaza lo dicho en Vergara ("se migran todos los linderos y puntos") |
| `local_id` / `espacio_de_nombres` vacíos (`''`) en el origen | Se tratan como NULL → id / nombre de la clase (Chaguaní: 2 fuentes administrativas; ili2pg exporta, ilivalidator rechaza `Attribute Local_Id requires a value`) |
| `comienzo_vida_util_version` NULL en el origen (MANDATORY). Preflight 2026-11-20: 10 de 25 municipios, ~500 objetos (terrenos, construcciones, unidades, características; Subachoque también 2 derechos y 3 interesados) | Terreno, construcción, unidad y derecho heredan la fecha de su predio (la menor si hay varios); el resto (características, interesados, agrupaciones, linderos, puntos) toma el 1 de enero de la vigencia, igual que las servidumbres. Métrica `imputado_comienzo_vida_util`. **Aprobada por el usuario 2026-11-20.** El interesado placeholder `SIN DATO` usaba `now()` (XTF distinto en cada corrida): ahora usa la misma regla |
| Linderos con menos de 2 puntos (`col_puntoccl`) en el origen; el modelo exige ≥ 2 (`punto should associate 2 to *`, ilivalidator). Nocaima: 7 | Se excluyen con sus `col_masCcl`/`col_menosCcl` (los terrenos quedan). No se generan puntos desde la geometría. Métrica `excluido_linderos_menos_2_puntos`; no se solapa con `excluido_linderos_sin_ue_migrada` (corregida 2026-11-21: antes contaba también estos) |
| Áreas MANDATORY nulas en el origen (preflight: construcciones en Anapoima 12, Facatativá 14, Guatavita 12, San Antonio 37; unidades en Anapoima, Guatavita, Apulo, San Antonio; 1 característica en Villeta) | Construcción y unidad: área geométrica (igual que el terreno); características: suma de las áreas de sus unidades. Métrica `imputado_area_construida` |
| `LC_Construccion.Identificador` (TEXT*20) vacío | Código de la construcción solo si cabe en 20 caracteres, si no el id de origen (Guatavita: 7 con el NPN de 30 en `codigo`) |
| `AV_TipologiaConstruccion` de municipios 2023 | `tb_valortipologia` vigencia 2023 tomada de `acc_2024` (esquema `aux_tipologia`). Reemplaza "vacía" de Vergara y Sutatausa (b) |
| Polígono de terreno/construcción/unidad válido en el origen que el snap a 1 mm invalida (Nimaima: 1 construcción) | Respaldo `ST_ReducePrecision` sobre la geometría previa a la limpieza (`02_fix` sección 5b; ver catálogo de errores). `fix` es atómico: si un control ≠ 0 no hace commit |
| Triggers/funciones del gestor en el dump (Sutatausa: 2 triggers que llaman a `attr_sync.*`, esquema que no viene) | `preparar` no los restaura (no aportan datos) y los registra en el manifiesto. `migrar.sh` sigue tolerando el error |
| Validación | ili2pg exporta con `--disableValidation`; valida solo ilivalidator 1.15.0 (más estricto). Evita validar dos veces |

Pendientes de decisión del usuario (no aplicadas): linderos gigantes de Nimaima, ZH inválidas a 1 mm (Guatavita,
Tocaima) y derechos sin ninguna fuente (Supatá, Anapoima, Subachoque). Ver `05_...` §6.

### Tibacuy (cun25805)

| Situación | Decisión |
|---|---|
| 1 interesado con tipo documento `NUIP` (no existe en v1.2) | Homologado a `Registro_Civil` |
| 2 interesados "MUNICIPIO DE TIBACUY" con `documento_identidad` NULL (campo MANDATORY, ambos con derechos) | Completado con NIT `8000186895`, tomado de otros registros del mismo interesado en la fuente |
| 4 unidades de construcción con geometría degenerada (astilla completa) | `geometria = NULL` |

### Tibirita (cun25807)

| Situación | Decisión |
|---|---|
| 4 agrupaciones de interesados con 1 solo miembro tras dedup (la fuente repetía a la misma persona) | El derecho pasa al interesado directo; se elimina la agrupación y su membresía (el modelo exige ≥2 miembros) |
| Terreno `t_id 3050136` con auto-intersección persistente | `ST_Buffer(geom, 0)` previo al pipeline de limpieza |

### Vergara (cun25862) — vigencia 2023

| Situación | Decisión |
|---|---|
| id de origen hasta ~2,5 millones (predio, interesado, fuente, uebaunit…) | Offsets de t_id ampliados de 1M a 100M por clase en la plantilla (t_id bigint) |
| El gestor no tiene `tb_valortipologia` | `av_tipologiaconstruccion` queda vacía (la plantilla omite el bloque con aviso). En el lote se toma de `acc_2024` |
| 143 pares repetidos (unidad espacial, predio) en `col_uebaunit` (62 construcciones, 81 unidades) | Se conserva el de menor id (`DISTINCT ON` en la plantilla) |
| 85 predios sin unidad espacial | Se migran igual (regla común) |
| ~60 polígonos con micro auto-intersección tras el snap | `ST_Buffer(0)` + limpieza, ahora global en `02_fix_validacion` |
| Linderos, puntos, CCL, fuentes espaciales, informalidad y ref. registral antigua no se migraban (ETL heredado de Tibacuy) | Incorporados a la plantilla (secciones 12b–12d). Se migran todos los linderos y puntos; las relaciones CCL solo hacia UE migradas (17 `col_masccl` excluidas: 2 terrenos de predios sin avalúo 2023) |
| `col_baunitfuente` vacía en el gestor | Derivada de `gc_fuenteespacial.descripcion` = número predial (10.125). 14 fuentes sin predio en el backup quedan fuera |
| Atributos de zonas físicas en texto libre ("Zonas con aguas abundantes") | Homologados por `dispname` del dominio con `public.fx_dom` |
| `Tipo_Principal` de fuentes | Regla del XTF de referencia: fuente administrativa con estado `Desconocido` → `Otro`; fuente espacial `Registro_Fotografico` → `Imagen` |
| Contacto de visita, novedades de números prediales, observaciones y avalúo de unidades no existen en el backup | Decisión del usuario (2026-10-02): tomarlos del XTF `comparacion/Vergara_20230207_1720.xtf` (etapa `complemento`). Cruce de características por huella 1 a 1 (11.062/11.062); datos adicionales por número predial (6.123/6.136, los 13 restantes son predios que ya no existen) |
| Diferencias que se mantienen frente al XTF de feb-2023 | 13 predios del XTF ya no están en el backup; `Nombre` del predio distinto en 1.195 (se respeta la fuente); el XTF previo no trae avalúo del predio |

### Sutatausa (cun25781) — vigencia 2023

Se migró dos veces: (a) backup de conservación 2026 (`sutatausa.env`, BD `sutatausa_lev12`, XTF `_bk2026`) y (b) **backup con corte 2023** (`sutatausa_v2023.env`, BD `sutatausa_v2023_lev12`), que es el XTF vigente. Frente al XML `comparacion/sutatausa/Registro_catastral_25781.xml` (feb-2023), (b) cruza 4.090 de 4.093 predios y 4.084 avalúos iguales; (a) solo cruzaba 4.004 y 3.677 avalúos (revisiones posteriores, `extavaluo.modificado`). Informes en `comparacion/informe_sutatausa_registro_2023*.json`.

| Situación | Decisión |
|---|---|
| Backup de **conservación con estado 2026** e histórico de avalúos 2019–2026 | Universo = predios con `extavaluo` 2023 (4.226 de 4.261). Los 35 excluidos se crearon entre dic-2023 y nov-2025 (solo tienen avalúos 2024+). Los atributos no avaluatorios (interesados, derechos, geometrías, áreas) son los vigentes en el backup (2026), no una foto de 2023; los predios cancelados antes de 2026 no están en el backup |
| `zhf_rural.area_homogenea_tierra` trae el código AHT (`05FSb-61`), no un número; el destino es Numeric opcional | `NULL` cuando el valor no es numérico (regla global en la plantilla) |
| 1 interesado con sexo `Otro` (no existe en `LC_SexoTipo` v1.2) | Homologado a `Sin_Determinar` (regla global en la plantilla) |
| `tb_valortipologia` 2023: 55 registros, 34 anexos sin equivalente | Se migran 21 tipologías (regla común de anexos) |
| Zonas homogéneas y tipologías solo existen para 2023 en el backup | Se migran todas (246 ZHF rurales, 24 urbanas, 9 ZHG rurales, 14 urbanas) |
| 3 predios sin unidad espacial | Se migran igual (regla común) |
| (b) El backup 2023 no trae `tb_valortipologia` | `av_tipologiaconstruccion` vacía (como Vergara) |
| (b) Predio `257810000000000050130000000000` con `fin_vida_util_version` 2022-09-20 < comienzo 2023-01-01 (vigente en el XML 2023 y en el backup 2026) | `fin_vida_util_version = NULL`; regla global en `02_fix_validacion` sección 7 |
| 216 predios con avalúo 2023 = $0 (informales, matrices PH/condominio) | Se migran (tienen avalúo de la vigencia); el XML de registro catastral los omite |
| Combinación de fuentes (decisión del usuario 2026-10-06) | Base = backup corte 2023. Del backup 2026 (etapa `auxiliar`, esquema `cun25781_v2026`) solo `tb_valortipologia` 2023 → 21 `AV_TipologiaConstruccion`. Del XTF del operador `comparacion/sutatausa/sutatausa_final.xtf` (3-feb-2023, etapa `complemento`): contacto de visita (4.234), novedades de números prediales (4.307), avalúo/observaciones de unidades (6.150 de 6.175) y `CC_Barrio`/`CC_CentroPoblado` |
| Datos PH/condominio (24) y servidumbres de tránsito (2) existían en el gestor y no se migraban | Incorporados a la plantilla (secciones 10a/10b) para todos los municipios |
| Relación `lc_predio_copropiedad` (unidad predial → matriz, con coeficiente) existía en el gestor (`gc_prediocopropiedad`, 59) y no se migraba: el XTF salía sin copropiedad (observación SNR) | Incorporada a la plantilla (sección 10c, t_id 50·10⁸ + id) para todos los municipios, solo entre predios migrados; secuencia final a 5.100.000.000. `verificar` compara origen vs destino y controla que los coeficientes de cada matriz sumen 1 (decisión del usuario 2026-10-07) |
| Valores de ZHG y tipologías: el XTF del operador usa valores comerciales (catastral/0,6) | Se mantienen los **catastrales** (decisión del usuario) |
| Construcciones regeneradas en el gestor el 6-feb-2023 (`cg_060223`, sin año/altura/dominio/valor) | Se dejan como están (decisión del usuario); el XTF del operador trae 2.294 construcciones previas con atributos, no cruzables 1 a 1 |
| Predios cancelados (decisión del usuario 2026-10-06) | Se agregan los 165 predios con novedad `Cancelacion` del XTF del operador, con sus derechos, datos adicionales, contactos (152), fuentes y novedad (etapa `cancelados`). Sin avalúo (no tienen avalúo 2023) ni unidad espacial. 74 de sus 111 interesados ya existían (mismo tipo y documento) y se reutilizan; `Id_Operacion` = `SUTATAUSA_C0001…` (UNIQUE) |
| Calidad de los 165 predios cancelados (decisión del usuario 2026-10-07) | Se corrigen en la etapa `cancelados` (`05_cancelados_xtf.sql`), porque no están en el backup: documentos sin espacios ni U+00A0 al cruzar interesados (y unión de repetidos dentro de la referencia), direcciones repetidas en el predio, una sola dirección principal (el XTF del operador no marcaba ninguna), fuentes repetidas en un mismo derecho y tipo de agrupación según sus miembros |
| Del XTF del operador no se toman | 3 predios `Predio_Nuevo` ausentes de ambos backups; `Avaluo_Terreno` (todo en 0) |
| Zonas homogéneas (revisión 2026-10-06) | Valores idénticos al backup 2023 (= 2026 en lo que se migra; el 2026 cambió `area_homogenea_tierra` a código AHT, por eso se usa el 2023). La geometría solo se redondea a 1 mm (precisión del modelo, mismos vértices y orden; desplazamiento máx. 0,6 mm). Regla global: las ZH ya no pasan por `MakeValid`/limpieza; `verificar` controla `zh_modificadas_vs_backup` = 0 |

### Nemocón (cun25486) — vigencia 2023

Backup `nemocon_25486_v2023_202610141544.sql` (histórico de avalúos 2019–2023; los 5.983 predios tienen avalúo 2023). Config `nemocon` (BD `nemocon_lev12`): solo el backup. Config `nemocon_v2023b` (BD `nemocon_v2023b_lev12`, 2026-10-14): el mismo backup complementado con el XTF del operador `comparacion/nemocon/nemocon_20230206_1330.xtf` (6-feb-2023, actualización urbana: 3.002 predios, 2.926 comunes con el backup + 76 cancelados) en las etapas `complemento`, `cancelados` y `operador`. Comparación y verificación en `D:/ACC/xtf_reporte_SNR/Nemocon`.

| Situación | Decisión |
|---|---|
| 242 predios con condición `Mejora` (NPN pos. 22 = 5), inexistente en `LC_CondicionPredioTipo` v1.2 | Homologados a `Informal` (decisión del usuario 2026-10-14; regla global en la plantilla) |
| 9 interesados con sexo `No_Binario` | `Sin_Determinar`, igual que `Otro` (decisión del usuario 2026-10-14; regla global) |
| 1 terreno sin `area` (predio `254860000000000080552000000000`); `Area_Terreno` es MANDATORY | Se usa el área geométrica (`round(ST_Area,1)`); regla global |
| 5 de 87 tramos de `cc_nomenclaturavial` sin `tipo_via` y 5 con `numero_via` vacío (4 coinciden), ambos MANDATORY. ili2pg exporta `''` sin error, pero ilivalidator 1.15.0 lo rechaza (`Attribute Numero_Via requires a value`) | Se excluyen (regla global: solo tramos con tipo homologable y número no vacío; 81 de 87). Lección: validar también con ilivalidator, la validación del export de ili2pg no basta |
| `cc_vereda.codigo_sector` con el código completo (`254860000`); destino `TEXT*2` | Se toman los 2 últimos dígitos (`00`); regla global |
| 2.903 derechos sin `col_rrrfuente`; su fuente está ligada al predio en `col_unidadfuente` (5.141 vínculos, título del predio: `local_id` = NPN, `espacio_de_nombres` = año). El modelo exige ≥1 fuente por derecho | Decisión del usuario 2026-10-14: se migra `col_unidadfuente` (t_id 51·10⁸) y a los derechos sin fuente se les asocian las fuentes de su predio (t_id 52·10⁸). Fuentes administrativas: 3.106 → 8.207; reglas globales |
| 1 derecho sin interesado ni agrupación (predio mejora `254860000000000060117500000001`); el modelo exige titular y ≥1 derecho por predio | Decisión del usuario 2026-10-14: interesado placeholder `SIN DATO` (Persona_Natural, `Secuencial`, documento `Sin_Dato`, t_id 53·10⁸ + id derecho); regla global |
| Nombre y dirección de 1 predio con caracteres de control (el validador los rechaza) | `02_fix` sección 8: se reemplazan por espacio en tablas de datos (nunca en catálogos con `ilicode`) |
| ZH rurales solo con vigencia 2021 (29 ZHF, 17 ZHG); urbanas: 11 ZHG 2023, 0 ZHF | Decisión del usuario 2026-10-14: se migran las de 2021 (opción `ZH_ULTIMA_VIGENCIA=si`), sin modificar |
| ZHF rurales 2021 con atributos en códigos numéricos (`disponibilidad_agua` 2/3/4, `uso_actual_suelo` 16) sin tabla de equivalencias | Quedan NULL (opcionales; no se adivina la homologación). Pendiente si el gestor entrega la tabla de códigos |
| 6 matrices de copropiedad cuyos coeficientes no suman 1 (p. ej. 4 matrices con suma 0,25) | Idénticos al origen: problema de calidad de la fuente, se reporta y no se corrige |
| 527 predios sin unidad espacial (241 son mejoras/informales) | Se migran igual (regla común) |
| Combinación con el XTF del operador (decisión del usuario 2026-10-14) | **Prevalece el gestor; el operador solo llena vacíos.** Las diferencias en predios comunes no se tocan: 36 con titulares distintos, 90 `Condicion_Predio` (`Via`/`Bien_Uso_Publico`/`Parque_Cementerio`), 31 `Destinacion_Economica`, 1.037 `Codigo_Homologado`, 4 FMI, 948 con direcciones distintas; `Nombre` del operador es un código interno. Detalle en `Nemocon/resultados/Comparacion_XTF_gestor_operador_complementado.xlsx` |
| Etapa `complemento` | Observaciones de las 4.303 características (cruce 1 a 1 por huella; 260 con texto), novedades de 2.926 predios, 2.912 contactos de visita, `CC_Barrio` y `CC_LocalidadComuna` (1 y 1; el backup no los trae) |
| Predios cancelados | Los 76 predios con novedad `Cancelacion` del operador (etapa `cancelados`): sin avalúo 2023 ni unidad espacial; 24 de sus 46 interesados ya existían y se reutilizan; `Id_Operacion` = `NEMOCON_C0001…` |
| Linderos, puntos y fuentes espaciales del operador (etapa nueva `operador`, `06_complemento_operador.sql`) | 1.907 de 1.911 terrenos urbanos tienen la misma geometría en ambas fuentes y reciben sus linderos: 5.042 `LC_Lindero`, 8.538 `col_masCcl`, 139 `col_menosCcl`, 10.680 `LC_PuntoLindero`, 17.423 `col_puntoCcl`. Los 4 terrenos con geometría distinta (manzana 25; 1,2 a 40,8 m²) quedan sin linderos (11 linderos no se copian). Además 13.278 `LC_PuntoLevantamiento` y 1.375 `LC_FuenteEspacial` (registro fotográfico; 4 de ellas vienen con los cancelados) |
| Zonas homogéneas urbanas | ZHF urbanas: el backup no trae; se toman las 66 del operador (vigencia 2023). ZHG urbanas: se conservan las 11 del gestor. Las 53 del operador son las mismas 11 zonas, partidas en más polígonos, sobre la misma área (122,33 ha), con valor comercial (gestor/operador = 0,6 en todas, igual que en Sutatausa) |
| `AV_TipologiaConstruccion` | El backup no trae `tb_valortipologia`; se toman las 104 del operador aunque puedan venir a valor comercial (decisión del usuario 2026-10-14) |
| Avalúo de unidades del operador | No se toma (`COMPLEMENTO_AVALUO_UNIDADES=no`, decisión del usuario 2026-10-14): no cuadra con el avalúo 2023 del gestor (mediana 2,3 % del avalúo del predio; p. ej. casa de 213,8 m² con unidad de $24.396) y mezcla escalas. El campo es opcional. Opción nueva de la etapa `complemento` (por defecto `si`: Sutatausa sin cambio) |

## Catálogo de errores de validación (ili2pg / ilivalidator)

> En el lote de 25 municipios valida **solo ilivalidator 1.15.0** (`scripts/lote.py`, etapa `validar`); ili2pg
> exporta con `--disableValidation`. ilivalidator rechaza cosas que la validación del export de ili2pg deja
> pasar: textos MANDATORY vacíos (`''`) como `Numero_Via` (Nemocón) o `Local_Id` (Chaguaní).
> `migrar.sh` (flujo heredado) sigue validando con ili2pg al exportar.

### `Attribute <X> requires a value` (ilivalidator; ili2pg no lo reporta)

- **Causa**: atributo MANDATORY con cadena vacía `''` en el origen. `COALESCE` no la reemplaza.
- **Solución**: `COALESCE(NULLIF(btrim(x),''), <valor por defecto>)` o excluir el objeto si no hay valor
  legítimo (regla global, ver `local_id` y `cc_nomenclaturavial`).

### `OID ...col_ueBaunit:<uuid>:<uuid> of object col_ueBaunit already exists`

- **Causa**: la fuente repite el mismo par (unidad espacial, predio) en `col_uebaunit`; el
  OID de la asociación es el par de OIDs, así que el duplicado choca (Vergara: 143).
- **Solución**: `DISTINCT ON (ue_*, baunit)` conservando el menor `t_id` al insertar
  (plantilla `01_migracion.sql`, sección 10).

### `Tabla ... tiene id ... >= 100.000.000` (abort del ETL, no de ili2pg)

- **Causa**: la estrategia `t_id = N·10⁸ + id` no admite ids de origen tan grandes.
- **Solución**: si aparece, cambiar a tabla de mapeo id_origen → t_id por secuencia.

### `duplicate coord at (x, y, z)`

- **Causa raíz**: dos vértices consecutivos que quedan idénticos al redondear a 3 decimales
  (el XTF escribe coordenadas con precisión de 1 mm). El origen más frecuente **no son los
  datos fuente**, sino `ST_MakeValid` aplicado al final del pipeline: al resolver polígonos
  con auto-intersección crea vértices nuevos fuera de la grilla y polígonos "astilla" de
  área ~0 con vértices a <1 mm.
- **Solución probada** (función `fx_limpiar_poligono` en `etl/plantilla/02_fix_validacion.sql`):
  1. `ST_MakeValid` **primero** (resuelve auto-intersecciones),
  2. descartar componentes con `ST_Area < 0.01` m² (astillas),
  3. `ST_SnapToGrid(geom, 0.001)` (alinear a la precisión del XTF),
  4. `ST_RemoveRepeatedPoints(geom, 0.002)`.
- **No sirve**: aplicar solo `ST_RemoveRepeatedPoints` (no elimina pares en anillos de 4
  puntos, ni vértices creados después por MakeValid), o arreglar registro por registro
  (el validador se detiene en el primer error y el ciclo es interminable).

### `Mandatory Constraint LADM_COL_V3_1.LADM_Nucleo.ObjetoVersionado.Constraint1 is not true`

- **Causa**: `Fin_Vida_Util_Version < Comienzo_Vida_Util_Version` en el origen (Sutatausa v2023: 1 predio).
- **Solución**: `02_fix_validacion` sección 7 pone `fin_vida_util_version = NULL` en toda tabla de `lev_cat_12` que lo cumpla.

### `rrr should associate 1 to *` / `fuente_administrativa should associate 1 to *` / `must not contain control characters`

- **Causa**: predio sin derecho, derecho sin fuente administrativa, texto con caracteres de control (Nemocón).
- **Solución**: ver decisiones de Nemocón (placeholder de titular, fuentes desde `col_unidadfuente`, `02_fix` sección 8).
  No eliminar derechos sin titular: el predio queda sin `rrr` y falla igual.

### `Class ... has to have an OID`

- **Causa**: clases del tópico de cartografía sin `t_ili_tid`.
- **Solución**: `UPDATE ... SET t_ili_tid = 'cc'||t_id WHERE t_ili_tid IS NULL` (script 02, sección 2).

### `OID ... of object col_miembros already exists`

- **Causa**: el mismo interesado repetido en la misma agrupación en la fuente.
- **Solución**: dedup por `(interesado, agrupacion)` conservando el menor `t_id` (script 02,
  sección 1). **Atención al efecto secundario**: agrupaciones que quedan con 1 miembro (ver
  siguiente).

### `interesado should associate 2 to * target objects (instead of 1)`

- **Causa**: `LC_AgrupacionInteresados` con un solo miembro (consecuencia del dedup).
- **Solución**: reasignar el derecho al interesado único (`interesado_lc_interesado`),
  poner `interesado_lc_agrupacioninteresados = NULL`, borrar membresía y agrupación
  (hoy en `etl/plantilla/02_fix_validacion.sql`, sección 2).

### `Self-intersection at or near point ...` (ST_IsValid falla tras el snap)

- **Causa**: el snap a grilla puede reintroducir una micro auto-intersección en polígonos
  muy irregulares.
- **Solución**: para el registro afectado, `ST_Buffer(geom, 0)` y volver a pasar
  `fx_limpiar_poligono`.

### Polígono válido en el origen que queda inválido tras `fix` (control `constr_invalida` / `terreno_invalido`)

- **Causa**: el snap a 1 mm reintroduce una auto-intersección y el reintento con `ST_Buffer(0)` vuelve a
  pasar por el snap (Nimaima 2026-11-20: 1 construcción de 97 m²).
- **Solución** (`02_fix` sección 5b, global): solo para lo que sigue inválido, `ST_ReducePrecision(ST_MakeValid(geom), 0.001)`
  sobre la geometría previa a la limpieza. GEOS redondea a la grilla preservando la validez (Hausdorff 0,5 mm).
  Las geometrías que ya salían válidas no cambian. **No** aplicarlo sobre la geometría ya dañada: el pico que
  crea el snap se convierte en un desplazamiento de 1,2 m.

### `punto should associate 2 to * target objects` (ilivalidator)

- **Causa**: lindero sin puntos o con 1 punto en `col_puntoccl` del origen (Nocaima 2026-11-20).
- **Solución**: regla global de exclusión de linderos con < 2 puntos (ver reglas del lote).

### ili2pg o ilivalidator no terminan (`validate target of role col_puntoCcl.ccl`)

- **Causa**: lindero con decenas de miles de puntos (Nimaima: 38.308 y 16.569). El costo de validar la relación
  crece más que proporcional al número de puntos por lindero: más de 30 min sin avanzar.
- **Solución**: pendiente de decisión del usuario (`05_...` §6, D1). Detectar antes con un preflight de puntos
  por lindero (en los demás municipios el máximo es 4.944).

### `Intersection coord1 (...)` en una zona homogénea (ilivalidator)

- **Causa**: ZH válida en el origen que el redondeo a 1 mm del XTF invalida, o ZH ya inválida en el origen
  (Guatavita, Tocaima). Las ZH no pasan por limpieza (regla Sutatausa).
- **Solución**: pendiente de decisión del usuario (`05_...` §6, D2).

### `value too long for type character varying(20)` en el ETL

- **Causa**: `gc_construccion.identificador` vacío; el ETL usaba el `codigo` (NPN de 30 caracteres) en
  `LC_Construccion.Identificador` (TEXT*20) (Guatavita).
- **Solución**: regla global del identificador (código solo si cabe en 20 caracteres, si no el id).

### `FIX: controles distintos de 0: derechos_sin_fuente=N`

- **Causa**: derecho sin `col_rrrfuente` y sin fuente en `col_unidadfuente` de su predio (Supatá 160).
- **Solución**: pendiente de decisión del usuario (`05_...` §6, D3).

### Violación NOT NULL en el INSERT del ETL

- **Causa**: campos MANDATORY del modelo con NULL en la fuente (ej. `documento_identidad`,
  `comienzo_vida_util_version`, `area_construccion`).
- **Solución**: completar con dato real si existe en otros registros de la fuente (caso NIT
  municipio, fecha del predio, área geométrica); si no, placeholder documentado (`Sin_Dato`). Nunca dejar pasar
  silenciosamente: medir el alcance en todos los municipios y registrar la decisión en este documento.

## Lecciones de proceso

1. **ili2pg escribe el XTF aunque la validación falle.** Verificar siempre que el log
   termine en `...export done`. El XTF "fallido" de Tibirita circuló como si fuera válido. `lote.py` escribe
   a `.parcial.xtf` y solo genera `.sha256` si ilivalidator termina en `...validation done`.
2. **Esquema destino fijo**: no correr `--schemaimport` por municipio. `migrar.sh` clona `lev_cat_12` de una BD
   ya migrada; `lote.py` carga `etl/esquema/lev_cat_12_plantilla.sql` (versionado). Así los t_id de catálogos
   son idénticos y no hay diferencias de flags.
3. La extensión **`uuid-ossp`** debe existir antes de restaurar el esquema clonado.
4. **Prefijar los OID (`t_ili_tid`) con el municipio** (`md5('<mun>_tabla'||id)`): sin
   prefijo, dos municipios generan los mismos UUID para los mismos id y colisionarían al
   cargarse juntos.
5. El validador reporta **un error por clase por pasada**: los fixes deben ser globales y
   preventivos, no reactivos registro a registro.
6. Verificación de cierre que no falla: la **suma de avalúos** origen (vigencia) vs
   `lc_predio.avaluo_catastral` debe coincidir al peso.
7. Algunos backups traen **triggers que llaman a `attr_sync.*`** (esquema externo que no viene en el dump;
   p. ej. Sutatausa 2026-10-07). Fallan al restaurar sin afectar los datos: `migrar.sh` tolera ese error y
   `lote.py` no restaura triggers ni funciones del gestor.
8. **Documentos de identidad con espacios no separables (U+00A0)** al final (Sutatausa: 25 cédulas).
   `trim()` no los quita, así que `'1074888324'` y `'1074888324  '` parecen personas distintas y los
   duplicados no se detectan ni se reutilizan. Normalizar con
   `regexp_replace(doc, '[\s' || chr(160) || ']', '', 'g')` antes de comparar (hoy en
   `05_cancelados_xtf.sql`; en la fuente lo corrige `correcciones/02_2_fusion_interesados.sql` del
   proyecto Sutatausa).
9. **Verificar el XTF contra las observaciones del cliente, no solo contra el validador.** El XTF de
   Sutatausa era válido para ili2pg y aun así conservaba los hallazgos de la SNR. Además el ETL filtra
   datos (p. ej. fuentes sin derecho), así que un XTF limpio no prueba que la base fuente lo esté.
10. **ilivalidator es más estricto que la validación de ili2pg** (textos vacíos, cardinalidades): la validación
    de entrega es la de ilivalidator.
11. **Medir antes de corregir**: cada falla nueva del lote se midió en los 25 municipios (preflight) antes de
    crear la regla; así se detectaron de una vez fechas nulas en 10 municipios, linderos gigantes solo en
    Nimaima y ZH inválidas solo en Guatavita y Tocaima.
12. **Recursos**: con 16 GB y ~2,5 GB libres, Java puede quedarse sin memoria en municipios grandes; definir
    `JAVA_XMX` y no lanzar corridas largas como tareas en segundo plano de Claude Code (las detiene).

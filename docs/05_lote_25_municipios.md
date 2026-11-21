# Lote de 25 municipios con actualización catastral (vigencias 2023 y 2024)

> Iniciado 2026-11-20 en la rama `lote-25-municipios` (sin push). Proceso: `scripts/lote.py` (§4).
> Última actualización: 2026-11-21. **Para retomar en una sesión nueva, ir a §7.**

## 1. Universo

`public.cadaster_information` (igual en `acc_mayo_2023`, `acc_2024` y `acc_noviembre_2026`) solo registra los
13 municipios con actualización vigente en 2023; **no registra las de 2024 ni hay vigencia 2022**. Los 12 de 2024
se identificaron como los únicos esquemas con zonas homogéneas de vigencia 2024 (`acc_noviembre_2026`), y se
confirmó que `acc_2024` trae su actualización completa (100 % de los predios con avalúo 2024, ZH 2024).
Universo y fuentes confirmados por el usuario el 2026-11-20. Catálogo: `config/lote_25.csv`.

| Vigencia | Fuente (BD de corte) | Municipios |
|---|---|---|
| 2023 | `acc_mayo_2023` | Arbeláez\*, Chaguaní, Fómeque\*, Nemocón\*, Nimaima, Nocaima, Quebradanegra, Supatá, Sutatausa, Tausa, Ubaté, Vergara, Villeta |
| 2024 | `acc_2024` | Anapoima, Anolaima, Facatativá, Guaduas, Guatavita, Quipile, Apulo, San Antonio del Tequendama, Subachoque, Tibacuy, Tibirita, Tocaima |

\* Actualización solo urbana (rural 2004–2006).

Comprobaciones de la fuente (2026-11-20):

- `acc_mayo_2023` cuadra con lo ya entregado: Nemocón 5.983 predios / $598.625.016.000, Sutatausa 4.307, Vergara 6.123.
- `acc_2024` cuadra al peso con Tibacuy (3.334 / $389.063.655.000) y Tibirita (5.134 / $325.077.199.000).
- `acc_2024` **no** sirve para 2023: trae avalúos 2023 ya revisados (Arbeláez −$7.300 M, Nemocón −$32 M).
- `acc_mayo_2023` **no** sirve para 2024: los 12 tienen 0–88 predios con avalúo 2024 y ninguna ZH 2024.
  Lo que trae como avalúo 2022 es conservación antigua (Tibacuy $55.700 M vs $389.000 M de la actualización).
- No usar los esquemas `cunXXXXX_backup_16feb2023` de `acc_mayo_2023` (pre-actualización).

## 2. Decisiones del usuario

| Fecha | Tema | Decisión |
|---|---|---|
| 2026-11-20 | Mezcla con XTF del operador (etapas `complemento`, `cancelados`, `operador`) | **No** en este lote; se hará en una etapa posterior |
| 2026-11-20 | Municipios ya migrados (Tibirita, Tibacuy, Vergara, Sutatausa, Nemocón) | Se reprocesan igual que el resto, en `salida/lote_25/`. Los XTF ya entregados (`salida/*.xtf`) no se tocan (sirven de regresión) |
| 2026-11-20 | Actualización solo urbana | Se migran todos los predios con avalúo de la vigencia (urbanos y rurales), como Nemocón |
| 2026-11-20 | Decisiones previas (Mejora→Informal, No_Binario/Otro→Sin_Determinar, NUIP→Registro_Civil, placeholder `SIN DATO`, fuentes desde `col_unidadfuente`, valores catastrales, ZH de la última vigencia cuando falta la exacta) | Aplican a todos por defecto |
| 2026-11-20 | ZH de Arbeláez, Fómeque y Nemocón | Rurales: última vigencia disponible (2021, `zh_ultima_vigencia=si`). ZHF urbanas 2023: no existen en las BD de corte → **vacías** por ahora |
| 2026-11-20 | `AV_TipologiaConstruccion` de los 13 de 2023 | `acc_mayo_2023` no trae `tb_valortipologia`; se toma de `acc_2024` **solo** esa tabla con vigencia 2023 (como Sutatausa con el backup 2026). Los 12 de 2024 la traen en su propio esquema |
| 2026-11-20 | `comienzo_vida_util_version` nulo en el origen | Regla de fecha heredada (ver `03_...`) **aprobada** |
| 2026-11-20 | Validación | Debe pasar ilivalidator 1.15.0 (copia local en `ili2pg/`) |
| 2026-11-20 | Ejecución | Un municipio a la vez. Pausa pedida tras Vergara |

Decisiones **pendientes**: §6.

## 3. Cambios al proceso respecto del flujo heredado (`migrar.sh`)

| Cambio | Antes | Ahora |
|---|---|---|
| Insumo | Backup pg_dump completo por municipio, entregado a mano | `pg_dump -n cunXXXXX` de la BD de corte (`insumos/lote_25/`, con sha256 en el manifiesto) |
| Restauración | Se toleraba el error de triggers que llaman a `attr_sync.*` | `preparar` no restaura TRIGGER/FUNCTION/PROCEDURE/RULE/EVENT TRIGGER/AGGREGATE del gestor (no aportan datos; Sutatausa traía 2 triggers de `attr_sync`) y restaura con `--exit-on-error`. Lo omitido queda en `fuente.objetos_no_restaurados` del manifiesto |
| Esquema destino | Clon de `lev_cat_12` desde la BD `tibacuy_lev12` | `etl/esquema/lev_cat_12_plantilla.sql` versionado. Catálogos verificados idénticos (ilicode, dispname, description) a un `--schemaimport` limpio de ili2pg 5.5.1 y en las 6 BD ya migradas |
| Homologaciones | `CASE` en el SQL | `config/homologaciones.csv` + `public.fx_hom` (`00_homologaciones.sql`), validadas contra el dominio destino |
| Chequeo de dominios | Informativo | Aborta si hay códigos sin equivalente (usa el mismo método que el ETL). ZHF: solo aviso (decisión Nemocón) |
| Universo | Todos los interesados, agrupaciones, linderos y puntos de lindero del municipio | Solo los ligados a derechos / unidades espaciales migradas; linderos con < 2 puntos se excluyen (las métricas informan cuántos) |
| Campos MANDATORY vacíos | `COALESCE(valor, id)`: el `''` del origen pasaba | `Local_Id`/`Espacio_De_Nombres` vacíos → id / nombre de clase; áreas nulas → área geométrica o suma de unidades; identificador de construcción → código si cabe en 20 caracteres, si no id; `comienzo_vida_util_version` nulo → fecha heredada |
| `fix` | Tabla final "debe dar 0", commit aunque no diera 0 | Aborta si un control ≠ 0 y **no hace commit** (atómico). Controles: agrupaciones con 0/1 miembro, derechos sin titular o sin fuente, predios sin derecho, cartografía sin OID, terrenos/construcciones/unidades inválidos. Respaldo `ST_ReducePrecision` para polígonos que el snap a 1 mm invalida |
| `verificar` | Informativo | Aborta si no cuadran avalúo, predios, duplicados, ZH o copropiedad; salida `clave|valor` con métricas de imputaciones y exclusiones y conteo por clase |
| Exportación y validación | ili2pg valida al exportar (`export done`) | ili2pg exporta con `--disableValidation` a `<xtf>.parcial.xtf` y lo renombra solo si termina en `...export done`; **ilivalidator 1.15.0** valida (`...validation done`) y solo entonces se genera el `.sha256`. Antes se validaba dos veces, y ilivalidator detecta más (textos MANDATORY vacíos) |
| Trazabilidad | Logs sueltos | `salida/lote_25/<mun>/manifiesto.json`: fuente y sha256 del dump, commit y cambios sin commit en `etl/`, `config/`, `scripts/`, sha256 de cada SQL, versiones de herramientas, tiempos por etapa, métricas, sha256 del XTF. `salida/lote_25/resumen_lote.csv` consolidado. Manifiestos, `.sha256` y resumen se versionan; los XTF no |

Detalle de cada regla y su justificación: `03_decisiones_y_lecciones.md`, sección "Reglas globales del lote".

## 4. Operación

Requisitos: `.env` (ver `.env.example`; para municipios grandes agregar `JAVA_XMX=4g`), ilivalidator en
`ili2pg/ilivalidator-1.15.0/`, BD de corte `acc_mayo_2023` y `acc_2024` accesibles.

```bash
python scripts/lote.py --piloto                 # Nemocón, Chaguaní, Quipile
python scripts/lote.py chaguani quipile         # por nombre corto (columna mun de config/lote_25.csv)
python scripts/lote.py --todos
python scripts/lote.py nemocon --desde etl      # reanudar desde una etapa
python scripts/lote.py nemocon --etapas exportar
python scripts/lote.py --reporte                # solo regenerar resumen_lote.csv
```

Etapas: `extraer → preparar → tipologias → dominios → etl → fix → verificar → exportar → validar`.
BD de trabajo `l25_<mun>` (se recrea en `preparar`; el script solo borra BD con prefijo `l25_`).
Logs en `logs/lote_25/<mun>/`. Un municipio que falla no detiene el lote; el resumen indica en qué etapa.

Forma de correr usada hasta ahora (desde Claude Code): un municipio a la vez, **en primer plano**, partiendo las
etapas para no pasar de 10 min por llamada:

```bash
python scripts/lote.py <mun> --etapas extraer,preparar,tipologias,dominios,etl,fix,verificar
python scripts/lote.py <mun> --etapas exportar
python scripts/lote.py <mun> --etapas validar
```

Tiempos observados (3.000–6.000 predios): `etl` 20–100 s, `exportar` 20–70 s (sin validación), `validar`
20–170 s; 4–7 min por municipio. **Memoria**: el equipo tiene 16 GB y ~2,5 GB libres durante la corrida; una
tarea en segundo plano de Claude Code fue detenida por falta de memoria (dejó un XTF parcial; por eso hoy
existe `.parcial.xtf`). Para el lote completo o municipios grandes (Facatativá 41.144 predios, Anapoima,
Guaduas, Ubaté, Villeta) usar `JAVA_XMX` y preferir la terminal propia del usuario.

Ante una falla:

1. `dominios`: código sin equivalente → decidir la homologación con el usuario, agregarla a
   `config/homologaciones.csv` y documentarla en `03_...`.
2. `fix` / `verificar`: el mensaje dice qué control falló; ver `03_...` (catálogo de errores).
3. `exportar` / `validar`: corregir en la plantilla con una regla global y preventiva, nunca registro a registro.
   Después re-correr desde `etl` (partir de `etl` garantiza que `fix` trabaje sobre geometrías sin limpiar).
4. Antes de crear una regla nueva, medir su alcance en los 25 municipios (preflight) y registrarla en `03_...`.

**Criterio de entrega**: XTF + `.sha256` + `manifiesto.json`, con ilivalidator válido y `codigo.git_sin_commit`
vacío en el manifiesto (sin cambios pendientes en `etl/`, `config/`, `scripts/`). **Ningún XTF actual del lote
cumple este criterio** (ver §5).

## 5. Estado (2026-11-21, pausa pedida por el usuario tras Vergara)

| Municipio | Vig. | Estado | Predios | Avalúo (cuadra al peso) | sha256 del XTF | Commit del manifiesto |
|---|---|---|---|---|---|---|
| Chaguaní | 2023 | ✅ válido | 2.718 | $291.067.399.000 | `28004daf…` | 7cc7ca4 (piloto) |
| Nemocón | 2023 | ✅ válido | 5.983 | $598.625.016.000 | `36f40b57…` | 7cc7ca4 (piloto) |
| Quipile | 2024 | ✅ válido | 4.632 | $411.517.087.000 | `7a209551…` | 830aff7 + cambios (piloto) |
| Tibacuy | 2024 | ✅ válido | 3.334 | $389.063.655.000 | `c9af6e40…` | 92632d6 + cambios |
| Quebradanegra | 2023 | ✅ válido | 3.491 | $457.432.740.085 | `86da52e4…` | 92632d6 + cambios |
| Nocaima | 2023 | ✅ válido | 4.193 | $869.998.342.917 | `ee3507e3…` | 92632d6 + cambios |
| Sutatausa | 2023 | ✅ válido | 4.307 | $383.091.973.000 | `2955f659…` | 92632d6 + cambios |
| Tausa | 2023 | ✅ válido | 4.793 | $711.017.173.200 | `e5b77d08…` | 92632d6 + cambios |
| Tibirita | 2024 | ✅ válido | 5.134 | $325.077.199.000 | `d032b215…` | 92632d6 + cambios |
| Vergara | 2023 | ✅ válido | 6.123 | $513.820.120.000 | `6e249299…` | 92632d6 + cambios |
| Nimaima | 2023 | ⏸️ falla en `exportar` (D1) | 2.803 | $456.522.978.000 | — | 92632d6 + cambios |
| Guatavita | 2024 | ⏸️ falla en `validar` (D2) | 4.341 | $997.735.701.000 | — | 92632d6 + cambios |
| Supatá | 2023 | ⏸️ falla en `fix` (D3) | — | — | — | 92632d6 + cambios |
| Tocaima | 2024 | ⏳ sin correr; afectado por D2 | | | | |
| Anapoima, Subachoque | 2024 | ⏳ sin correr; afectados por D3 (Anapoima además es grande) | | | | |
| Arbeláez, Fómeque, Villeta, Ubaté | 2023 | ⏳ sin correr; sin bloqueo conocido | | | | |
| Anolaima, Guaduas, Apulo, San Antonio del Tequendama, Facatativá | 2024 | ⏳ sin correr; sin bloqueo conocido | | | | |

Notas:

- "Válido" = ilivalidator 1.15.0 sin errores. En todos los que llegaron a `verificar`, avalúo y número de
  predios cuadraron al peso (Nimaima y Guatavita incluidos).
- **Ningún XTF es entregable todavía**: todos se generaron con código distinto del actual (el piloto antes de
  las reglas de linderos, áreas, identificador y `ReducePrecision`; el resto con cambios sin commit, porque las
  reglas se agregaron durante el lote). Las reglas nuevas solo actúan donde existe la condición, así que se
  espera el mismo sha256 al re-correr, pero hay que comprobarlo (§7, paso 5).
- En `resumen_lote.csv` la columna `ili2pg` dice `valido` en las corridas anteriores al cambio de exportación
  (ili2pg validaba) y `exportado` en las posteriores (ili2pg solo escribe). La validez la da la columna `ilivalidator`.
- Los manifiestos generados antes del 2026-11-21 listan en `git_sin_commit` también las salidas del lote y
  recortan el primer carácter de la primera ruta (`ocs/…`); corregido en `lote.py` (solo `etl/`, `config/`,
  `scripts/`). Se regeneran en la corrida final.
- "Sin bloqueo conocido" significa que los preflights hechos sobre los 25 (fechas y áreas nulas, linderos
  gigantes, validez de ZH a 1 mm, derechos sin fuente) no detectaron nada; aún pueden aparecer casos nuevos.
- El mensaje del commit 155187c dice "11 municipios válidos"; son 10 (corregido en 3de1fa4).

**Piloto** (cerrado 2026-11-20): Chaguaní dio el mismo sha256 en dos corridas (proceso determinista). Nemocón
cambió respecto de su 1.ª corrida solo por la fecha del interesado placeholder (ya no usa `now()`).
**Regresión Nemocón** (`comparacion/informe_nemocon_lote25_vs_gestor_20261014.json`) contra el XTF "solo gestor"
del 2026-10-14 (mismo backup, sin operador): todas las clases de levantamiento idénticas (5.983 predios, mismo
avalúo, 6.993 interesados, 0 atributos distintos en predios). Diferencias esperadas: +14 `AV_TipologiaConstruccion`
(de `acc_2024`, decisión 2026-11-20) y −1 `CC_NomenclaturaVial` (tramo sin número de vía, regla de ilivalidator
posterior a ese XTF).

**Preflights sobre los 25** (2026-11-20):

- `comienzo_vida_util_version` nulo: Nocaima 1 terreno; Anapoima 52/13/13 (terrenos/construcciones/unidades);
  Anolaima 42 terrenos; Facatativá 77/18/7 + 3 características; Guatavita 26/11/11; Quipile 30; Apulo 2;
  San Antonio del Tequendama 37 construcciones, 34 unidades, 1 característica; Subachoque 24/16/14 + 11
  características, 2 derechos, 3 interesados; Tocaima 1 terreno. Cubierto por la regla aprobada.
- Áreas MANDATORY nulas: ver `03_...` (cubierto por regla global).
- Linderos con más de 5.000 puntos: solo Nimaima (D1). Máximo en los demás: 4.944.
- ZH inválidas a 1 mm: Guatavita y Tocaima (D2).
- Derechos sin ninguna fuente: Supatá, Anapoima, Subachoque (D3).

## 6. Decisiones pendientes del usuario

Cada una se implementaría como regla global en la plantilla, con métrica en `verificar` y registro en `03_...`.

### D1 — Nimaima: 2 linderos gigantes

- **Hechos**: un lindero de 38.308 puntos / 54,8 km que delimita 204 terrenos y otro de 16.569 puntos / 69,5 km
  con 498 terrenos. ili2pg (validando) e ilivalidator pasan más de 30 min en la relación `col_puntoCcl` sin
  terminar (el costo crece más que proporcional al número de puntos por lindero). ili2pg sin validación exporta
  en 1,5 min. Ningún otro municipio supera 5.000 puntos por lindero.
- **Opciones**: (a) excluir esos 2 linderos con sus `col_puntoCcl`, `col_masCcl`/`col_menosCcl` y los puntos que
  queden sin lindero (los terrenos se conservan), con un umbral global de puntos por lindero; (b) conservarlos y
  entregar Nimaima sin validación completa.
- **Propuesta**: (a).

### D2 — Zonas homogéneas que no son válidas a 1 mm

- **Hechos**: Guatavita 1 ZHG rural (válida en el origen; el redondeo a 1 mm la invalida; ilivalidator:
  `Intersection coord1 (4903772,562, 2107550,691)`). Tocaima 2 ZHF urbanas inválidas ya en el origen + 1 ZHG
  urbana que el redondeo invalida. Hoy las ZH no se modifican (regla Sutatausa) y `verificar` lo controla con
  `zh_modificadas_vs_backup = 0`.
- **Opciones**: (a) solo para las ZH inválidas, `ST_ReducePrecision` a 1 mm (desplazamiento < 1 mm; Guatavita
  0,93 mm y 0,08 m² sobre 7.327 ha) y `ST_MakeValid` para las inválidas de origen; `verificar` las contaría
  aparte (p. ej. `zh_ajustadas_precision`) y seguiría exigiendo 0 en el resto; (b) excluir esas ZH; (c) no
  entregar Guatavita/Tocaima hasta que el gestor corrija la fuente.
- **Propuesta**: (a).

### D3 — Derechos sin ninguna fuente administrativa

- **Hechos**: posesiones/ocupaciones sin `col_rrrfuente` ni fuente en `col_unidadfuente` del predio: Supatá 160
  (detectado por `fix`), Anapoima 37 y Subachoque 1 (preflight). El modelo exige ≥ 1 fuente por derecho y el
  dominio tiene `Sin_Documento`.
- **Opciones**: (a) una fuente placeholder por derecho, tipo `Sin_Documento`, estado `Desconocido` (como el
  interesado `SIN DATO`), con métrica `imputado_fuente_sin_documento`; (b) excluir esos predios (rompería el
  cuadre de avalúo, que hoy aborta); (c) pedir las fuentes al gestor.
- **Propuesta**: (a).

## 7. Retomar aquí (sesión nueva)

Estado al cerrar la sesión del 2026-11-21: rama `lote-25-municipios`, sin push, árbol limpio, nada corriendo.
Las BD de trabajo `l25_*` existentes se recrean al correr.

1. **Comprobar entorno**: `git status` limpio en la rama; `.env` con `JAVA_XMX=4g` (lo agrega el usuario; el
   asistente no edita `.env`); ningún proceso `java` vivo; memoria libre.
2. **Obtener D1, D2 y D3** (§6). Implementarlas como reglas globales, medir su alcance en los 25 (preflight),
   documentarlas en `03_...` y en este documento.
3. **Correr los 9 sin bloqueo conocido**, uno a la vez y en primer plano (§4): `arbelaez`, `fomeque`, `villeta`,
   `ubate`, `anolaima`, `guaduas`, `apulo`, `san_antonio_tequendama` y, al final, `facatativa`. Si aparece una
   falla nueva, resolverla con regla global (§4) o llevarla al usuario como decisión.
4. **Correr los afectados** una vez implementadas las decisiones: `nimaima`, `guatavita`, `tocaima`, `supata`,
   `anapoima`, `subachoque` (desde `extraer`; el dump se reutiliza).
5. **Corrida final uniforme**: commit sin cambios en `etl/`, `config/`, `scripts/`; re-correr los 25 desde
   `preparar` (idealmente `python scripts/lote.py --todos` en la terminal del usuario, con `JAVA_XMX`); comparar
   cada sha256 con el anterior y explicar cualquier diferencia; verificar `codigo.git_sin_commit` vacío en los 25.
6. **Cerrar**: `python scripts/lote.py --reporte`, actualizar §5, commit. Push o PR solo si el usuario lo pide.

Fuera de este lote (etapas posteriores, sin fecha):

- Mezcla con el XTF del operador (etapas `complemento`, `cancelados`, `operador`), incluidas las ZHF urbanas
  2023 de Arbeláez, Fómeque y Nemocón, hoy vacías.
- Centralizar los rangos de `t_id` (hoy constantes repetidas en el SQL).
- Herramienta de seguimiento (`04_...`) alimentada por los manifiestos.
- Predios sin unidad espacial (p. ej. Nemocón 527, Tibacuy 277): evaluar con el gestor.

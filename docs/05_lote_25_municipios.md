# Lote de 25 municipios con actualización catastral (vigencias 2023 y 2024)

> Iniciado 2026-11-20 en la rama `lote-25-municipios`. Proceso: `scripts/lote.py` (ver §4).

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

## 2. Decisiones del usuario (2026-11-20)

| Tema | Decisión |
|---|---|
| Mezcla con XTF del operador (etapas `complemento`, `cancelados`, `operador`) | **No** en este lote; se hará en una etapa posterior |
| Municipios ya migrados (Tibirita, Tibacuy, Vergara, Sutatausa, Nemocón) | Se reprocesan igual que el resto, en `salida/lote_25/`. Los XTF ya entregados no se tocan (sirven de regresión) |
| Actualización solo urbana | Se migran todos los predios con avalúo de la vigencia (urbanos y rurales), como Nemocón |
| Decisiones previas (Mejora→Informal, No_Binario/Otro→Sin_Determinar, NUIP→Registro_Civil, placeholder `SIN DATO`, fuentes desde `col_unidadfuente`, valores catastrales) | Aplican a todos por defecto |
| ZH de Arbeláez, Fómeque y Nemocón | Rurales: última vigencia disponible (2021, `zh_ultima_vigencia=si`). ZHF urbanas 2023: no existen en las BD de corte → **vacías** por ahora |
| `AV_TipologiaConstruccion` de los 13 de 2023 | `acc_mayo_2023` no trae `tb_valortipologia`; se toma de `acc_2024` **solo** esa tabla con vigencia 2023 (como Sutatausa con el backup 2026). Los 12 de 2024 la traen en su propio esquema |
| Validación | Debe pasar ili2pg **e** ilivalidator 1.15.0 |

## 3. Cambios al proceso (Fase 1)

| Cambio | Antes | Ahora |
|---|---|---|
| Insumo | Backup pg_dump completo por municipio, entregado a mano | `pg_dump -n cunXXXXX` de la BD de corte (`insumos/lote_25/`, con sha256 en el manifiesto) |
| Esquema destino | Clon de `lev_cat_12` desde la BD `tibacuy_lev12` | `etl/esquema/lev_cat_12_plantilla.sql` versionado. Catálogos verificados idénticos (ilicode, dispname, description) a un `--schemaimport` limpio de ili2pg 5.5.1 y en las 6 BD ya migradas |
| Homologaciones | `CASE` en el SQL | `config/homologaciones.csv` + `public.fx_hom` (`00_homologaciones.sql`), validadas contra el dominio destino |
| Chequeo de dominios | Informativo | Aborta si hay códigos sin equivalente (usa el mismo método que el ETL). ZHF: solo aviso (decisión Nemocón) |
| `fix` | Tabla final "debe dar 0" | Aborta si un control ≠ 0; agrega `predios_sin_derecho`, `derechos_sin_fuente`, `agrup_sin_miembros` |
| `verificar` | Informativo | Aborta si no cuadran avalúo, predios, duplicados, ZH o copropiedad; salida `clave|valor` con métricas de imputaciones y exclusiones y conteo por clase |
| Universo | Todos los interesados, agrupaciones, linderos y puntos de lindero del municipio | Solo los ligados a derechos / unidades espaciales migradas (las métricas informan cuántos se excluyen) |
| `Local_Id` / `Espacio_De_Nombres` | `COALESCE(valor, id)`: el `''` del origen pasaba | Vacío o NULL → id / nombre de clase (ilivalidator lo rechazaba; Chaguaní: 2 fuentes) |
| Validación | ili2pg (`export done`) | ili2pg **+** ilivalidator (`validation done`); el `.sha256` solo se genera si pasan ambos |
| Trazabilidad | Logs sueltos | `salida/lote_25/<mun>/manifiesto.json`: fuente y sha256 del dump, commit y sha256 de cada SQL, versiones de herramientas, tiempos por etapa, métricas, sha256 del XTF. `salida/lote_25/resumen_lote.csv` consolidado |

Pendiente (no bloquea el lote): centralizar los rangos de `t_id` (hoy constantes repetidas en el SQL);
herramienta de seguimiento (`04_...`) alimentada por los manifiestos.

## 4. Operación

```bash
python scripts/lote.py --piloto                 # Nemocón, Chaguaní, Quipile
python scripts/lote.py chaguani quipile         # por nombre corto (columna mun)
python scripts/lote.py --todos
python scripts/lote.py nemocon --desde etl      # reanudar desde una etapa
python scripts/lote.py --reporte                # solo regenerar resumen_lote.csv
```

Etapas: `extraer → preparar → tipologias → dominios → etl → fix → verificar → exportar → validar`.
BD de trabajo `l25_<mun>` (se recrea en `preparar`; el script solo borra BD con prefijo `l25_`).
Logs en `logs/lote_25/<mun>/`. Un municipio que falla no detiene el lote; el resumen indica en qué etapa.

Ante una falla:

1. `dominios`: código sin equivalente → decidir la homologación con el usuario, agregarla a
   `config/homologaciones.csv` y documentarla en `03_...`.
2. `fix` / `verificar`: el mensaje dice qué control falló; ver `03_...` (catálogo de errores).
3. `exportar` / `validar`: corregir en la plantilla con una regla global y preventiva, nunca registro a registro.

Para entregar: XTF + `.sha256` + `manifiesto.json`, generados desde un commit sin cambios pendientes
(`codigo.git_sin_commit` vacío en el manifiesto).

## 5. Resultados

Ver `salida/lote_25/resumen_lote.csv` (se regenera en cada corrida) y el manifiesto de cada municipio.

### Piloto (2026-11-20) — cerrado

Los tres generados con el código final (corridas en primer plano, una a la vez).

| Municipio | Predios | Avalúo (cuadra al peso) | ili2pg | ilivalidator | sha256 | Nota |
|---|---|---|---|---|---|---|
| Chaguaní (2023) | 2.718 | $291.067.399.000 | válido | válido (0 errores, 0 avisos) | `28004daf…` | Detectó `Local_Id` vacío. Mismo sha256 en dos corridas: el proceso es determinista |
| Quipile (2024) | 4.632 | $411.517.087.000 | válido | válido | `7a209551…` | Detectó `comienzo_vida_util_version` nulo (30 terrenos imputados) |
| Nemocón (2023) | 5.983 | $598.625.016.000 | válido | válido | `36f40b57…` | Cambia respecto de la 1.ª corrida solo por la fecha del interesado placeholder (ya no usa `now()`) |

Regla de `comienzo_vida_util_version` aprobada por el usuario el 2026-11-20.

Tiempo por municipio pequeño: ~6 min (exportar ~3 min, ilivalidator ~1,5 min).

**Regresión Nemocón** (`comparacion/informe_nemocon_lote25_vs_gestor_20261014.json`) contra el XTF "solo gestor" del
2026-10-14 (mismo backup, sin operador): todas las clases de levantamiento idénticas (5.983 predios, mismo avalúo,
6.993 interesados, 0 atributos distintos en predios). Diferencias esperadas: +14 `AV_TipologiaConstruccion`
(de `acc_2024`, decisión 2026-11-20) y −1 `CC_NomenclaturaVial` (tramo sin número de vía, regla de ilivalidator
posterior a ese XTF).

**Preflight de los 25** (`comienzo_vida_util_version` nulo en el origen): Nocaima 1 terreno; Anapoima 52/13/13
(terrenos/construcciones/unidades); Anolaima 42 terrenos; Facatativá 77/18/7 + 3 características; Guatavita 26/11/11;
Quipile 30; Apulo 2; San Antonio del Tequendama 37 construcciones, 34 unidades, 1 característica; Subachoque 24/16/14
+ 11 características, 2 derechos, 3 interesados; Tocaima 1 terreno. Cubierto por la regla global (ver `03_...`).

**Memoria**: el equipo tiene 16 GB y ~2,5 GB libres durante la corrida. Para municipios grandes (Facatativá
41.144 predios, Anapoima, Guaduas, Ubaté, Villeta) definir `JAVA_XMX` en `.env` y correr el lote desde una
terminal propia (no como tarea en segundo plano de Claude Code, que la detiene si falta memoria).

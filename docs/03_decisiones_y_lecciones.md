# Decisiones sobre datos y lecciones aprendidas

Registro de las decisiones de homologación tomadas por municipio y el catálogo de errores
de validación con su causa raíz y solución probada. **Consultar antes de resolver un error
nuevo**: casi todo lo que falla ya falló antes.

## Decisiones de homologación

### Comunes a todos los municipios

| Situación | Decisión | Justificación |
|---|---|---|
| `tb_valortipologia.tipo_anexo` (anexos: pozos, silos, tanques…) | Se excluyen del submodelo Avalúos | `AV_TipologiaTipo` v1.2 no contempla anexos; solo se migran tipologías con equivalente |
| `gc_predio.tipo` (`Privado`, `Publico.*`) | Se antepone `Predio.` al ilicode | El dominio destino `col_unidadadministrativabasicatipo` usa ruta completa (`Predio.Privado`) |
| Predios sin terreno/construcción en `col_uebaunit` | Se migran igual | El modelo permite predios sin unidad espacial (informales, mejoras); queda registrado el conteo |
| Geometrías vacías tras limpieza (área < tolerancia) en construcción/unidad | `geometria = NULL` | El atributo es opcional en esas clases; eran astillas degeneradas sin valor catastral |
| `resultado_visita` (texto libre) | CASE de homologación a ilicodes (`No permitieron acceso` → `No_Permitieron_Acceso`, etc.) | Ver ETL sección 11 |

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

## Catálogo de errores de validación ili2pg

### `duplicate coord at (x, y, z)`

- **Causa raíz**: dos vértices consecutivos que quedan idénticos al redondear a 3 decimales
  (el XTF escribe coordenadas con precisión de 1 mm). El origen más frecuente **no son los
  datos fuente**, sino `ST_MakeValid` aplicado al final del pipeline: al resolver polígonos
  con auto-intersección crea vértices nuevos fuera de la grilla y polígonos "astilla" de
  área ~0 con vértices a <1 mm.
- **Solución probada** (función `fx_limpiar_poligono` en los scripts 02/03):
  1. `ST_MakeValid` **primero** (resuelve auto-intersecciones),
  2. descartar componentes con `ST_Area < 0.01` m² (astillas),
  3. `ST_SnapToGrid(geom, 0.001)` (alinear a la precisión del XTF),
  4. `ST_RemoveRepeatedPoints(geom, 0.002)`.
- **No sirve**: aplicar solo `ST_RemoveRepeatedPoints` (no elimina pares en anillos de 4
  puntos, ni vértices creados después por MakeValid), o arreglar registro por registro
  (el validador se detiene en el primer error y el ciclo es interminable).

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
  (script `03_fix_revalidacion_tibirita.sql`, sección b).

### `Self-intersection at or near point ...` (ST_IsValid falla tras el snap)

- **Causa**: el snap a grilla puede reintroducir una micro auto-intersección en polígonos
  muy irregulares.
- **Solución**: para el registro afectado, `ST_Buffer(geom, 0)` y volver a pasar
  `fx_limpiar_poligono`.

### Violación NOT NULL en el INSERT del ETL

- **Causa**: campos MANDATORY del modelo con NULL en la fuente (ej. `documento_identidad`).
- **Solución**: completar con dato real si existe en otros registros de la fuente (caso NIT
  municipio); si no, placeholder documentado (`Sin_Dato`). Nunca dejar pasar silenciosamente:
  registrar la decisión en este documento.

## Lecciones de proceso

1. **ili2pg escribe el XTF aunque la validación falle.** Verificar siempre que el log
   termine en `...export done`. El XTF "fallido" de Tibirita circuló como si fuera válido.
2. **Clonar `lev_cat_12` de una BD ya migrada** en vez de correr `--schemaimport` de nuevo:
   garantiza t_id de catálogos idénticos y evita diferencias de flags.
3. La extensión **`uuid-ossp`** debe existir antes de restaurar el esquema clonado.
4. **Prefijar los OID (`t_ili_tid`) con el municipio** (`md5('<mun>_tabla'||id)`): sin
   prefijo, dos municipios generan los mismos UUID para los mismos id y colisionarían al
   cargarse juntos.
5. El validador reporta **un error por clase por pasada**: los fixes deben ser globales y
   preventivos, no reactivos registro a registro.
6. Verificación de cierre que no falla: la **suma de avalúos** origen (vigencia) vs
   `lc_predio.avaluo_catastral` debe coincidir al peso.

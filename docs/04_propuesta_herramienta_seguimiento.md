# Propuesta — Herramienta de seguimiento de migraciones LADM-COL

> Propuesta de desarrollo. Estado: borrador para discusión. 2026-08-28.

## 1. Problema

Hoy el seguimiento de cada migración (¿cuántos registros trae la fuente?, ¿cuántos se
migraron?, ¿qué se excluyó y por qué?, ¿el XTF validó?) vive disperso en consultas SQL
ad-hoc, logs de ili2pg y la memoria de quien ejecutó el proceso. Consecuencias reales ya
observadas:

- Un XTF **inválido** (Tibirita) circuló como entregable porque nadie verificó el final del
  log de exportación.
- Las cifras de control (3.334 de 3.339 predios migrados, 277 predios sin unidad espacial,
  60 códigos de anexos excluidos) no quedan registradas en ningún lado consultable.
- Cada municipio nuevo repite el mismo ciclo de diagnóstico manual.

## 2. Objetivo

Una herramienta que, para cada corrida de migración, **capture automáticamente** las
métricas de origen, destino y validación, las **persista como historial** y las **muestre
en un dashboard** comparativo, de modo que cualquier miembro del equipo pueda responder en
segundos: *¿cómo quedó la migración de X municipio y qué quedó por fuera?*

## 3. Usuarios y casos de uso

| Usuario | Caso de uso |
|---|---|
| Ingeniero de migración | Ver en vivo el resultado de su corrida; detectar caídas de registros entre etapas |
| Coordinador / calidad | Verificar estado de validación XTF antes de entregar; comparar municipios |
| Auditoría / soporte | Reconstruir qué se excluyó y con qué justificación, meses después |

## 4. Alcance funcional

### 4.1 Métricas por corrida (el corazón de la herramienta)

Para cada municipio/corrida se capturan tres bloques:

**A. Fuente (esquema `cunXXXXX`)**
- Conteo por entidad: predios, terrenos, construcciones, unidades, interesados, derechos,
  fuentes, direcciones, zonas homogéneas, cartografía.
- Predios por vigencia de avalúo (la base del filtro).
- Calidad de entrada: campos obligatorios nulos, códigos de dominio sin equivalente
  (salida del `00_check_dominios`), geometrías inválidas, duplicados (miembros, avalúos
  por predio).

**B. Migrado (esquema `lev_cat_12`)**
- Conteo por entidad (mismas categorías) → **tasa de migración** = migrado / fuente elegible.
- Exclusiones con motivo: predios sin avalúo de la vigencia, unidades sin construcción o
  características, anexos sin equivalente, huérfanos.
- Transformaciones aplicadas: homologaciones de dominio (NUIP→Registro_Civil), datos
  completados (NIT municipio), geometrías anuladas.
- Cifras de control contable: **suma de avalúos origen vs destino** (debe cuadrar al peso),
  áreas totales de terreno/construcción.

**C. Validación y entrega**
- Resultado del export ili2pg (`done` / `failed`) parseado del log, con conteo de errores
  por tipo (duplicate coord, OID, multiplicidad…).
- Hash y fecha del XTF entregado → evita el problema del "XTF fallido que circula".

### 4.2 Dashboard (vista propuesta)

```
┌─────────────────────────────────────────────────────────────────────┐
│  Migraciones LADM-COL Lev Cat v1.2          [Municipio: Tibacuy ▼]  │
├─────────────┬─────────────┬─────────────────┬───────────────────────┤
│ XTF: VÁLIDO │ Predios     │ Avalúo cuadrado │ Última corrida        │
│  ✅ 17:04   │ 3.334/3.339 │ ✅ $389.063 M   │ 2026-08-28 (corrida 3)│
├─────────────┴─────────────┴─────────────────┴───────────────────────┤
│  Embudo de migración por entidad        Fuente → Elegible → Migrado │
│  Predios          ▓▓▓▓▓▓▓▓▓▓ 3.339 → 3.334 → 3.334                  │
│  Terrenos         ▓▓▓▓▓▓▓▓▓  3.106 → 3.042 → 3.042                  │
│  Unidades constr. ▓▓▓▓▓▓▓▓   3.783 → 3.681 → 3.681                  │
│  Interesados      ▓▓▓▓▓▓▓▓▓▓ 4.574 → 4.574 → 4.574                  │
├──────────────────────────────────┬──────────────────────────────────┤
│  Exclusiones (con drill-down)    │  Validación XTF (historial)      │
│  • 5 predios sin avalúo 2024     │  Corrida 1  ❌ 3 errores geom.   │
│  • 102 unidades sin caract.      │  Corrida 2  ❌ 1 error geom.     │
│  • 60 anexos sin equivalente     │  Corrida 3  ✅ export done       │
│  • 277 predios sin unidad esp.   │                                  │
├──────────────────────────────────┴──────────────────────────────────┤
│  Comparativo municipios: Tibirita ✅ · Tibacuy ✅ · <siguiente> ⏳   │
└─────────────────────────────────────────────────────────────────────┘
```

Interacciones clave: drill-down de cada exclusión hasta la lista de registros (números
prediales concretos), diff entre corridas, y mapa opcional (PostGIS ya tiene las capas)
para ver terrenos/construcciones migradas vs fuente.

## 5. Arquitectura propuesta

Principio: **la captura de métricas es SQL puro que se acopla al pipeline existente**; el
dashboard es solo una vista encima. Así la herramienta sirve aunque el dashboard evolucione.

```
Backup cunXXXXX ─▶ ETL (scripts actuales) ─▶ lev_cat_12 ─▶ ili2pg ─▶ XTF
        │                    │                   │            │
        ▼                    ▼                   ▼            ▼
   99_metricas_fuente.sql  99_metricas_migracion.sql   parser de logs
        └──────────────┬─────────────────┴────────────────┘
                       ▼
         esquema `seguimiento` (BD central de métricas)
                       ▼
                  Dashboard web
```

### Componentes

1. **Esquema `seguimiento`** (PostgreSQL, BD central o la misma de trabajo):

```sql
corrida        (id, municipio, esquema_origen, bd, vigencia, fecha, ejecutor, etapa_final)
metrica        (corrida_id, bloque {fuente|migrado|validacion}, entidad, nombre, valor_num, valor_texto)
exclusion      (corrida_id, entidad, motivo, cantidad)
exclusion_det  (corrida_id, motivo, id_origen, numero_predial)     -- drill-down
transformacion (corrida_id, regla, cantidad, descripcion)          -- NUIP→Registro_Civil, etc.
validacion     (corrida_id, resultado, errores_total, xtf_ruta, xtf_hash, xtf_bytes)
validacion_err (corrida_id, clase, tipo_error, tid, detalle)       -- parseado del log ili2pg
```

2. **Scripts de captura** (`etl/99_metricas_*.sql`): consultas parametrizadas por esquema
   que insertan en `seguimiento`. Se ejecutan con `psql -v` al final de cada etapa del
   runbook (son las mismas consultas de verificación que hoy se corren a mano).

3. **Parser de logs ili2pg** (Python, ~100 líneas): convierte `export_<mun>.log` en filas
   de `validacion` y `validacion_err`. Ya conocemos los patrones (`duplicate coord`,
   `has to have an OID`, `should associate`, `...export done|failed`).

4. **Dashboard**: dos opciones según ambición —

| Opción | Stack | Esfuerzo | Cuándo elegirla |
|---|---|---|---|
| **A. Ligera (recomendada para empezar)** | Streamlit + plotly, leyendo el esquema `seguimiento` | 1–2 semanas | Equipo pequeño, uso interno, iterar rápido |
| B. Web completa | FastAPI + React + mapa (MapLibre sobre pg_tileserv) | 6–8 semanas | Si se vuelve herramienta institucional multiusuario |

La opción A no excluye la B: comparten el esquema `seguimiento`.

## 6. Fases de desarrollo

| Fase | Entregable | Esfuerzo estimado |
|---|---|---|
| 1. Fundación | Esquema `seguimiento` + scripts `99_metricas_*` integrados al runbook + carga retroactiva de Tibirita y Tibacuy | 3–5 días |
| 2. Validación | Parser de logs ili2pg + registro de hash del XTF | 2–3 días |
| 3. Dashboard v1 | Streamlit: tarjetas de estado, embudo por entidad, tabla de exclusiones con drill-down, historial de corridas | 1–2 semanas |
| 4. Comparativos | Vista multi-municipio, diff entre corridas, exportación de reporte (PDF/MD) para entregas | 1 semana |
| 5. (Opcional) Mapa | Capa geográfica fuente vs migrado con simbología por estado | 1–2 semanas |

## 7. Criterios de éxito

- Ninguna entrega de XTF sin registro `validacion.resultado = 'done'` y hash coincidente.
- El 100% de las exclusiones de una corrida tienen motivo registrado y son navegables
  hasta el número predial.
- Retomar un municipio meses después no requiere leer logs: el dashboard responde qué se
  migró, qué no y por qué.

## 8. Riesgos y decisiones abiertas

- **¿BD central de métricas o esquema por BD de trabajo?** Propuesta: BD central
  (`seguimiento_ladm`) para que el comparativo multi-municipio sea trivial.
- **Retención de `exclusion_det`**: puede crecer; definir si se guarda siempre o solo el
  agregado con opción de regenerar el detalle.
- **Acceso**: si el dashboard sale del equipo, agregar autenticación (fase B).
- Los scripts ETL actuales son por municipio (copias con sed); la herramienta empuja a
  **parametrizarlos** (una plantilla + tabla de configuración por municipio), lo cual es
  deuda técnica sana de pagar en la Fase 1.

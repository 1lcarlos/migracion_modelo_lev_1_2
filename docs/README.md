# Documentación — Migración al modelo LADM-COL Lev Cat v1.2

Documentación del proceso de migración de bases de gestores catastrales (esquemas `cunXXXXX`)
al modelo LADM-COL Levantamiento Catastral v1.2, con salida a XTF validado por ili2pg.

| Documento | Contenido | Cuándo usarlo |
|---|---|---|
| [01_contexto_general.md](01_contexto_general.md) | Estado actual, entorno, bases de datos, rutas y herramientas | **Leer primero al retomar el proyecto** |
| [02_runbook_migracion.md](02_runbook_migracion.md) | Paso a paso reproducible para migrar un municipio nuevo | Al iniciar la migración de otro municipio |
| [03_decisiones_y_lecciones.md](03_decisiones_y_lecciones.md) | Decisiones sobre datos, catálogo de errores y sus soluciones | Cuando la validación falle o haya dudas de mapeo |
| [04_propuesta_herramienta_seguimiento.md](04_propuesta_herramienta_seguimiento.md) | Propuesta de herramienta/dashboard de seguimiento de migraciones | Para planear el desarrollo de la herramienta |

## Estado al 2026-10-02

- **Tibirita** (cun25807 → `tibirita_lev12`, vigencia 2024): XTF válido en `salida/tibirita_lev_cat_v1_2_vigencia2024.xtf` (scripts históricos).
- **Tibacuy** (cun25805 → `tibacuy_lev12`, vigencia 2024): XTF válido en `salida/tibacuy_lev_cat_v1_2_vigencia2024.xtf` (scripts históricos).
- **Vergara** (cun25862 → `vergara_lev12`, vigencia 2023): XTF válido en `salida/vergara_lev_cat_v1_2_vigencia2023.xtf` (+ `.sha256`), generado con la plantilla parametrizada.

Desde 2026-10-02 toda migración nueva se ejecuta con `scripts/migrar.sh <municipio>` y la
plantilla `etl/plantilla/` (ver runbook).

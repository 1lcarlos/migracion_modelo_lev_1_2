# Documentación — Migración al modelo LADM-COL Lev Cat v1.2

Documentación del proceso de migración de bases de gestores catastrales (esquemas `cunXXXXX`)
al modelo LADM-COL Levantamiento Catastral v1.2, con salida a XTF validado (ilivalidator 1.15.0).

| Documento | Contenido | Cuándo usarlo |
|---|---|---|
| [01_contexto_general.md](01_contexto_general.md) | Estado actual, entorno, bases de datos, rutas y herramientas | **Leer primero al retomar el proyecto** |
| [02_runbook_migracion.md](02_runbook_migracion.md) | Paso a paso del flujo heredado `migrar.sh` (backup entregado + XTF del operador) | Migraciones fuera del lote o mezcla con el operador |
| [03_decisiones_y_lecciones.md](03_decisiones_y_lecciones.md) | Decisiones sobre datos, catálogo de errores y sus soluciones | Cuando la validación falle o haya dudas de mapeo |
| [04_propuesta_herramienta_seguimiento.md](04_propuesta_herramienta_seguimiento.md) | Propuesta de herramienta/dashboard de seguimiento de migraciones | Para planear el desarrollo de la herramienta |
| [05_lote_25_municipios.md](05_lote_25_municipios.md) | Lote de 25 municipios (2023/2024): universo, fuentes, decisiones, operación de `scripts/lote.py`, estado, decisiones pendientes | **Proceso vigente**. §7: retomar aquí |

## Estado al 2026-11-21

- **Lote de 25 municipios** (rama `lote-25-municipios`, en pausa): 10 válidos con ilivalidator, 3 detenidos por
  decisiones pendientes del usuario, 9 sin correr; falta la corrida final desde un commit limpio. Detalle y
  próximos pasos: [`05_lote_25_municipios.md`](05_lote_25_municipios.md) §5–§7.
- **Entregados antes del lote** (flujo heredado, no se modifican): Tibirita, Tibacuy, Vergara, Sutatausa y Nemocón
  (ver tabla en [`01_contexto_general.md`](01_contexto_general.md)).

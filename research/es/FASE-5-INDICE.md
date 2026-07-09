# Fase 5 — Contratos del kernel (suspend lifecycle)

> Rama: `research/suspend-lifecycle`  
> [English](../INDEX.md)

## Idea

Dejar de añadir parches de retry. Entender **qué contrato incumple** cada capa (ACP → SDW → codec → FW).

## 10 líneas paralelas

| ID | Tema |
|----|------|
| T01 | Máquina de estados boot → Dummy |
| T02 | Callbacks PM (`probe` … `resume`, `fw_ready`) |
| T03 | Ownership de estructuras |
| T04 | Comparar con otros codecs SDW |
| T05 | Orden temporal fino en resume |
| T06 | ACP70 resume (no boot -22) |
| T07 | Invariantes |
| T08 | Diff firmware 8 vs B (solo lectura) |
| T09 | Bucle estadístico N× suspend |
| T10 | Enfoque upstream / maintainer |

## Prioridad

[PRIORITY-RESUME-TRACE.md](../PRIORITY-RESUME-TRACE.md) — ACP sale de suspend → primer `trigger()` en `:8`.

## Scripts

```bash
./scripts/phase5-resume-collect.sh --notes "N"
./scripts/phase5-check-invariants.sh
./scripts/phase5-resume-stats-loop.sh --count 20   # con cuidado
```

## Pausado en esta rama

Parches de `usleep`/retry sin prueba de contrato roto.

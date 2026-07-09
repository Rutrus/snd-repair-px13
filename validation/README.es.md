# Validación Serie B — base de datos reproducible

> [English](README.md) | **Español**

Directorio generado por `scripts/fw-validation-collect.sh`. No editar CSV a mano salvo correcciones.

## Estructura

```
validation/
├── fw-matrix.csv
├── fw-summary.md
└── boot-logs/
```

## Tras cada arranque

```bash
./scripts/fw-validation-run.sh boot
./scripts/fw-validation-run.sh boot --notes "0006+0007+0009"
```

## Con prueba de audio

```bash
./scripts/fw-validation-run.sh boot-audio
```

## Tras suspend/resume

```bash
./scripts/fw-validation-run.sh suspend
```

## Matriz de frecuencias (sin reboot)

```bash
./scripts/fw-validation-run.sh rates
```

## Ver progreso

```bash
./scripts/fw-validation-run.sh status
cat validation/fw-summary.md
```

## CSV — columnas

| Columna | Significado |
|---------|-------------|
| `uid8_fw` / `uidb_fw` | `OK`, `WARN`, `FAIL110`, `FAIL?` |
| `left_audio` / `right_audio` | `1`/`0`/vacío (solo con `--audio`) |
| `regression_capture` | `YES` = Problema A (Serie A) |
| `suspend_resume` | `boot` o `suspend_resume` |

## Objetivo RFC

Ver `upstream/series-B-firmware/VALIDATION-TODO.md` y `upstream/SUBMISSION-PLAN.md`.

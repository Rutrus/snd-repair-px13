# FW validation summary

Generado: 2026-07-09T13:29:33
Fuente: `validation/fw-matrix.csv`

## Boots analizados: **2**

### Éxito global FW (ambos UIDs OK)

- **2/2** (100.0%)

### UID `:8` (tas2783-1 / Left)

- `OK`: 2

### UID `:b` (tas2783-2 / Right)

- `OK`: 2

### Regresión capture (Problema A)

- `REGRESSION_CAPTURE=YES`: **1/2**

### Audio L+R (entradas con --audio)

- Ambos canales OK: **1/1** (100.0%)

### Por contexto (`suspend_resume`)

- **boot**: 2/2 OK global

### Por frecuencia (`rate`)

- **48000 Hz**: 2/2 OK global

### Kernels

- `7.0.0-27-generic`: 2 boots

## Tabla completa

| boot | timestamp | :8 | :b | L | R | ctx | rate | regr | notes |
|------|-----------|----|----|---|---|-----|------|------|-------|
| 1 | 2026-07-09T12:58 | OK | OK | 1 | 1 | boot | 48000 | NO | 0006+0007+0009 L/R validado manual |
| 2 | 2026-07-09T13:29 | OK | OK |  |  | boot | 48000 | YES | smoke-test |

## Criterio RFC Serie B (objetivo)

- 20–30 boots, 0× `FAIL110` en `:b`
- Suspend/resume ≥6/6 OK
- Rates 44100 / 48000 / 96000 sin regresión
- `regression_capture=NO` en todos los boots

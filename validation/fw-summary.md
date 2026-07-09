# FW validation summary

Generado: 2026-07-09T20:37:34
Fuente: `/home/rutrus/snd_repair/validation/fw-matrix.csv`

## Boots analizados: **16**

### Éxito global FW (ambos UIDs OK)

- **8/16** (50.0%)

### UID `:8` (tas2783-1 / Left)

- `OK`: 8
- `WARN`: 8

### UID `:b` (tas2783-2 / Right)

- `OK`: 16

### Regresión capture (Problema A)

- `REGRESSION_CAPTURE=YES`: **0/16**

### Audio L+R (entradas con --audio)

- Ambos canales OK: **1/1** (100.0%)

### Por contexto (`suspend_resume`)

- **boot**: 7/8 OK global
- **suspend_resume**: 1/8 OK global

### Por frecuencia (`rate`)

- **48000 Hz**: 8/16 OK global

### Kernels

- `7.0.0-27-generic`: 16 boots

## Tabla completa

| boot | timestamp | :8 | :b | L | R | ctx | rate | regr | notes |
|------|-----------|----|----|---|---|-----|------|------|-------|
| 1 | 2026-07-09T12:58 | OK | OK | 1 | 1 | boot | 48000 | NO | 0006+0007+0009 L/R validado manual |
| 2 | 2026-07-09T17:04 | WARN | OK |  |  | boot | 48000 | NO | auto@boot |
| 3 | 2026-07-09T17:16 | WARN | OK |  |  | suspend_resume | 48000 | NO |  |
| 4 | 2026-07-09T17:21 | WARN | OK |  |  | suspend_resume | 48000 | NO | manual@suspend |
| 5 | 2026-07-09T17:22 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 6 | 2026-07-09T17:25 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 7 | 2026-07-09T17:29 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 8 | 2026-07-09T17:52 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 9 | 2026-07-09T18:00 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend-manual-recovery |
| 10 | 2026-07-09T19:22 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 11 | 2026-07-09T19:27 | OK | OK |  |  | boot | 48000 | NO | pre-suspend-ok |
| 12 | 2026-07-09T19:30 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 13 | 2026-07-09T20:00 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 14 | 2026-07-09T20:09 | WARN | OK |  |  | suspend_resume | 48000 | NO | resume-20:05-fail |
| 15 | 2026-07-09T20:37 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 16 | 2026-07-09T20:37 | OK | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |

## Criterio RFC Serie B (objetivo)

- 20–30 boots, 0× `FAIL110` en `:b`
- Suspend/resume ≥6/6 OK
- Rates 44100 / 48000 / 96000 sin regresión
- `regression_capture=NO` en todos los boots

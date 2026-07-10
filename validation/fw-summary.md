# FW validation summary

Generado: 2026-07-10T12:55:26
Fuente: `/home/rutrus/snd_repair/validation/fw-matrix.csv`

## Boots analizados: **62**

### Éxito global FW (ambos UIDs OK)

- **34/62** (54.8%)

### UID `:8` (tas2783-1 / Left)

- `OK`: 34
- `WARN`: 28

### UID `:b` (tas2783-2 / Right)

- `OK`: 62

### Regresión capture (Problema A)

- `REGRESSION_CAPTURE=YES`: **0/62**

### Audio L+R (entradas con --audio)

- Ambos canales OK: **1/1** (100.0%)

### Por contexto (`suspend_resume`)

- **boot**: 23/24 OK global
- **suspend_resume**: 11/38 OK global

### Por frecuencia (`rate`)

- **48000 Hz**: 34/62 OK global

### Kernels

- `7.0.0-27-generic`: 62 boots

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
| 16 | 2026-07-09T20:37 | OK | OK |  |  | suspend_resume | 48000 | NO | false-positive-no-suspend |
| 17 | 2026-07-09T21:28 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 18 | 2026-07-09T21:33 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 19 | 2026-07-09T21:39 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 20 | 2026-07-09T21:46 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 21 | 2026-07-09T22:22 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 22 | 2026-07-09T22:30 | OK | OK |  |  | boot | 48000 | NO | auto@boot post-collapse-recovery |
| 23 | 2026-07-09T22:42 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 24 | 2026-07-09T22:43 | WARN | OK |  |  | suspend_resume | 48000 | NO | suspend-2240-cable-icon |
| 25 | 2026-07-09T23:07 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 26 | 2026-07-09T23:10 | WARN | OK |  |  | suspend_resume | 48000 | NO | phase5-loop-1 |
| 27 | 2026-07-09T23:12 | WARN | OK |  |  | suspend_resume | 48000 | NO | phase5-loop-2 |
| 28 | 2026-07-09T23:14 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 29 | 2026-07-09T23:29 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 30 | 2026-07-09T23:30 | OK | OK |  |  | suspend_resume | 48000 | NO | phase5-post-0002 |
| 31 | 2026-07-09T23:32 | OK | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 32 | 2026-07-09T23:36 | OK | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 33 | 2026-07-09T23:38 | OK | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 34 | 2026-07-09T23:40 | OK | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 35 | 2026-07-09T23:44 | OK | OK |  |  | suspend_resume | 48000 | NO | phase5-post-0002-N |
| 36 | 2026-07-09T23:45 | OK | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 37 | 2026-07-09T23:46 | OK | OK |  |  | suspend_resume | 48000 | NO | phase5-confirm-0002 |
| 38 | 2026-07-09T23:47 | OK | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 39 | 2026-07-10T00:08 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 40 | 2026-07-10T00:15 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 41 | 2026-07-10T00:21 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 42 | 2026-07-10T00:38 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 43 | 2026-07-10T00:45 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 44 | 2026-07-10T00:53 | OK | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 45 | 2026-07-10T01:05 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 46 | 2026-07-10T01:09 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 47 | 2026-07-10T01:52 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 48 | 2026-07-10T01:56 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 49 | 2026-07-10T02:11 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 50 | 2026-07-10T02:15 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 51 | 2026-07-10T02:30 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 52 | 2026-07-10T02:34 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 53 | 2026-07-10T02:37 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 54 | 2026-07-10T02:58 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 55 | 2026-07-10T03:02 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 56 | 2026-07-10T03:43 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 57 | 2026-07-10T03:47 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 58 | 2026-07-10T03:49 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 59 | 2026-07-10T03:53 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 60 | 2026-07-10T12:36 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 61 | 2026-07-10T12:51 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 62 | 2026-07-10T12:55 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |

## Criterio RFC Serie B (objetivo)

- 20–30 boots, 0× `FAIL110` en `:b`
- Suspend/resume ≥6/6 OK
- Rates 44100 / 48000 / 96000 sin regresión
- `regression_capture=NO` en todos los boots

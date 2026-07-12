# FW validation summary

Generado: 2026-07-12T10:35:05
Fuente: `/home/rutrus/snd_repair/validation/fw-matrix.csv`

## Boots analizados: **126**

### Éxito global FW (ambos UIDs OK)

- **63/126** (50.0%)

### UID `:8` (tas2783-1 / Left)

- `OK`: 63
- `WARN`: 63

### UID `:b` (tas2783-2 / Right)

- `OK`: 126

### Regresión capture (Problema A)

- `REGRESSION_CAPTURE=YES`: **0/126**

### Audio L+R (entradas con --audio)

- Ambos canales OK: **1/1** (100.0%)

### Por contexto (`suspend_resume`)

- **boot**: 52/53 OK global
- **suspend_resume**: 11/73 OK global

### Por frecuencia (`rate`)

- **48000 Hz**: 63/126 OK global

### Kernels

- `7.0.0-27-generic`: 126 boots

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
| 63 | 2026-07-10T12:59 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 64 | 2026-07-10T13:03 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 65 | 2026-07-10T13:13 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 66 | 2026-07-10T13:25 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 67 | 2026-07-10T13:43 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 68 | 2026-07-10T14:00 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 69 | 2026-07-10T14:08 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 70 | 2026-07-10T15:20 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 71 | 2026-07-10T15:24 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 72 | 2026-07-10T15:30 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 73 | 2026-07-10T15:55 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 74 | 2026-07-10T16:08 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 75 | 2026-07-10T16:12 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 76 | 2026-07-10T16:13 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 77 | 2026-07-10T18:27 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 78 | 2026-07-10T18:44 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 79 | 2026-07-10T19:03 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 80 | 2026-07-10T19:34 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 81 | 2026-07-10T19:44 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 82 | 2026-07-10T19:46 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 82 | 2026-07-10T19:46 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 83 | 2026-07-10T19:51 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 84 | 2026-07-10T20:37 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 85 | 2026-07-10T20:40 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 86 | 2026-07-10T21:47 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 87 | 2026-07-10T22:55 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 88 | 2026-07-11T00:12 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 89 | 2026-07-11T00:15 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 90 | 2026-07-11T00:22 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 91 | 2026-07-11T00:29 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 92 | 2026-07-11T00:51 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 93 | 2026-07-11T00:56 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 94 | 2026-07-11T01:20 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 95 | 2026-07-11T01:23 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 96 | 2026-07-11T01:42 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 97 | 2026-07-11T01:45 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 98 | 2026-07-11T02:16 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 99 | 2026-07-11T02:21 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 100 | 2026-07-11T02:53 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 101 | 2026-07-11T03:06 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 102 | 2026-07-11T03:09 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 103 | 2026-07-11T10:59 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 104 | 2026-07-11T11:04 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 105 | 2026-07-11T13:50 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 106 | 2026-07-11T17:09 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 107 | 2026-07-11T17:11 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 108 | 2026-07-11T17:20 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 109 | 2026-07-11T18:02 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 110 | 2026-07-11T18:04 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 111 | 2026-07-11T18:17 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 112 | 2026-07-11T18:20 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 113 | 2026-07-11T18:31 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 114 | 2026-07-11T18:33 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 115 | 2026-07-11T19:08 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 116 | 2026-07-11T19:11 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 117 | 2026-07-11T19:14 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 118 | 2026-07-12T01:57 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 119 | 2026-07-12T02:07 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 120 | 2026-07-12T09:40 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 121 | 2026-07-12T10:00 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 122 | 2026-07-12T10:23 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 123 | 2026-07-12T10:26 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |
| 124 | 2026-07-12T10:29 | OK | OK |  |  | boot | 48000 | NO | auto@boot |
| 125 | 2026-07-12T10:35 | WARN | OK |  |  | suspend_resume | 48000 | NO | auto@suspend |

## Criterio RFC Serie B (objetivo)

- 20–30 boots, 0× `FAIL110` en `:b`
- Suspend/resume ≥6/6 OK
- Rates 44100 / 48000 / 96000 sin regresión
- `regression_capture=NO` en todos los boots

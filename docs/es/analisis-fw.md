# Análisis matriz FW — 2026-07-09

> [English](../fw-analysis.md) | **Español**

## Boots únicos (6 reinicios reales)

| Boot | boot_id (8 chars) | :8 Left | :b Right | Audio |
|------|-------------------|---------|----------|-------|
| 1 | 8ecd0bbc | WARN | **FAIL(fw)** | solo-L |
| 2 | 8bc7932c | WARN | OK | solo-L |
| 3 | 28347f62 | WARN | OK | solo-L |
| 4 | 79e6d74b | WARN | **FAIL(fw)** | solo-L |
| 5 | 8e8f7349 | WARN | **FAIL(fw)** | solo-L |
| 6 | 8681aafb | WARN | OK | solo-L |

## Demostrado por la matriz

1. **`:8` nunca registra `FW download failed`** en ningún boot.
2. **`:b` falla FW de forma intermitente** — 3/6 boots con `-110` (~50%).
3. **`:8` siempre `WARN(no-fw-hw_params)`** — PipeWire llama `hw_params` antes de que termine la descarga async.
4. **Audio siempre solo-L** incluso cuando `:b` = OK → el canal derecho no depende solo del éxito de FW en probe; también falla `hw_params` temprano o el stream no enlaza `tas2783-2`.

## Compatible con (no demostrado aún)

- Contención temporal en `sdw_nwrite_no_pm` al descargar FW en paralelo (solo pierde `:b`, no alterna `:8`/`:b`).
- Race PipeWire vs `request_firmware_nowait` en `:8` (WARN sin FAIL de nwrite).

## No compatible con

- Fallo determinista siempre en el mismo UID en nwrite (`:8` nunca falla).
- Bug profundo de `soundwire-amd` o transporte SDW.

## Parches aplicados (0006 + 0007)

| Parche | Efecto |
|--------|--------|
| **0006** | Retry ×5, 10 ms, en `-ETIMEDOUT`/`-EAGAIN` durante FW download |
| **0007** | `hw_params` espera a `fw_dl_task_done` antes de rechazar playback |

## Verificación post-reboot

```bash
~/snd_repair/scripts/collect-tas2783-fw.sh >> ~/tas2783-fw-matrix.log
speaker-test -D plughw:1,2 -c 2 -t wav -l 1
echo "  AUDIO: solo-L | L+R" >> ~/tas2783-fw-matrix.log
```

## Boot 7 — primer boot con FW OK en ambos

| `:8` | `:b` | Audio |
|------|------|-------|
| OK | OK | solo-L (aún) |

**Conclusión:** 0006+0007 resuelven FW; el bloqueante restante era routing ASoC (Problema C). Ver [`REVISION-TECNICA.md`](REVISION-TECNICA.md).


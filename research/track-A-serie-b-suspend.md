# Track A — Serie B: FW `:8` tras suspend/resume

> **Absorbed into unified model** (2026-07-12): [UNIFIED-CAUSAL-MODEL.md](UNIFIED-CAUSAL-MODEL.md)  
> Track A logs (`:8 done=0`, `playback without fw download`) = **same chain**, earlier altitude.  
> **Active P0:** [track-PCM-smartamp-hwparams.md](track-PCM-smartamp-hwparams.md) (Q1: rejecting callback).

**Prioridad histórica:** P0 · **Estado:** absorbed — no fork new work here  
**Última evidencia:** boot #14 (2026-07-09 20:05)

---

## Síntoma

- `wpctl` → **Dummy Output** (sin Speaker)
- Kernel: `playback without fw download (uid=0x8 done=0)`
- Tras **cold boot** suele recuperar; tras **s2idle resume** falla sistemáticamente

## Métricas (matriz `validation/fw-matrix.csv`)

| Contexto | FW global OK |
|----------|--------------|
| `boot` | 6/7 (86%) |
| `suspend_resume` | **0/7 (0%)** |

UID `:b` (derecho): **14/14 OK** — fallo **asimétrico** en `:8` (izquierdo / `1714-1-8.bin`).

---

## Secuencia causal (reproducida)

```
1. PM: suspend exit
2. slave-tas2783 :8/:b → failed to resume: error -110
3. px13-audio-resume → PCI unbind/bind OK, tarjeta presente
4. speaker-test / PipeWire → fw download wait timeout
5. :8 done=0 hasta reboot
```

**Conclusión:** el reset PCI userspace **no equivale** a cold boot para la descarga FW de `:8`.

---

## Hipótesis (orden de probabilidad)

| # | Hipótesis | Prueba |
|---|-----------|--------|
| H1 | PM resume SDW deja `:8` roto antes del PCI reset | Timestamp `PM -110` vs primer `unbind` en journal |
| H2 | `fw_dl_task` async no arranca/termina tras warm probe | Trazas `fw_dl_start`/`done` (prod, sin ENZOPLAY ruido) |
| H3 | Carrera PipeWire `hw_params` antes de FW (agrava, no causa raíz) | Track D: PW parado → sigue `done=0` (visto 20:05) |
| H4 | `:8` más sensible que `:b` al timeout bus | Comparar jiffies overlap descargas (Serie B RFC) |

---

## Plan de investigación

### Fase 1 — Baseline reproducible

- [ ] Cold boot → `./scripts/fw-validation-run.sh boot --notes "track-A-baseline"`
- [ ] Un suspend → `./scripts/fw-validation-run.sh suspend --notes "track-A-suspend-1"`
- [ ] Archivar: `research/snapshots/` vía `investigation-snapshot.sh`

### Fase 2 — Kernel producción

```bash
cd ~/snd_repair
./scripts/build-from-upstream.sh    # sin ENZOPLAY
sudo ./scripts/install-tas2783-ko.sh
sudo reboot
```

- [ ] Repetir Fase 1 con `notes=track-A-prod-modules`
- [ ] Comparar boot-logs: ¿sigue `PM -110` en resume?

### Fase 3 — Parches Serie B

- Módulos con `0006` (retry) + `0007` (wait hw_params)
- Objetivo RFC: 20–30 filas, **0/7 → 6/7** suspend OK

### Fase 4 — PM / ACPI (si A persiste)

- [ ] `journalctl -k | grep -E 'failed to resume|GPP4'`
- [ ] Correlación con Track ACPI (GPP4 `AE_ALREADY_EXISTS`) — exploratorio

---

## Comandos

```bash
# Estado FW en sesión actual
journalctl -k -b | grep -iE 'playback without fw|failed to resume|FW download failed' | tail -20

# Tras suspend (manual)
./scripts/fw-validation-run.sh suspend --notes "track-A-test-N"
```

---

## Referencias

- `upstream/series-B-firmware/`
- `patches/0006-tas2783-fw-retry-on-timeout.patch`
- `patches/0007-tas2783-hw-params-wait-fw.patch`
- `docs/FW-VALIDATION.md`

---

## Bitácora

| Fecha | Evento |
|-------|--------|
| 2026-07-09 | 7/7 suspend_resume `:8=WARN`; PM `-110` en boot #14 |
| 2026-07-09 | px13 endurecido: 2× PCI + speaker-test → sigue fallando sin reboot |

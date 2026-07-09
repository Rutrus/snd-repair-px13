# Investigation index — PX13 snd_repair

> **Canonical state (EN):** [`../docs/PROJECT-STATE.md`](../docs/PROJECT-STATE.md) · **ES:** [`../docs/es/ESTADO-PROYECTO.md`](../docs/es/ESTADO-PROYECTO.md)  
> **Machine:** ASUS ProArt PX13 HN7306EAC · kernel `7.0.0-27-generic`

**Phase 4:** only **suspend/resume** (`:8` / `-110`) remains. Cold boot stereo, capture A, ch_mask C — resolved.

**Phase 5 (branch `research/suspend-lifecycle`):** kernel **contract** investigation — no retry patches until lifecycle traced. → [`phase-5/INDEX.md`](phase-5/INDEX.md)

Líneas **independientes**. No mezclar evidencia entre tracks salvo correlación explícita en logs.

---

## Mapa de tracks

| Track | Prioridad | Tema | Bloquea audio | Documento |
|-------|-----------|------|---------------|-----------|
| **A** | P0 | FW `:8` + suspend/resume (Serie B) | Sí | [track-A-serie-b-suspend.md](track-A-serie-b-suspend.md) |
| **B** | Closed | Capture `-22` (0004) | No | [track-B-capture-pin4.md](track-B-capture-pin4.md) |
| **C** | P3 | Webcam `/dev/media0` + dma-buf | No | [track-C-webcam-media0.md](track-C-webcam-media0.md) |
| **D** | P3 | PipeWire / px13 / systemd validación | A veces | [track-D-userspace-pipewire.md](track-D-userspace-pipewire.md) |

**Informe consolidado (snapshot):** [FAILURE-REPORT-2026-07-09.md](FAILURE-REPORT-2026-07-09.md)

---

## Relación entre tracks

```
                    ┌─────────────────┐
                    │  WirePlumber    │  ← hilo débil (enumera A y C)
                    └────────┬────────┘
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
         Track A         Track D         Track C
      (kernel FW)    (px13/PipeWire)   (media0 USB)
              │              │
              └──────┬───────┘
                     ▼
              Track B (PIN4 -22)
              solo playback path
```

**Audio Dummy / `:8 done=0` → solo Track A (+ D como agravante).**  
**Webcam → solo Track C** (mismo demonio, distinto hardware).

---

## Estado actual (última sesión)

| Track | Estado investigación | Siguiente paso |
|-------|---------------------|----------------|
| A | **Active P0** — 0/9 real suspend OK | Serie B → `install-tas2783.ko` → 3–5 suspends |
| B | **Closed** — 0004, 0/20 regression | — |
| C | **Causa probable:** usuario fuera de grupo `video` | `sudo usermod -aG video,render rutrus` + verificar |
| D | Mitigaciones en `px13-audio-fix.sh` | Reinstalar + validar tras reboot |

---

## Recolección común

```bash
# Snapshot rápido (guardar en research/snapshots/)
~/snd_repair/scripts/investigation-snapshot.sh

# Matriz FW
~/snd_repair/scripts/fw-validation-run.sh status
```

---

## Criterios de cierre por track

| Track | Cerrado cuando |
|-------|----------------|
| A | ≥6/6 suspend_resume `:8=OK` en matriz con módulos upstream |
| B | `capture_dailink_warn=NO` o -22 < umbral acordado |
| C | 0× `Permiso denegado` en media0; libcamera estable en wpctl |
| D | px13-resume <30s; 0× PW SIGKILL; validación suspend en CSV |

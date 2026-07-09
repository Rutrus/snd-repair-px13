# Índice de investigación — PX13 snd_repair

> **Estado:** activo desde 2026-07-09  
> **Máquina:** ASUS ProArt PX13 HN7306EAC · kernel `7.0.0-27-generic`

Líneas **independientes**. No mezclar evidencia entre tracks salvo correlación explícita en logs.

---

## Mapa de tracks

| Track | Prioridad | Tema | Bloquea audio | Documento |
|-------|-----------|------|---------------|-----------|
| **A** | P0 | FW `:8` + suspend/resume (Serie B) | Sí | [track-A-serie-b-suspend.md](track-A-serie-b-suspend.md) |
| **B** | P2 | Capture `SDW1-PIN4` prepare `-22` | No | [track-B-capture-pin4.md](track-B-capture-pin4.md) |
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
| A | Evidencia sólida (0/7 resume OK) | Módulos prod + trazas ENZOFW; reboot → 1 suspend de prueba |
| B | Documentado, no bloqueante | Revisar UCM `tas2783.conf` capture |
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

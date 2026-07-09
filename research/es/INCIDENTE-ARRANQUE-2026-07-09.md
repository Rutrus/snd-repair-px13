# Incidente de arranque — 2026-07-09 22:27

> [English](../BOOT-INCIDENT-2026-07-09.md)

Entre matriz **#21** (22:22 OK) y **#22** (22:30 OK) hubo un **arranque colgado** sin fila en la matriz.

## Causa

`px13-audio-rebind` hizo **unbind PCI** demasiado pronto → soft lockup (~2,5 min) → segundo reboot.

## Cambios

- Sin `speaker-test` al arrancar (`PX13_SKIP_SPEAKER_TEST=1`)
- Sin reset PCI en cold boot (`PX13_SKIP_PCI_ON_BOOT=1`); resume sigue con PCI
- Ciclo systemd de `snd-repair-fw-validation` corregido

```bash
sudo ~/snd_repair/scripts/install-px13-audio-fix.sh
```

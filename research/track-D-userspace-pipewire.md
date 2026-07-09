# Track D — Userspace: PipeWire, px13-audio-fix, validación

**Prioridad:** P3 (P1 si agrava Track A)  
**Bloquea altavoces:** indirectamente (carreras, sesión sin audio)  
**Relación con Track A:** **agrava** bucle `hw_params`; **no sustituye** fix kernel

---

## Problemas documentados

| ID | Síntoma | Estado |
|----|---------|--------|
| D1 | WirePlumber `stop-sigterm` 90s → SIGKILL | Mitigado: stop sockets + mask |
| D2 | `pipewire.socket` reactiva daemon durante reset PCI | Mitigado en `px13-audio-fix.sh` |
| D3 | `px13-audio-resume` exit 1 deja PW parado | Mitigado: restore PW en fallo |
| D4 | Dos instancias concurrentes de px13-fix | Mitigado: `flock` |
| D5 | `snd-repair-fw-validation` ordering cycle | Pendiente |
| D6 | ExecStartPost no corre si servicio falla | Mitigado: hook desde script + `SuccessExitStatus=1` |

---

## Incidentes

### D1 — Timeout WirePlumber (19:28–19:29)

```
px13-audio-fix: restarting pipewire for uid 1000
… 90s …
wireplumber.service: stop-sigterm timed out → SIGKILL
```

### D2 — Socket reactiva (19:52)

PCI reset con PW “parado” pero socket activo → `hw_params` a los 2s.

### D3 — Sesión sin PipeWire (20:05)

Script nuevo sale exit 1 sin arrancar PW → `Could not connect to PipeWire`.

---

## Artefactos en repo

| Archivo | Rol |
|---------|-----|
| `scripts/px13-audio-fix.sh` | Fork endurecido brainchillz |
| `scripts/install-px13-audio-fix.sh` | Instalación en `/usr/local/sbin` |
| `scripts/px13-restore-pipewire.sh` | Recuperación manual PW |
| `systemd/px13-audio-resume.service.d-snd-repair-fw-validation.conf` | Validación post-resume |

---

## Plan de investigación

### Paso D1 — Reinstalar stack endurecido

```bash
sudo ~/snd_repair/scripts/install-px13-audio-fix.sh
sudo ~/snd_repair/scripts/install-fw-validation-service.sh --suspend-only
sudo systemctl daemon-reload
```

### Paso D2 — Prueba post-reboot

1. Boot → Speaker OK
2. Suspend 30s → resume
3. Medir:
   - `systemctl status px13-audio-resume`
   - `journalctl -b | grep px13-audio-fix`
   - `tail -1 validation/fw-matrix.csv`

### Paso D3 — Fix ordering cycle (D5)

- [ ] Cambiar unidad system `snd-repair-fw-validation.service` → `After=sound.target`, sin `graphical.target`
- [ ] O desinstalar unidad system y usar solo user + linger

### Paso D4 — Métricas objetivo

| Métrica | Objetivo |
|---------|----------|
| Duración `px13-audio-resume` | < 60s |
| SIGKILL wireplumber | 0 |
| Fila `auto@suspend` en CSV | 100% tras resume |

---

## Separación de Track A

Incluso con D perfecto, si kernel deja `:8 done=0`, el resultado es Dummy hasta reboot.  
Track D reduce **daño colateral** y mejora diagnóstico; Track A resuelve la causa.

---

## Bitácora

| Fecha | Evento |
|-------|--------|
| 2026-07-09 | Script endurecido instalado; resume 20:05 aún FAIL FW |
| 2026-07-09 | Validación suspend boot #14 manual (`resume-20:05-fail`) |

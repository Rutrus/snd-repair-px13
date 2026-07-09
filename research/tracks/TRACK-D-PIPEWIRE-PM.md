# TRACK D — PipeWire / WirePlumber / px13-audio-fix

**Prioridad:** P1  
**Rol:** agravante de Track A; mitigación userspace  
**No sustituye** fix kernel Serie B

---

## Incidentes documentados

| Fecha/hora | Evento |
|------------|--------|
| 19:28–19:29 | `restarting pipewire` → WirePlumber `stop-sigterm timed out` → SIGKILL (~90s) |
| 19:52 | `pipewire.socket` reactiva daemon durante espera FW del script |
| 20:05 | `px13-audio-resume` exit 1 → PipeWire parado (`Could not connect`) |
| 17:26 | PCI `unbind failed/timed out` → soft lockup multi-CPU (script brainchillz original) |

---

## Mecanismo

1. Tras resume, FW `:8` aún no listo (`done=0`).
2. PipeWire/WirePlumber abren `plughw:1,2` → bucle `hw_params` cada ~3s.
3. Eso impide recuperación incluso si PCI reset podría funcionar en otro timing.

---

## Mitigaciones en repo (2026-07-09)

| Cambio | Archivo |
|--------|---------|
| Stop sockets + mask runtime | `scripts/px13-audio-fix.sh` |
| No bind si unbind timeout | idem |
| flock anti-instancias paralelas | idem |
| Restaurar PW si FW falla | idem |
| Restore manual | `scripts/px13-restore-pipewire.sh` |
| Instalador | `scripts/install-px13-audio-fix.sh` |

---

## Investigación pendiente

- [ ] Medir duración total `px13-audio-resume` (objetivo <30s)
- [ ] ¿Evitar restart PipeWire si FW OK y udev ya notificó card?
- [ ] Política GNOME: ¿retener stream suspend vs cerrar?
- [ ] Reproducir soft lockup (Track D + L3) con script **sin** mitigación — solo en VM/lab
- [ ] `SuccessExitStatus=1` en drop-in validación — verificar en systemd instalado

---

## Reproducción / recuperación

```bash
# Tras script fallido
~/snd_repair/scripts/px13-restore-pipewire.sh

# Reinstalar script endurecido
sudo ~/snd_repair/scripts/install-px13-audio-fix.sh
sudo systemctl daemon-reload
```

---

## Criterio de cierre

- Tras resume **con FW OK** (Track A resuelto): Speaker en <15s sin SIGKILL
- Tras resume **con FW roto**: sesión mantiene PipeWire (Dummy OK), mensaje claro “reboot required”
- 0× soft lockup en 10 suspend con script nuevo

---

## Referencias

- brainchillz base: `/usr/local/sbin/px13-audio-fix.sh.brainchillz.bak`
- Docs: [`../../docs/FW-VALIDATION.md`](../../docs/FW-VALIDATION.md) § Resume freeze

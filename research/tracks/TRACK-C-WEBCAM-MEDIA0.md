# TRACK C — Webcam: `/dev/media0`, libcamera, dma-buf

**Prioridad:** P3  
**Línea independiente** — no incluir en RFC Serie B audio  
**Relacionado con:** WirePlumber (daemon común); hardware USB `c4:00.4`, **no** ACP `c4:00.5`

---

## Síntomas observados

```text
wireplumber: Failed to open media device at /dev/media0: Permiso denegado
wireplumber: Unable to populate media device /dev/media0, skipping
wireplumber: Could not open any dma-buf provider
wireplumber: Failed to add device for '.../usb1/1-1/.../media0', skipping
```

**Lo que SÍ funciona:**

- `uvcvideo` carga
- PipeWire **Video** → `ASUS FHD webcam (V4L2)` visible en `wpctl status`
- Preview V4L2 usable en apps que no dependen de libcamera pipeline

---

## Hardware / ruta

| Componente | Ruta |
|------------|------|
| USB webcam | `0000:c4:00.4` → `usb1/1-1` |
| Nodo media | `/dev/media0` |
| Driver | `uvcvideo` |
| Audio ACP (referencia) | `0000:c4:00.5` — **distinto** |

---

## Diagnóstico diferencial

| Pregunta | Audio suspend | Webcam |
|----------|---------------|--------|
| Error principal | `-110`, `done=0` | `EACCES` permiso |
| Cuándo | Tras resume | Post-arranque WirePlumber |
| Fix conocido | Reboot | udev / grupos / policy |

**Conclusión:** misma máquina, **distinto subsistema**. Solo investigar en paralelo si tras arreglar permisos cambia Track A (hipótesis no sostenida hoy).

---

## Investigación pendiente

- [ ] `ls -la /dev/media0` — owner/group/mode
- [ ] `groups` — ¿usuario en `video`, `render`?
- [ ] Reglas udev: `/usr/lib/udev/rules.d/*media*`
- [ ] ¿WirePlumber necesita libcamera o basta V4L2? (política `.conf`)
- [ ] Probar tras suspend: ¿media0 persiste con mismo error de permiso?
- [ ] `dmesg | grep uvcvideo` — errores USB aparte de permiso userspace

---

## Reproducción

```bash
journalctl -b | grep -iE 'media0|dma-buf|uvcvideo'
wpctl status   # sección Video
ls -la /dev/media* /dev/video*
groups "$USER"
```

---

## Criterio de cierre

- WirePlumber abre `/dev/media0` sin error **o**
- Documentar que PX13 usa solo V4L2 y desactivar ruta libcamera en config WP
- dma-buf: resolver si se requiere zero-copy (apps concretas)

---

## Referencias

- Informe: [`../FAILURE-REPORT-2026-07-09.md`](../FAILURE-REPORT-2026-07-09.md) § L5
- Backlog: [`../INVESTIGATION-BACKLOG.md`](../INVESTIGATION-BACKLOG.md)

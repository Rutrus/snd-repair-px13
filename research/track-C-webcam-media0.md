# Track C — Webcam `/dev/media0` y dma-buf

**Prioridad:** P3 · **Bloquea altavoces:** no  
**Estado:** investigación iniciada — **causa probable identificada**  
**Relación con Track A:** **ninguna** (hardware USB `c4:00.4` vs ACP `c4:00.5`)

---

## Síntoma

```
wireplumber: Failed to open media device at /dev/media0: Permiso denegado
wireplumber: Could not open any dma-buf provider
```

**Cuándo:** arranque de WirePlumber (~2–3 min post-boot), no tras suspend.

**Qué sí funciona:** nodos V4L2 en PipeWire (`wpctl` → `ASUS FHD webcam (V4L2)`).  
**Qué falla:** ruta **libcamera** / media controller graph.

---

## Evidencia (2026-07-09)

| Recurso | Permisos | Usuario `rutrus` |
|---------|----------|------------------|
| `/dev/media0` | `crw-rw----+ root:video` | ACL `user:rutrus:rw-` (logind) |
| `/dev/video0-3` | `root:video` | ACL presente |
| `/dev/dri/renderD128` | `root:render` | **sin** grupo `render` |
| Grupos `rutrus` | — | **no** está en `video` ni `render` |

**Instancia con error:** `wireplumber[6593]` a las 19:59:55 (tras reinicio PW por px13).  
**Instancia posterior:** `wireplumber[17295]` a las 20:12 — libcamera arranca sin ERROR en grep.

**Hipótesis:** carrera en arranque (ACL logind aún no aplicada) **o** falta de grupo `video`/`render` en procesos hijo libcamera.

---

## Hardware (referencia)

```
DEVPATH=.../0000:c4:00.4/usb1/1-1/1-1:1.0/media0
ID_PATH=pci-0000:c4:00.4-usb-0:1:1.0
Driver: uvcvideo
```

Mismo dominio PCI AMD `c4:00.x` que audio, **función distinta** — no implica fallo SoundWire.

---

## Plan de resolución

### Paso C1 — Grupos (recomendado)

```bash
sudo usermod -aG video,render rutrus
# Cerrar sesión y volver a entrar (o reboot)
groups   # debe listar video render
```

### Paso C2 — Verificación

```bash
# Tras login
test -r /dev/media0 && echo "media0 OK" || echo "media0 FAIL"
test -r /dev/dri/renderD128 && echo "render OK" || echo "render FAIL"
journalctl -b --user -u wireplumber | grep -iE 'media0|dma-buf|ERROR'
wpctl status | grep -i webcam
```

### Paso C3 — Si persiste

- [ ] Regla udev `TAG+="uaccess"` en `70-camera.rules` para ASUS VID/PID
- [ ] Desactivar nodo libcamera en WirePlumber si solo se necesita V4L2
- [ ] `pipewire-pulse` / `wireplumber` version pin

---

## Criterio de cierre

- 0× `Permiso denegado` en `/dev/media0` tras login limpio
- 0× `Could not open any dma-buf provider` en boot
- libcamera + V4L2 visibles en `wpctl` de forma estable

---

## No hacer

- No incluir en RFC Serie B ni en parches `tas2783`
- No asumir correlación con `:8 done=0` sin prueba A/B (reboot → fix C → suspend → medir FW)

---

## Bitácora

| Fecha | Hallazgo |
|-------|----------|
| 2026-07-09 | Error 19:59:55; usuario sin grupo `video`/`render` |
| 2026-07-09 | wpctl muestra libcamera + V4L2 en sesión actual (parcial/intermitente) |

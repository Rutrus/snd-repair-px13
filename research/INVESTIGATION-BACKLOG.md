# Backlog de investigación — PX13 snd_repair

> **Español** | [English](INVESTIGATION-BACKLOG.en.md)  
> **Snapshot cuantitativo:** [`FAILURE-REPORT-2026-07-09.md`](FAILURE-REPORT-2026-07-09.md)  
> **Matriz viva:** [`../validation/fw-matrix.csv`](../validation/fw-matrix.csv)

Documento para retomar la investigación sin depender del chat. Cada pista tiene hipótesis, reproducción, criterio de cierre y enlaces al repo.

**Última actualización:** 2026-07-09  
**Kernel de referencia:** `7.0.0-27-generic`  
**Nota metodológica:** muchas pruebas usaron módulos **laboratorio** (ENZOPLAY/ENZODBG). Antes de RFC upstream, repetir hitos con [`../scripts/build-from-upstream.sh`](../scripts/build-from-upstream.sh).

---

## Mapa de relaciones

```
                    ┌─────────────────────────────────────┐
                    │  ASUS ProArt PX13 (HN7306EAC)       │
                    └─────────────────────────────────────┘
                                      │
          ┌───────────────────────────┼───────────────────────────┐
          │                           │                           │
    PCI c4:00.5                   PCI c4:00.4                  ACPI
    ACP / SoundWire               USB (webcam)                  GPP4
          │                           │                           │
    ┌─────▼─────┐               ┌─────▼─────┐               ┌─────▼─────┐
    │ TRACK A   │               │ TRACK C   │               │ TRACK F   │
    │ FW :8     │  NO ligado    │ media0    │  débil        │ AE_ALREADY│
    │ suspend   │◄─────────────►│ webcam    │  solo SoC     │ _EXISTS   │
    └─────┬─────┘               └───────────┘               └───────────┘
          │
    ┌─────▼─────┐     ┌─────────────┐     ┌─────────────┐
    │ TRACK B   │     │ TRACK D     │     │ TRACK E     │
    │ PIN4 -22  │     │ PipeWire    │     │ systemd     │
    │ capture   │     │ px13 script │     │ validación  │
    └───────────┘     └─────────────┘     └─────────────┘
                              │
                    WirePlumber (común userspace)
```

**Regla:** Track A es el bloqueador de altavoces tras suspend. Tracks C, E, F son **líneas nuevas** salvo correlación demostrada en logs.

---

## Estado global (2026-07-09)

| Track | Tema | ¿Relacionado con audio suspend? | Prioridad | Estado |
|-------|------|-----------------------------------|-----------|--------|
| **A** | FW TAS2783 `:8` + PM `-110` en resume | — (núcleo) | P0 | Abierto |
| **B** | Capture dailink PIN4 `-22` | Parcial (mismo card ALSA) | P2 | Abierto |
| **C** | Webcam `/dev/media0` + dma-buf | **No** | P3 | Abierto |
| **D** | PipeWire / px13-audio-fix | Agrava A; no causa raíz | P1 | Mitigado parcial |
| **E** | Automatización systemd | No | P3 | Abierto |
| **F** | ACPI GPP4 duplicado | Especulativo | P4 | Exploratorio |

---

## TRACK A — Suspend/resume: FW `:8` (`done=0`)

**Ficha:** [`tracks/TRACK-A-SUSPEND-FW.md`](tracks/TRACK-A-SUSPEND-FW.md)

**Síntoma:** tras s2idle, altavoz izquierdo muerto → PipeWire **Dummy Output**; dmesg:

```text
slave-tas2783 …:8: PM: failed to resume: error -110
slave-tas2783 …:8: error playback without fw download (uid=0x8 done=0)
```

**Datos:** matriz `0/7` suspend_resume con FW global OK; `:b` **14/14 OK** (asimetría izquierda).

**Parches candidatos:** `0006`, `0007` → [`../upstream/series-B-firmware/`](../upstream/series-B-firmware/)

---

## TRACK B — Capture dailink `SDW1-PIN4` prepare `-22`

**Ficha:** [`tracks/TRACK-B-CAPTURE-DAILINK.md`](tracks/TRACK-B-CAPTURE-DAILINK.md)

**Síntoma:** WirePlumber/UCM enumeran capture en amps solo-playback; ~80–120 líneas/boot.

**Impacto:** playback estéreo validado OK (boot #1); `regression_capture=NO` en matriz.

**Parches:** `0004` aplicado; posible UCM brainchillz.

---

## TRACK C — Webcam: `media0` / libcamera (línea independiente)

**Ficha:** [`tracks/TRACK-C-WEBCAM-MEDIA0.md`](tracks/TRACK-C-WEBCAM-MEDIA0.md)

**Síntoma:** WirePlumber no abre `/dev/media0`; dma-buf falla; **V4L2 sí funciona**.

**Conclusión:** no mezclar con Serie B salvo nueva evidencia.

---

## TRACK D — Userspace: PipeWire y `px13-audio-fix`

**Ficha:** [`tracks/TRACK-D-PIPEWIRE-PM.md`](tracks/TRACK-D-PIPEWIRE-PM.md)

**Incidentes:** WirePlumber SIGKILL ~90s; `pipewire.socket` reactiva durante reset PCI; sesión sin PW si script falla.

**Mitigaciones en repo:** [`../scripts/px13-audio-fix.sh`](../scripts/px13-audio-fix.sh), [`../scripts/px13-restore-pipewire.sh`](../scripts/px13-restore-pipewire.sh)

---

## TRACK E — Infra: validación automática systemd

**Ficha:** [`tracks/TRACK-E-SYSTEMD-VALIDATION.md`](tracks/TRACK-E-SYSTEMD-VALIDATION.md)

**Síntoma:** ordering cycle con `graphical.target`; `ExecStartPost` no corre si unidad falla (corregido parcialmente en script).

---

## TRACK F — ACPI `GPP4 AE_ALREADY_EXISTS`

**Ficha:** [`tracks/TRACK-F-ACPI-GPP4.md`](tracks/TRACK-F-ACPI-GPP4.md)

**Síntoma:** cada cold boot, objetos `_S0W/_PR0/_PR3` duplicados en `\_SB.PCI0.GPP4`.

**Prioridad baja** hasta correlacionar con Track A.

---

## Comandos rápidos al retomar

```bash
# Estado matriz
./scripts/fw-validation-run.sh status

# Tras suspend
./scripts/fw-validation-run.sh suspend --notes "retest-YYYY-MM-DD"

# Audio
wpctl status | grep -E 'Speaker|Dummy'
journalctl -k -b | grep -iE 'playback without fw|failed to resume.*-110'

# Webcam (Track C)
journalctl -b | grep -iE 'media0|dma-buf|uvcvideo'
ls -la /dev/media* ; groups

# Capture PIN4 (Track B)
grep -c 'SDW1-PIN4-CAPTURE.*prepare ret=-22' validation/boot-logs/boot-*.log
```

---

## Criterio RFC Serie B (pendiente)

Ver [`../upstream/series-B-firmware/VALIDATION-TODO.md`](../upstream/series-B-firmware/VALIDATION-TODO.md):

- [ ] 20–30 filas en matriz (14 hoy)
- [ ] Suspend/resume ≥6/6 OK global
- [ ] Rates 44100 / 48000 / 96000
- [ ] Módulos producción (sin ENZO)
- [ ] 0× `FAIL110` en `:b` (cumplido)

---

## Historial de documentos

| Fecha | Documento | Contenido |
|-------|-----------|-----------|
| 2026-07-09 | `FAILURE-REPORT-2026-07-09.md` | Informe cuantitativo sesión |
| 2026-07-09 | `INVESTIGATION-BACKLOG.md` | Este backlog + fichas por track |

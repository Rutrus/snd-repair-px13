# Informe de fallos — ASUS ProArt PX13 (snd_repair)

**Fecha:** 2026-07-09  
**Máquina:** ProArt PX13 HN7306EAC  
**Kernel:** `7.0.0-27-generic` (módulos laboratorio: ENZOPLAY/ENZODBG)  
**Fuente:** `validation/fw-matrix.csv` (14 entradas), `validation/boot-logs/`, `journalctl`

---

## Resumen ejecutivo

| Área | Severidad | Frecuencia | ¿Bloquea altavoces? |
|------|-----------|------------|---------------------|
| **B — FW `:8` tras suspend** | Crítica | 7/7 resume fallan `:8` | Sí (Dummy Output) |
| **B′ — PM resume `-110`** | Alta | Cada resume problemático | Sí (precursor de B) |
| **A′ — Capture dailink `-22`** | Media | 13/14 boots (ruido) | No (playback OK) |
| **U1 — PipeWire resume race** | Alta | Resume con script viejo | Sí (agrava B) |
| **U2 — PCI unbind lockup** | Crítica | 1 evento (17:26) | Sí (freeze sistema) |
| **V1 — Webcam media0** | Baja | Cada boot | No (V4L2 OK) |
| **S1 — systemd ordering** | Baja | Cada boot | No (matriz incompleta) |
| **ACPI — GPP4 duplicado** | Info | Cada boot | Desconocido |

**Línea principal ya abierta:** Serie B upstream (`0006` + `0007`) — FW async TAS2783 en resume.  
**Este documento:** fallos *colaterales* y vectores de investigación complementarios.

---

## Datos cuantitativos (matriz FW)

```
Boots totales:     14
FW global OK:      6/14 (42.9%)
  boot:            6/7 OK
  suspend_resume:  0/7 OK  ← bloqueador RFC Serie B

UID :8  OK/WARN:   6 / 8
UID :b  OK/WARN:   14 / 0  ← canal derecho estable

REGRESSION_CAPTURE=YES:  0/14  (Serie A no regresa)
capture_dailink_warn:    13/14 (ver L2)
```

### Cronología suspend/resume (todos `:8=WARN`)

| boot | hora | :8 | :b | notas |
|------|------|----|----|-------|
| 3 | 17:16 | WARN | OK | post-suspend sesión larga |
| 4–6 | 17:21–17:25 | WARN | OK | auto/manual suspend |
| 9 | 18:00 | WARN | OK | recovery manual fallida |
| 12 | 19:30 | WARN | OK | PipeWire 90s timeout |
| 14 | 20:09 | WARN | OK | PM `-110` + px13 exit 1 |

---

## L1 — Suspend/resume: FW `:8` con `done=0` (Problema B)

**Síntoma:** `playback without fw download (uid=0x8 done=0)` → Dummy Output.

**Secuencia típica (boot #14, resume 20:05):**
```
PM: suspend exit
  → slave-tas2783 :8/:b  failed to resume: error -110
  → px13-audio-resume: PCI unbind/bind OK
  → speaker-test / PipeWire: fw download wait timeout
  → :8 done=0 permanente hasta cold reboot
```

**Hipótesis:**
1. ACPI/SDW resume deja `:8` en estado inválido antes del reset PCI.
2. Descarga FW async no completa (`fw_dl_task_done=0`) tras warm reset.
3. `:b` tolera el path; `:8` (1714-1-8.bin / tas2783-1) es más frágil.

**Investigación propuesta:**
- [ ] Correlacionar `PM failed -110` con `done=0` (timestamp en `boot-logs`).
- [ ] Probar Serie B upstream **sin** ENZOPLAY (módulos producción).
- [ ] Añadir traza `ENZOFW` solo en prod: `fw_dl_start` / `fw_dl_done` por UID.
- [ ] Probar `s2idle` vs `deep` (si firmware lo permite).
- [ ] Medir si segundo suspend en misma sesión empeora (sesión `a2f361bf` boots 3–6).

**Parches:** `patches/0006`, `0007` → `upstream/series-B-firmware/`

---

## L2 — Capture dailink `SDW1-PIN4-CAPTURE` prepare `-22`

**Síntoma:** `SDW1-PIN4-CAPTURE-SmartAmp: machine prepare ret=-22`  
**Frecuencia:** ~80–120 líneas/boot en 13/14 entradas (`capture_dailink_warn=YES`).  
**Matriz:** `regression_capture=NO` (no cuenta como regresión Serie A).

**Interpretación:** WirePlumber/UCM sigue enumerando un dailink de **capture** en amps TAS2783 solo-playback. El parche 0004 evita el fallo a nivel codec, pero el machine driver aún intenta `prepare` en PIN4.

**Impacto usuario:** Ninguno en playback estéreo validado (boot #1 L/R OK). Ruido en logs y posible latencia en enumeración PipeWire.

**Investigación propuesta:**
- [ ] ¿Desactivar nodo capture en UCM (`tas2783.conf`) vs fix kernel machine?
- [ ] Contar si `-22` correlaciona con tiempo hasta Speaker visible.
- [ ] Comparar con `upstream/series-A-capture` en máquina limpia.

**Parches:** `0004` (aplicado), posible extensión UCM brainchillz.

---

## L3 — PCI unbind timeout → soft lockup (17:26)

**Evento único documentado:**
```
17:26:43  px13-audio-fix: unbind failed/timed out
17:27:10  watchdog: soft lockup CPU#4, #22, #29 …
17:28:21  reboot forzado
```

**Causa:** `echo … > unbind` bloqueado con bus ACP/SoundWire en estado roto; script continuaba con `bind` (brainchillz original).

**Mitigación aplicada:** `scripts/px13-audio-fix.sh` — no hace bind si unbind falla + `flock`.

**Investigación propuesta:**
- [ ] Reproducir con bus analyzer / `sdw`-debug tras resume sin reset previo.
- [ ] Valorar `reset` PCI subsystem vs unbind user-space.
- [ ] Documentar ventana mínima post-resume antes de tocar `0000:c4:00.5`.

---

## L4 — Userspace: PipeWire / WirePlumber en resume

**Incidentes:**

| Hora | Evento |
|------|--------|
| 19:28–19:29 | `restarting pipewire` → WirePlumber `stop-sigterm timed out` → SIGKILL (~90s) |
| 19:52 | `pipewire.socket` reactiva daemon durante espera FW |
| 20:05 | `px13-audio-resume` exit 1 → sesión sin PipeWire |

**Mecanismo:** PipeWire abre `hw_params` antes de FW listo → bucle `playback without fw` cada ~3s.

**Mitigaciones aplicadas:** stop sockets + mask, settle 12s, speaker-test probe, flock, restaurar PW en fallo.

**Investigación propuesta:**
- [ ] Retrasar `WantedBy=suspend.target` vs ordenar **después** de `sound.target` + delay dinámico.
- [ ] ¿WirePlumber udev monitor basta sin restart si PW no murió en suspend?
- [ ] Métrica: tiempo `px13-audio-resume` → primer `hw_params OK` en dmesg.

---

## L5 — Webcam: WirePlumber / libcamera (`/dev/media0`)

**Log (boot #13, 19:59):**
```
wireplumber: Failed to open media device /dev/media0: Permiso denegado
wireplumber: Could not open any dma-buf provider
```

**Estado:** `uvcvideo` + V4L2 en PipeWire **funcionan**; falla ruta libcamera/media graph.

**Investigación propuesta:**
- [ ] Grupos: usuario en `video`, reglas udev `media0`.
- [ ] ¿Relacionado con orden de arranque vs pipewire-pulse?
- [ ] Separar de track audio — issue independiente.

---

## L6 — Automatización: systemd ordering cycle

**Log:**
```
ordering cycle: snd-repair-fw-validation.service → graphical.target → multi-user.target
Job snd-repair-fw-validation.service/start deleted
```

**Impacto:** unidad **system** de validación boot a veces no corre; unidad **user** + linger compensa parcialmente.

**Investigación propuesta:**
- [ ] Cambiar `WantedBy=timers.target` o `After=sound.target` sin depender de `graphical.target`.
- [ ] Registrar en matriz si `auto@boot` faltó (campo `notes`).

---

## L7 — ACPI `AE_ALREADY_EXISTS` (GPP4)

**Cada cold boot:**
```
Failure creating named object [\_SB.PCI0.GPP4._S0W/_PR0/_PR3], AE_ALREADY_EXISTS
```

**Contexto:** GPP4 suele ser puerto PCIe del ACP/audio. Posible duplicación tabla ACPI vs kernel.

**Investigación propuesta:**
- [ ] Correlacionar con `PM failed -110` en resume (misma sesión PCI).
- [ ] `acpidump` + comparar con Windows DSDT.
- [ ] Bajo prioridad salvo vínculo con L1.

---

## L8 — Transitorio boot: `trf on Slave 1 failed:-110`

**Frecuencia:** 2 líneas/boot en arranques con actividad SDW (no en todos los clean boots).

**Ejemplo:** `trf on Slave 1 failed:-110 write addr 8108 count 6904` → segundos después `hw_params OK`.

**Distinción vs L1:** en **cold boot** suele recuperar; en **resume** no.

**Investigación propuesta:**
- [ ] Identificar Slave 1 = `:8` o manager.
- [ ] ¿0006 retry cubre este path en resume?
- [ ] Matriz separada: `trf-110` boot OK vs resume FAIL.

---

## L9 — Metodología: módulos laboratorio vs producción

**Estado actual:** ENZOPLAY/ENZODBG en `snd-soc-tas2783-sdw` (instrumentación).

**Riesgo:** RFC Serie B debe validarse con `scripts/build-from-upstream.sh` (sin ENZO).

**Acción:** bifurcar matriz `notes=lab` vs `notes=prod` antes de enviar upstream.

---

## L10 — Cobertura RFC incompleta

| Criterio Serie B | Estado |
|------------------|--------|
| 20–30 cold boots | 7 boot + 7 resume = 14 filas |
| 0× FAIL110 en `:b` | ✅ 14/14 `:b=OK` |
| Suspend ≥6/6 OK | ❌ 0/7 |
| Rates 44.1 / 48 / 96 kHz | ❌ solo 48 kHz |
| Buffer min/max | ❌ no probado |

---

## Priorización de líneas nuevas

```
P0  L1 + L8   Kernel FW resume (:8)          → Serie B upstream
P1  L4         PipeWire ordering              → px13-audio-fix + WP policy
P1  L3         PCI unbind safety              → mitigado; reproducir 1×
P2  L2         Capture PIN4 -22               → UCM / Serie A extendida
P3  L5         Webcam media0                  → issue separado
P3  L6         Validación systemd             → fix unidad system
P4  L7         ACPI GPP4                      → exploratorio
```

---

## Comandos de recolección para nuevas líneas

```bash
# L2 — capture dailink
grep -c 'SDW1-PIN4-CAPTURE.*prepare ret=-22' validation/boot-logs/boot-NNN.log

# L1/L8 — resume vs boot
journalctl -k -b | grep -E 'failed to resume: error -110|trf on Slave.*-110|done=0'

# L5 — webcam
journalctl -b | grep -iE 'media0|dma-buf|uvcvideo'

# L6 — validación
journalctl -b | grep -iE 'ordering cycle|snd-repair-fw-validation'

# Registrar manualmente tras incidente
./scripts/fw-validation-run.sh suspend --notes "L1-investigation"
```

---

## Referencias en repo

| Tema | Ruta |
|------|------|
| Matriz | `validation/fw-matrix.csv`, `validation/fw-summary.md` |
| Serie B RFC | `upstream/series-B-firmware/VALIDATION-TODO.md` |
| Guía validación | `docs/FW-VALIDATION.md` |
| Freeze resume | `docs/FW-VALIDATION.md` § Resume freeze |
| px13 endurecido | `scripts/px13-audio-fix.sh` |

---

*Generado para abrir issues / ramas de investigación. Actualizar tras cada bloque de 5–10 pruebas.*

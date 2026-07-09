# TRACK A — FW TAS2783 `:8` tras suspend/resume

**Prioridad:** P0  
**Bloquea:** altavoces internos tras lid close / `systemctl suspend`  
**Relacionado con:** Track D (agrava); **no** Track C (webcam)

---

## Síntomas

| Capa | Manifestación |
|------|----------------|
| Kernel | `PM: failed to resume: error -110` en `:8` y a veces `:b` |
| Kernel | `playback without fw download (uid=0x8 done=0)` |
| Kernel | `fw download wait timeout in hw_params` |
| Userspace | PipeWire **Dummy Output** (sin sink Speaker) |
| Recuperación | **Cold reboot** fiable; PCI reset en caliente **no** recupera `:8` |

---

## Evidencia (matriz 2026-07-09)

- **suspend_resume:** 0/7 OK global FW
- **boot:** 6/7 OK global FW
- **`:b`:** 14/14 OK (canal derecho estable)
- **`:8`:** 8 WARN / 6 OK — todos los WARN en sesión post-suspend o boot con historial suspend en mismo `proc_boot_id`

### Secuencia documentada (boot #14, resume 20:05)

1. `PM: suspend exit`
2. `:8/:b` → `resume: initialization timed out` → `-110`
3. `px13-audio-resume` → unbind/bind PCI `0000:c4:00.5` OK
4. `speaker-test` / espera 12s → `:8 done=0`
5. Script exit 1

---

## Hipótesis (orden de probabilidad)

1. **PM SoundWire/ACPI:** el slave `:8` no sale de s2idle; el warm PCI reset no reinicia la descarga FW async.
2. **Asimetría hardware/firmware:** `1714-1-8.bin` (izq) más sensible que `1714-1-B.bin` (der).
3. **Race post-resume:** PipeWire abre stream antes de FW (Track D — agravante, no causa `-110` inicial).
4. **Parches 0006/0007 insuficientes** en path resume (solo cubren boot/retry parcial).

---

## Reproducción

```bash
# Precondición: boot limpio con Speaker OK
wpctl status | grep Speaker
./scripts/fw-validation-run.sh boot --notes "pre-suspend-baseline"

# Suspend ~30s
systemctl suspend

# Tras login
journalctl -k -b | grep -iE 'failed to resume|playback without fw' | tail -10
wpctl status | grep -E 'Speaker|Dummy'
./scripts/fw-validation-run.sh suspend --notes "track-a-retest"
```

---

## Investigación pendiente

- [ ] Log estructurado: timestamp `PM suspend exit` → primer `-110` → primer `done=0`
- [ ] Probar con módulos **upstream** (sin ENZOPLAY)
- [ ] Aplicar Serie B (`0006`+`0007`) y repetir matriz 10× suspend
- [ ] ¿Segundo suspend en misma sesión empeora? (sesión `a2f361bf`, boots 3–6)
- [ ] Correlacionar con Track F (ACPI GPP4) si hay datos `acpidump`
- [ ] Upstream: retry FW en **resume callback**, no solo en `hw_params`

---

## Criterio de cierre

- ≥6/6 suspend_resume con `uid8_fw=OK` y `uidb_fw=OK`
- 0× `playback without fw` en ventana 60s post-resume
- `wpctl` muestra **Audio Coprocessor Speaker** sin reboot manual

---

## Referencias

- Parches: [`../../patches/0006-tas2783-fw-retry-on-timeout.patch`](../../patches/0006-tas2783-fw-retry-on-timeout.patch), [`../../patches/0007-tas2783-hw-params-wait-fw.patch`](../../patches/0007-tas2783-hw-params-wait-fw.patch)
- Upstream: [`../../upstream/series-B-firmware/`](../../upstream/series-B-firmware/)
- Logs: `validation/boot-logs/boot-003.log` … `boot-014.log` (suspend)

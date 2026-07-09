# TRACK E — Automatización validación FW (systemd)

**Prioridad:** P3  
**Impacto:** huecos en matriz; no afecta audio directamente

---

## Problemas

### E1 — Ordering cycle (boot)

```text
ordering cycle: snd-repair-fw-validation.service → graphical.target → multi-user.target
Job snd-repair-fw-validation.service/start deleted
```

**Efecto:** unidad **system** a veces no ejecuta `auto@boot`.

**Workaround actual:** unidad **user** + `loginctl enable-linger`.

### E2 — ExecStartPost omitido en fallo

Si `px13-audio-resume.service` sale con código 1, `ExecStartPost` (hook suspend) **no apareció** en journal (boot 20:05).

**Mitigación:** hook llamado desde `px13-audio-fix.sh` + `SuccessExitStatus=1` en drop-in.

### E3 — Dedup suspend

Primer diseño usaba `boot_id` → bloqueaba filas suspend; corregido con timestamp 45s.

---

## Investigación pendiente

- [ ] Reordenar unidad system: `After=sound.target`, `Before=pipewire` (sin `graphical.target`)
- [ ] Confirmar drop-in instalado: `/etc/systemd/system/px13-audio-resume.service.d/`
- [ ] Verificar fila boot #14 `resume-20:05-fail` vs auto@suspend pendientes
- [ ] Documentar en [`../../docs/FW-VALIDATION.md`](../../docs/FW-VALIDATION.md)

---

## Instalación / verificación

```bash
./scripts/install-fw-validation-service.sh
sudo ./scripts/install-fw-validation-service.sh --suspend-only
sudo systemctl daemon-reload
journalctl -b | grep -iE 'snd-repair-fw|ordering cycle'
tail -3 validation/fw-matrix.csv
```

---

## Criterio de cierre

- 100% boots registran `auto@boot` o equivalente
- 100% resumes registran `auto@suspend` dentro de 90s post-resume
- 0× ordering cycle en journal

---

## Referencias

- [`../../scripts/install-fw-validation-service.sh`](../../scripts/install-fw-validation-service.sh)
- [`../../systemd/px13-audio-resume.service.d-snd-repair-fw-validation.conf`](../../systemd/px13-audio-resume.service.d-snd-repair-fw-validation.conf)

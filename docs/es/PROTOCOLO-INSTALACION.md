# Protocolo de instalación y comprobación — PX13

> [English](../INSTALL-VERIFY-PROTOCOL.md) | **Español**

**ASUS ProArt PX13 HN7306EAC**, kernel `7.0.0-27-generic`.

Diagnóstico rápido: `./scripts/px13-stack-check.sh`

---

## Capas del stack

| Capa | Qué | Comando | Para qué |
|------|-----|---------|----------|
| **L0** | Módulos stock | `apt reinstall linux-modules-$(uname -r)` | Base limpia |
| **L1** | Firmware + UCM | brainchillz `fix-px13-audio.sh` | Speaker en PipeWire |
| **L2** | Parches upstream A+B+C | `build-from-upstream.sh` | Estéreo, -22, FW |
| **L3** | Resume W1+W2 | `build-w1-w2.sh` | Audio tras S2 |
| **L4** | Mic UCM | `install-ucm-px13.sh` | Mic interno GNOME |
| **L5** | Verificación | `post-s2-user-witness.sh` | KPI-U |

**No mezclar** `px13-audio-resume.service` con **L3**.

---

## Fase 0 — Limpieza

```bash
sudo systemctl disable --now px13-audio-resume.service
sudo apt install --reinstall linux-modules-$(uname -r)
sudo depmod -a && sudo reboot
./scripts/px13-stack-check.sh
```

---

## Fase 1 — brainchillz

```bash
./fix-px13-audio.sh && sudo reboot
```

Comprobar: firmware en `/lib/firmware/`, `wpctl` → Speaker (no Dummy).

---

## Fase 2 — Kernel upstream

```bash
./scripts/prepare-kernel-tree.sh
./scripts/build-from-upstream.sh && sudo reboot
```

Comprobar: estéreo L/R, `vermagic` = `uname -r`.

---

## Fase 3 — Resume W1+W2

```bash
sudo ./scripts/build-w1-w2.sh
sudo systemctl disable --now px13-audio-resume.service
sudo reboot
```

---

## Fase 4 — Mic (si falta)

```bash
sudo ./scripts/install-ucm-px13.sh
systemctl --user restart wireplumber pipewire
```

---

## Fase 5 — KPI-U

Tras S2, esperar ~30 s:

```bash
./scripts/post-s2-user-witness.sh
```

PASS = mic OK + **confirmas que oyes** el tono.

---

## Dónde falla (tu máquina ahora)

Tras comprobar stock el **13 jul 2026**:

| Capa | Estado |
|------|--------|
| L0 stock | OK (sin W2/W3) |
| L1 firmware + UCM | OK |
| L2 upstream | **Falta** — módulos distro |
| L3 W1+W2 | **Falta** |
| Post-S2 | **-110** en dmesg (esperado sin L3) |

**Siguiente paso:** Fase 2 → reboot → Fase 3 → reboot → witness.

Matriz completa de síntomas: [INSTALL-VERIFY-PROTOCOL.md](../INSTALL-VERIFY-PROTOCOL.md).

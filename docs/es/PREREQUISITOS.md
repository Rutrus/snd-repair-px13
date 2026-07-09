# Requisitos previos

> [English](../PREREQUISITES.md) | **Español**

---

## Hardware

| Requisito | Notas |
|-----------|-------|
| **ASUS ProArt PX13 (HN7306EAC)** | AMD ACP70, 2× TAS2783 SoundWire |
| Kernel **7.0+** | Probado `7.0.0-27-generic` |
| Ubuntu 26.04 / Linux Mint 22.x | Otras derivadas Debian con ajustes |

---

## Etapa 1 — brainchillz

```bash
sudo apt install git alsa-utils pipewire pipewire-pulse wireplumber
```

Necesario además:

- Firmware `.bin` extraído localmente (no en git)
- sudo para `/lib/firmware`, systemd, UCM

---

## Etapa 2 — snd_repair

`prepare-kernel-tree.sh` instala:

```bash
build-essential flex bison libssl-dev libelf-dev dwarves bc zstd \
linux-headers-$(uname -r) linux-source-$(uname -r | cut -d- -f1-2)
```

**Espacio:** ~4 GB en `build/`.

---

## Verificación

```bash
sudo apt install alsa-utils
wpctl status
```

---

## No necesario

DKMS, kernel personalizado completo, ni desactivar Secure Boot salvo que el sistema bloquee módulos sin firmar.

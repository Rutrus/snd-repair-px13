# Lista de verificación

> [English](../VERIFICATION.md) | **Español**

Usar tras **etapa 1** (brainchillz) y de nuevo tras **etapa 2** (módulos kernel). Ver [`INSTALACION.md`](INSTALACION.md).

---

## 1. Firmware cargado

```bash
journalctl -k -b 0 | grep -i tas2783
```

**OK:** sin `Direct firmware load ... failed`, sin `error playback without fw download`.

```bash
ls -lh /lib/firmware/1714-1-8.bin /lib/firmware/1714-1-B.bin
```

---

## 2. Enumeración SoundWire

```bash
ls /sys/bus/soundwire/devices/
```

**OK:** tres dispositivos (RT721 + TAS2783 en `0x8` y `0xb`).

---

## 3. PipeWire / UCM (etapa 1)

```bash
wpctl status
```

**OK:** sink **Audio Coprocessor Speaker** (no solo Dummy Output).

---

## 4. Módulos kernel (etapa 2)

```bash
modinfo snd_soc_tas2783_sdw | grep vermagic
```

**OK:** `vermagic` coincide con `uname -r`.

**OK (producción):** sin cadenas `ENZOPLAY` si se usó `build-from-upstream.sh`.

---

## 5. Estéreo

```bash
speaker-test -D plughw:1,2 -c 2 -t wav -l 1 -s 1
speaker-test -D plughw:1,2 -c 2 -t wav -l 1 -s 2
speaker-test -D pipewire -c 2 -t sine -f 440 -l 1
```

---

## 6. Suspend / resume

```bash
systemctl suspend
wpctl status
speaker-test -D pipewire -c 2 -t sine -f 440 -l 1
```

---

## Resumen

| Comprobación | Etapa |
|--------------|-------|
| dmesg firmware OK | 1 |
| `wpctl` Speaker | 1 |
| Recuperación tras suspend | 1 |
| vermagic | 2 |
| L/R con speaker-test | 2 |

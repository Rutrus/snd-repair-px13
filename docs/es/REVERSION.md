# Reversión — restaurar stack de audio original

> [English](../ROLLBACK.md) | **Español**

---

## Módulos kernel (etapa 2)

### Con backups en `$HOME`

```bash
KVER=$(uname -r)
sudo cp ~/snd-soc-tas2783-sdw.ko.zst.orig \
  /lib/modules/$KVER/kernel/sound/soc/codecs/snd-soc-tas2783-sdw.ko.zst
sudo cp ~/snd-soc-sdw-utils.ko.zst.orig \
  /lib/modules/$KVER/kernel/sound/soc/sdw_utils/snd-soc-sdw-utils.ko.zst
sudo depmod -a && sudo reboot
```

### Sin backups

```bash
sudo apt install --reinstall linux-image-$(uname -r) linux-modules-$(uname -r)
sudo reboot
```

### Limpiar árbol parcheado

```bash
rm -f build/linux-source/.snd-repair-upstream-applied \
      build/linux-source/.snd-repair-upstream-kernel-version
cd build/linux-source && git checkout -- sound/ 2>/dev/null || true
```

---

## Capa de usuario (etapa 1 — brainchillz)

```bash
sudo systemctl disable --now px13-audio-rebind.service px13-audio-resume.service
sudo rm -f /etc/systemd/system/px13-audio-{rebind,resume}.service
sudo rm -f /usr/local/sbin/px13-audio-fix.sh
sudo apt install --reinstall alsa-ucm-conf
sudo systemctl daemon-reload
```

Firmware en `/lib/firmware/` puede dejarse; no afecta a otros equipos.

---

## Módulos de investigación (solo debug)

Ver [`../../patches/README.es.md`](../../patches/README.es.md) — restaurar `soundwire-amd` / `soundwire-bus` desde `*.orig`.

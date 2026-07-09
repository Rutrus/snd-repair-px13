# Parches kernel — PX13 / TAS2783

> [English](README.md) | **Español**

## Producción (uso normal)

| Parche | Problema | Módulo |
|--------|----------|--------|
| 0004 | Capture -22 | `snd-soc-tas2783-sdw` |
| 0006 | FW timeout -110 | `snd-soc-tas2783-sdw` |
| 0007 | Race hw_params / FW | `snd-soc-tas2783-sdw` |
| 0009 | Estéreo L/R | `snd-soc-tas2783-sdw` + `snd-soc-sdw-utils` |

**Automatizado (recomendado — series upstream limpias):**

```bash
cd ~/snd_repair
./scripts/prepare-kernel-tree.sh
./scripts/build-from-upstream.sh
sudo reboot
```

**Solo investigación** (`patches/`, incluye `ENZOPLAY` en 0009):

```bash
./scripts/build-production-modules.sh
```

Parches **0001–0003, 0005, 0008**: solo depuración (trazas `ENZODBG` / `ENZOPLAY`). Ver secciones inferiores.

Equivalentes sin trazas de depuración: [`../upstream/`](../upstream/README.md).

---

# Instrumentación SoundWire — PX13 / TAS2783

Prefijo de trazas: **`ENZODBG[N]`** → `sudo dmesg | grep ENZODBG`

| Fase | Origen | Significado |
|------|--------|-------------|
| `[1]` | tas2783-sdw | hw_params (dev + devnum) |
| `[2]` | tas2783-sdw | add_slave OK/FAIL |
| `[3]` | stream.c | slave_port ENTER/OK/FAIL (devnum) |
| `[4]` | amd_manager + stream | amd_xport ENTER/OK/FAIL |
| `[5]` | amd_manager + stream | amd_port / master_port OK/FAIL |
| `[6]` | stream.c | sdw_program_port_params OK + sdw_program_params ret |

Todas las trazas incluyen identificador de dispositivo (`devnum`, `link`, etc.) y registran **éxito y fallo**.

## Mapa archivo → módulo

| Fuente | `.ko` |
|--------|-------|
| `drivers/soundwire/stream.c` | **`soundwire-bus.ko`** |
| `drivers/soundwire/amd_manager.c` | **`soundwire-amd.ko`** |
| `sound/soc/codecs/tas2783-sdw.c` | **`snd-soc-tas2783-sdw.ko`** |

Parches **0001 + 0002**: un solo `make M=drivers/soundwire modules` → instalar **ambos** `.ko.zst`.

---

## 1. Preparar árbol

```bash
sudo apt install build-essential flex bison libssl-dev libelf-dev dwarves bc \
  linux-headers-$(uname -r) zstd

cd ~/snd_repair
./scripts/prepare-kernel-tree.sh
# o: cd build/linux-source  (tras prepare-kernel-tree.sh)
```

## 2. Aplicar parches (0001 + 0002 juntos)

```bash
patch -p1 < ~/snd_repair/patches/0001-sdw-debug-program-port-params.patch
patch -p1 < ~/snd_repair/patches/0002-sdw-debug-amd-manager.patch
# opcional:
# patch -p1 < ~/snd_repair/patches/0003-sdw-debug-tas2783-hw_params.patch
```

## 3. Compilar

```bash
make -j"$(nproc)" M=drivers/soundwire modules

# solo si aplicas 0003:
make -j"$(nproc)" M=sound/soc/codecs CONFIG_SND_SOC_TAS2783_SDW=m modules
```

## 4. Instalar como `.ko.zst` (no copiar `.ko` sin comprimir)

```bash
KVER=$(uname -r)
DEST=/lib/modules/$KVER/kernel/drivers/soundwire

# Backup originales
sudo mv $DEST/soundwire-amd.ko.zst ~/soundwire-amd.ko.zst.orig
sudo mv $DEST/soundwire-bus.ko.zst ~/soundwire-bus.ko.zst.orig

# Comprimir e instalar
zstd -19 -f drivers/soundwire/soundwire-amd.ko -o /tmp/soundwire-amd.ko.zst
zstd -19 -f drivers/soundwire/soundwire-bus.ko -o /tmp/soundwire-bus.ko.zst
sudo cp /tmp/soundwire-amd.ko.zst /tmp/soundwire-bus.ko.zst $DEST/

sudo depmod -a
sudo reboot
```

Si aplicas 0003:

```bash
sudo mv /lib/modules/$KVER/kernel/sound/soc/codecs/snd-soc-tas2783-sdw.ko.zst \
  ~/snd-soc-tas2783-sdw.ko.zst.orig
zstd -19 -f sound/soc/codecs/snd-soc-tas2783-sdw.ko -o /tmp/snd-soc-tas2783-sdw.ko.zst
sudo cp /tmp/snd-soc-tas2783-sdw.ko.zst \
  /lib/modules/$KVER/kernel/sound/soc/codecs/
sudo depmod -a
```

---

## 5. Verificar que cargas TU módulo (antes del reinicio / reproducir audio)

```bash
modinfo -n soundwire_amd
modinfo -n soundwire_bus

strings "$(modinfo -n soundwire_amd)" | grep ENZODBG
strings "$(modinfo -n soundwire_bus)" | grep ENZODBG

modinfo soundwire_amd | grep vermagic
modinfo soundwire_bus | grep vermagic
```

Ambos `vermagic` deben coincidir exactamente con el kernel en ejecución, p. ej.:

```
7.0.0-27-generic SMP preempt mod_unload modversions
```

Si no coincide, el kernel ignorará el módulo o fallará al cargarlo — la ausencia de trazas no implicaría fallo de audio sino de instrumentación.

Debes ver cadenas `ENZODBG[4]`, `ENZODBG[5]`, `ENZODBG[6]` en los `.ko`.

---

## 6. Probar

```bash
aplay /usr/share/sounds/alsa/Front_Center.wav
sudo dmesg -T | grep ENZODBG
```

### Árbol de decisión

```
ENZODBG[4] amd_xport OK … ret=0
ENZODBG[5] amd_port OK … ret=0
ENZODBG[6] sdw_program_params ret=-22
    → fallo en stream.c (esclavo); mirar [3] slave_port FAIL / dpn_prop NULL

ENZODBG[4] amd_xport FAIL ret=-EINVAL
    → bug ruta AMD (acp_rev / instance)

ENZODBG[6] sdw_program_port_params OK + sdw_program_params ret=0
    → AMD + bus OK; buscar fallo en sdw_notify_config u otra fase
```

---

## Restaurar originales

```bash
KVER=$(uname -r)
sudo cp ~/soundwire-amd.ko.zst.orig \
  /lib/modules/$KVER/kernel/drivers/soundwire/soundwire-amd.ko.zst
sudo cp ~/soundwire-bus.ko.zst.orig \
  /lib/modules/$KVER/kernel/drivers/soundwire/soundwire-bus.ko.zst
sudo depmod -a && sudo reboot
```

---

## Nota ACP70

`amd_sdw_transport_params()` / `amd_sdw_port_params()` en ruta ACP70 válida **retornan 0**.
Si ves `amd_xport EXIT ret=0` y luego `port_params ret=-22`, el origen está en `stream.c`.

---

## Parche funcional 0004 (fix capture TAS2783)

Corrige `Program transport params failed: -22` en captura cuando el DisCo no anuncia `source_ports`.

**No requiere** 0001–0003. Aplica sobre fuente vanilla:

```bash
cd ~/snd_repair/build/linux-source   # o $KERNEL_SRC
patch -p1 < ~/snd_repair/patches/0004-tas2783-skip-capture-without-source-ports.patch

make -C /lib/modules/$(uname -r)/build \
  M="$(pwd)/sound/soc/codecs" CONFIG_SND_SOC_TAS2783_SDW=m modules
```

Instalar:

```bash
KVER=$(uname -r)
DEST=/lib/modules/$KVER/kernel/sound/soc/codecs
sudo mv $DEST/snd-soc-tas2783-sdw.ko.zst ~/snd-soc-tas2783-sdw.ko.zst.orig
zstd -19 -f sound/soc/codecs/snd-soc-tas2783-sdw.ko -o /tmp/snd-soc-tas2783-sdw.ko.zst
sudo cp /tmp/snd-soc-tas2783-sdw.ko.zst $DEST/
sudo depmod -a && sudo reboot
```

Recomendado: restaurar también `soundwire-{bus,amd}.ko.zst` originales si siguen instrumentados.

---

## Fase FW: caracterizar `-110` (antes de mutex)

### Paso 1 — Matriz de reboots (sin parches nuevos)

```bash
~/snd_repair/scripts/collect-tas2783-fw.sh
# tras cada reboot:
~/snd_repair/scripts/collect-tas2783-fw.sh >> ~/tas2783-fw-matrix.log

# resumen tras N boots:
~/snd_repair/scripts/summarize-fw-matrix.sh ~/tas2783-fw-matrix.log
```

Interpretación:

| Patrón | Siguiente paso |
|--------|----------------|
| Alternancia `:8` / `:b` FAIL | Instrumentar (0005) → retry (0006) |
| Siempre el mismo UID FAIL | Firmware/ACPI/hardware antes que mutex |
| Ambos OK siempre | Intermitente; subir N |

Comprobar estéreo en cada boot: `speaker-test -D plughw:1,2 -c 2 -t wav -l 1`

### Paso 2 — Instrumentación `tas2783_fw_ready` (0005)

Trazas **`ENZOFW[1]`**: `io_init`, `fw_ready START/END`, cada `nwrite`, con `uid` y `jiffies`.

```bash
cd build/linux-source   # tras ./scripts/prepare-kernel-tree.sh
patch -p1 < ../patches/0005-tas2783-fw-download-instrumentation.patch
make -C /lib/modules/$(uname -r)/build \
  M="$(pwd)/sound/soc/codecs" CONFIG_SND_SOC_TAS2783_SDW=m modules
# instalar .ko.zst como en 0004
```

Detectar paralelismo: si `fw_ready START` de `:8` y `:b` se solapan en `jiffies` → descargas concurrentes (hecho observable, no implica aún causa del `-110`).

### Paso 3 — Experimento retry (0006, solo tras matriz)

Reintenta `sdw_nwrite_no_pm` hasta 5 veces con `usleep_range(10ms, 15ms)` en `-ETIMEDOUT`/`-EAGAIN`.

```bash
patch -p1 < ../patches/0006-tas2783-fw-retry-on-timeout.patch
# recompilar e instalar como 0004
```

Si 10/10 boots → estéreo OK con solo 0006, el timeout era transitorio.

**No aplicar mutex** hasta demostrar solapamiento en 0005 y que 0006 no basta.

### Paso 4 — Esperar FW en hw_params (0007)

Si la matriz muestra `WARN(no-fw-hw_params)` en `:8` pero sin `FW download failed`, PipeWire abre el stream antes de que termine `request_firmware_nowait`. 0007 hace `wait_event` en `hw_params` antes de rechazar.

Combinar con 0006:

```bash
patch -p1 < ../patches/0006-tas2783-fw-retry-on-timeout.patch
patch -p1 < ../patches/0007-tas2783-hw-params-wait-fw.patch
~/snd_repair/scripts/install-tas2783-ko.sh
sudo reboot
```

---

## Parche 0008 — instrumentación playback (Problema C)

Trazas `ENZOPLAY` en `tas2783-sdw.c` + `soc_sdw_utils.c`. **No toca firmware ni SoundWire.**

```bash
~/snd_repair/scripts/build-playback-instrumentation.sh
# instalar ambos .ko.zst con sudo (ver script) + reboot
~/snd_repair/scripts/run-stereo-phase1.sh ~/tas2783-stereo-phase1.log
grep ENZOPLAY ~/tas2783-stereo-phase1.log
```

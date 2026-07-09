# Kernel patches — PX13 / TAS2783

> **English** | [Español](README.es.md)

## Production (normal use)

| Patch | Issue | Module |
|-------|-------|--------|
| 0004 | Capture -22 | `snd-soc-tas2783-sdw` |
| 0006 | FW timeout -110 | `snd-soc-tas2783-sdw` |
| 0007 | hw_params / FW race | `snd-soc-tas2783-sdw` |
| 0009 | Stereo L/R | `snd-soc-tas2783-sdw` + `snd-soc-sdw-utils` |

**Automated (recommended — clean upstream series):**

```bash
cd ~/snd_repair
./scripts/prepare-kernel-tree.sh
./scripts/build-from-upstream.sh
sudo reboot
```

**Investigation only** (`patches/`, includes `ENZOPLAY` in 0009):

```bash
./scripts/build-production-modules.sh
```

Patches **0001–0003, 0005, 0008**: debug only (`ENZODBG` / `ENZOPLAY` traces). See sections below.

Clean equivalents without debug traces: [`../upstream/`](../upstream/README.md).

---

# SoundWire instrumentation — PX13 / TAS2783

Trace prefix: **`ENZODBG[N]`** → `sudo dmesg | grep ENZODBG`

| Phase | Source | Meaning |
|-------|--------|---------|
| `[1]` | tas2783-sdw | hw_params (dev + devnum) |
| `[2]` | tas2783-sdw | add_slave OK/FAIL |
| `[3]` | stream.c | slave_port ENTER/OK/FAIL (devnum) |
| `[4]` | amd_manager + stream | amd_xport ENTER/OK/FAIL |
| `[5]` | amd_manager + stream | amd_port / master_port OK/FAIL |
| `[6]` | stream.c | sdw_program_port_params OK + sdw_program_params ret |

All traces include device id (`devnum`, `link`, etc.) and log **success and failure**.

## File → module map

| Source | `.ko` |
|--------|-------|
| `drivers/soundwire/stream.c` | **`soundwire-bus.ko`** |
| `drivers/soundwire/amd_manager.c` | **`soundwire-amd.ko`** |
| `sound/soc/codecs/tas2783-sdw.c` | **`snd-soc-tas2783-sdw.ko`** |

Patches **0001 + 0002**: single `make M=drivers/soundwire modules` → install **both** `.ko.zst`.

---

## 1. Prepare tree

```bash
sudo apt install build-essential flex bison libssl-dev libelf-dev dwarves bc \
  linux-headers-$(uname -r) zstd

cd ~/snd_repair
./scripts/prepare-kernel-tree.sh
# or: cd build/linux-source
```

## 2. Apply patches (0001 + 0002 together)

```bash
patch -p1 < ~/snd_repair/patches/0001-sdw-debug-program-port-params.patch
patch -p1 < ~/snd_repair/patches/0002-sdw-debug-amd-manager.patch
# optional:
# patch -p1 < ~/snd_repair/patches/0003-sdw-debug-tas2783-hw_params.patch
```

## 3. Build

```bash
make -j"$(nproc)" M=drivers/soundwire modules

# only if applying 0003:
make -j"$(nproc)" M=sound/soc/codecs CONFIG_SND_SOC_TAS2783_SDW=m modules
```

## 4. Install as `.ko.zst` (do not copy uncompressed `.ko`)

```bash
KVER=$(uname -r)
DEST=/lib/modules/$KVER/kernel/drivers/soundwire

sudo mv $DEST/soundwire-amd.ko.zst ~/soundwire-amd.ko.zst.orig
sudo mv $DEST/soundwire-bus.ko.zst ~/soundwire-bus.ko.zst.orig

zstd -19 -f drivers/soundwire/soundwire-amd.ko -o /tmp/soundwire-amd.ko.zst
zstd -19 -f drivers/soundwire/soundwire-bus.ko -o /tmp/soundwire-bus.ko.zst
sudo cp /tmp/soundwire-amd.ko.zst /tmp/soundwire-bus.ko.zst $DEST/

sudo depmod -a
sudo reboot
```

If applying 0003:

```bash
sudo mv /lib/modules/$KVER/kernel/sound/soc/codecs/snd-soc-tas2783-sdw.ko.zst \
  ~/snd-soc-tas2783-sdw.ko.zst.orig
zstd -19 -f sound/soc/codecs/snd-soc-tas2783-sdw.ko -o /tmp/snd-soc-tas2783-sdw.ko.zst
sudo cp /tmp/snd-soc-tas2783-sdw.ko.zst \
  /lib/modules/$KVER/kernel/sound/soc/codecs/
sudo depmod -a
```

---

## 5. Verify you load YOUR module

```bash
modinfo -n soundwire_amd
modinfo -n soundwire_bus

strings "$(modinfo -n soundwire_amd)" | grep ENZODBG
strings "$(modinfo -n soundwire_bus)" | grep ENZODBG

modinfo soundwire_amd | grep vermagic
modinfo soundwire_bus | grep vermagic
```

Both `vermagic` values must match the running kernel, e.g.:

```
7.0.0-27-generic SMP preempt mod_unload modversions
```

Mismatch means the kernel ignores or fails to load the module — missing traces would indicate instrumentation failure, not necessarily audio failure.

You should see `ENZODBG[4]`, `ENZODBG[5]`, `ENZODBG[6]` strings in the `.ko` files.

---

## 6. Test

```bash
aplay /usr/share/sounds/alsa/Front_Center.wav
sudo dmesg -T | grep ENZODBG
```

### Decision tree

```
ENZODBG[4] amd_xport OK … ret=0
ENZODBG[5] amd_port OK … ret=0
ENZODBG[6] sdw_program_params ret=-22
    → failure in stream.c (slave); check [3] slave_port FAIL / dpn_prop NULL

ENZODBG[4] amd_xport FAIL ret=-EINVAL
    → AMD path bug (acp_rev / instance)

ENZODBG[6] sdw_program_port_params OK + sdw_program_params ret=0
    → AMD + bus OK; look at sdw_notify_config or another phase
```

---

## Restore originals

```bash
KVER=$(uname -r)
sudo cp ~/soundwire-amd.ko.zst.orig \
  /lib/modules/$KVER/kernel/drivers/soundwire/soundwire-amd.ko.zst
sudo cp ~/soundwire-bus.ko.zst.orig \
  /lib/modules/$KVER/kernel/drivers/soundwire/soundwire-bus.ko.zst
sudo depmod -a && sudo reboot
```

---

## ACP70 note

`amd_sdw_transport_params()` / `amd_sdw_port_params()` on a valid ACP70 path **return 0**.
If you see `amd_xport EXIT ret=0` then `port_params ret=-22`, the origin is in `stream.c`.

---

## Functional patch 0004 (TAS2783 capture fix)

Fixes `Program transport params failed: -22` on capture when DisCo does not advertise `source_ports`.

**Does not require** 0001–0003. Apply on vanilla source:

```bash
cd ~/snd_repair/build/linux-source
patch -p1 < ~/snd_repair/patches/0004-tas2783-skip-capture-without-source-ports.patch

make -C /lib/modules/$(uname -r)/build \
  M="$(pwd)/sound/soc/codecs" CONFIG_SND_SOC_TAS2783_SDW=m modules
```

Install:

```bash
KVER=$(uname -r)
DEST=/lib/modules/$KVER/kernel/sound/soc/codecs
sudo mv $DEST/snd-soc-tas2783-sdw.ko.zst ~/snd-soc-tas2783-sdw.ko.zst.orig
zstd -19 -f sound/soc/codecs/snd-soc-tas2783-sdw.ko -o /tmp/snd-soc-tas2783-sdw.ko.zst
sudo cp /tmp/snd-soc-tas2783-sdw.ko.zst $DEST/
sudo depmod -a && sudo reboot
```

Recommended: also restore original `soundwire-{bus,amd}.ko.zst` if still instrumented.

---

## FW phase: characterize `-110` (before mutex)

### Step 1 — Reboot matrix (no new patches)

```bash
./scripts/collect-tas2783-fw.sh
# after each reboot:
./scripts/collect-tas2783-fw.sh >> ~/tas2783-fw-matrix.log

./scripts/summarize-fw-matrix.sh ~/tas2783-fw-matrix.log
```

| Pattern | Next step |
|---------|-------------|
| Alternating `:8` / `:b` FAIL | Instrument (0005) → retry (0006) |
| Same UID always FAIL | Firmware/ACPI/hardware before mutex |
| Both always OK | Intermittent; increase N |

Check stereo each boot: `speaker-test -D plughw:1,2 -c 2 -t wav -l 1`

### Step 2 — `tas2783_fw_ready` instrumentation (0005)

Traces **`ENZOFW[1]`**: `io_init`, `fw_ready START/END`, each `nwrite`, with `uid` and `jiffies`.

```bash
cd build/linux-source
patch -p1 < ../patches/0005-tas2783-fw-download-instrumentation.patch
make -C /lib/modules/$(uname -r)/build \
  M="$(pwd)/sound/soc/codecs" CONFIG_SND_SOC_TAS2783_SDW=m modules
```

### Step 3 — Retry experiment (0006, only after matrix)

Retries `sdw_nwrite_no_pm` up to 5 times with `usleep_range(10ms, 15ms)` on `-ETIMEDOUT`/`-EAGAIN`.

### Step 4 — Wait for FW in hw_params (0007)

If matrix shows `WARN(no-fw-hw_params)` on `:8` without `FW download failed`, PipeWire opens the stream before `request_firmware_nowait` completes. 0007 adds `wait_event` in `hw_params`.

Combine with 0006, or use `./scripts/build-production-modules.sh` for the full production set.

---

## Patch 0008 — playback instrumentation (Problem C)

`ENZOPLAY` traces in `tas2783-sdw.c` + `soc_sdw_utils.c`. **Does not touch firmware or SoundWire.**

```bash
./scripts/build-playback-instrumentation.sh
./scripts/run-stereo-phase1.sh ~/tas2783-stereo-phase1.log
grep ENZOPLAY ~/tas2783-stereo-phase1.log
```

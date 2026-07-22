# Troubleshooting

Short fixes for common PX13 audio issues with this install stack.

---

## `install-modules`: missing 0001 / 0002 marker (false negative)

**Symptom:**

```text
ERROR: staged snd-soc-tas2783-sdw.ko.zst missing 0001 marker — rebuild post-sleep first
```

(or the same for 0002 / `soundwire-amd`)

**Cause (fixed in `lib/modules.sh`):** with `set -o pipefail`, `zstdcat | strings | grep -q` can exit non-zero when `grep -q` closes the pipe early (SIGPIPE on `strings`), even if the marker string is present. Staging was fine; the check lied.

**Check staging yourself:**

```bash
ST=build/staging/$(uname -r)
zstdcat "$ST/snd-soc-tas2783-sdw.ko.zst" | strings | grep -F 'post-sleep playback fw_reinit failed'
zstdcat "$ST/soundwire-amd.ko.zst" | strings | grep -F 'amd_sdw_kick_irq_if_pending'
```

**Fix:** pull/use current `scripts/lib/modules.sh`, then retry (no rebuild if the greps above match):

```bash
sudo ./scripts/snd-repair install-modules
```

If the manual `grep` finds nothing, staging really lacks the patch:

```bash
./scripts/snd-repair build
sudo ./scripts/snd-repair install-modules
```

---

## Post-s2idle: slaves UNATTACHED / FW timeout storm

**Symptom:** Speaker sink visible in `wpctl`, but silent; dmesg spam:

```text
slave-tas2783 … failed to resume: error -110
fw download wait timeout in hw_params
trf on Slave N failed:-5
```

**Check:**

```bash
grep . /sys/bus/soundwire/devices/sdw:*/status
# FAIL: UNATTACHED on :8 / :b / rt721
./scripts/snd-repair status   # overlay may still show 0001/0002 OK
```

**Cause:** after s2idle the SoundWire slaves never re-ATTACH. Patches 0001/0002 help the normal resume path; they do not make a userspace PCI unbind/bind safe.

### DANGER — do not PCI-reset live

**Incident 2026-07-19:** `sudo PX13_AFTER_SUSPEND=1 …/px13-audio-fix.sh` (PCI unbind/bind of `0000:c4:00.5`) **froze the whole machine**; recovery required a hard power-off. Same class of risk as enabling `px13-audio-resume.service` with the overlay loaded.

```bash
# FORBIDDEN while snd_repair overlay is installed / session live:
sudo PX13_AFTER_SUSPEND=1 /usr/local/sbin/px13-audio-fix.sh
sudo systemctl start px13-audio-resume.service
# manual: echo … > …/snd_pci_ps/unbind
```

### Safe recover

1. Stop PipeWire hammer (optional, reduces log spam):

```bash
systemctl --user stop wireplumber pipewire pipewire-pulse \
  pipewire.socket pipewire-pulse.socket 2>/dev/null
```

2. **Cold power cycle** (full power off ≥10 s — not a soft reboot only).

3. After login:

```bash
grep . /sys/bus/soundwire/devices/sdw:*/status   # Attached
wpctl status | head -40                          # Speaker *
speaker-test -D pipewire -c 2 -t sine -f 440 -l 1
```

Boot-time `px13-audio-rebind.service` with `PX13_SKIP_PCI_ON_BOOT=1` is OK (no PCI reset). Keep `px13-audio-resume.service` **disabled**.

---

## Post-s2idle: Attached but silent (open stream)

**Symptom:** After suspend, Speaker still selected, PCM may show `RUNNING`, **no** `fw download wait timeout` / `-110`, but no audible output. Often Firefox (or another client) was playing through S2.

**Check:**

```bash
grep . /sys/bus/soundwire/devices/sdw:*/status
# expect Attached ×3
journalctl -k -b 0 | grep 'snd_repair resume enum kick' | tail -4
# expect kick + kick delayed with pend!=0
journalctl --user -b 0 | grep -i 'spa.alsa.*broken pipe\|Broken pipe' | tail -5
```

**Cause:** Case B re-attach (0003b) worked; patch 0001 only runs the second `fw_reinit()` on the **first post-sleep `hw_params`**. An open PipeWire stream that recovers in place never hits that gate. Patch **0001b** schedules the same second reinit after resume (~100 ms) so sound returns without reopening the device.

**Workaround (while Attached):** force a new `hw_params` — e.g. in GNOME Settings deselect then reselect the Speaker output, stop playback clients, or:

```bash
systemctl --user restart pipewire pipewire-pulse wireplumber
speaker-test -D pipewire -c 2 -t sine -f 440 -l 1
```

**Confirmed 2026-07-22:** unselect → reselect output device restored sound (no cold power). That reopens the ALSA PCM and hits 0001’s gate.

Do **not** cold-power or PCI-reset for this pattern (that is for UNATTACHED / Case B only).

---

## Dummy Output

**Cause:** `px13-audio-resume.service` (PCI reset) running together with kernel patches.

**Fix:**

```bash
sudo systemctl disable --now px13-audio-resume.service
sudo reboot
```

---

## No Speaker sink / no internal speakers in Settings

**Cause:** Firmware or UCM not installed.

**Fix:** Run [brainchillz `fix-px13-audio.sh`](https://github.com/brainchillz/asus-proart-px13-linux-speaker-fix), reboot.

```bash
ls -l /lib/firmware/1714-1-8.bin /lib/firmware/1714-1-B.bin
journalctl -k -b 0 | grep -i tas2783
```

---

## Speaker visible but silent after suspend

**Cause:** Patch 0001 not loaded, or PipeWire holds stale device.

**Check:**

```bash
./scripts/snd-repair status
# or:
modinfo -n snd-soc-tas2783-sdw | xargs zstdcat | \
  strings | grep -F 'post-sleep playback fw_reinit failed' || echo "rebuild 0001"
```

**Fix:**

```bash
./scripts/build-upstream-post-sleep-reinit.sh
sudo ./scripts/snd-repair install-modules
sudo reboot
```

Test with PipeWire stopped (rules out EBUSY):

```bash
systemctl --user stop wireplumber pipewire pipewire-pulse
systemctl suspend && sleep 10
speaker-test -D hw:1,2 -c 2 -r 48000 -t sine -f 440 -l 3
systemctl --user start pipewire pipewire-pulse wireplumber
```

---

## Patch 0002 not installed

**Symptoms:**

- `build-amd-soundwire-resume.sh` exits with `ERROR: 0002 marker not found in .../soundwire-amd.ko`
- `snd-repair status` shows `0002: MISSING`
- Verification prints nothing:

```bash
modinfo -n soundwire-amd | xargs zstdcat | \
  strings | grep amd_sdw_kick_irq_if_pending && echo OK
```

- Staged/installed module still shows lab strings:

```bash
modinfo -n soundwire-amd | xargs zstdcat | \
  strings | grep PHASE7 && echo "lab module — replace"
```

If `build-amd-soundwire-resume.sh` prints `ERROR: 0002 marker not found`:

- **Cause:** stale `soundwire-amd.o` in the build tree, or `amd_manager.c` still contaminated with phase7 from the lab branch.
- **Not installed:** script exits before staging — stock module remains after reboot.

**Fix:**

```bash
./scripts/snd-repair build
sudo ./scripts/snd-repair install-modules
sudo reboot
```

After reboot, expect `0002 OK` from `./scripts/snd-repair status`.

---

## Rollback / remove overlay

```bash
sudo ./scripts/snd-repair rollback
sudo reboot
```

If `status` reports **legacy in-tree** (old installs that overwrote `kernel/`):

```bash
sudo apt-get install --reinstall linux-modules-$(uname -r)
sudo reboot
```

---

**Cause:** Series C channel-map patch not applied.

**Fix:**

```bash
sudo ./scripts/reset-kernel-tree.sh
sudo ./scripts/apply-upstream-patches.sh
sudo ./scripts/build-from-upstream.sh
sudo reboot
```

---

## Internal microphone missing in GNOME

**Fix:**

```bash
sudo ./scripts/install-ucm-px13.sh
systemctl --user restart wireplumber pipewire
```

---

## `speaker-test`: Device or resource busy

PipeWire owns the PCM. Stop user services (see above) or use `-D pipewire`.

---

## After kernel upgrade — audio broken

Modules are tied to kernel version. Rebuild:

```bash
sudo ./scripts/reset-kernel-tree.sh
sudo ./scripts/apply-upstream-patches.sh
sudo ./scripts/build-from-upstream.sh
sudo ./scripts/build-upstream-post-sleep-reinit.sh
sudo ./scripts/build-amd-soundwire-resume.sh
sudo reboot
```

Verify:

```bash
modinfo snd_soc_tas2783_sdw | grep vermagic
uname -r
```

---

## `arecord` fails after suspend but GNOME mic works

**Expected limitation.** Direct ALSA read/write capture can fail post-S2; PipeWire uses MMAP and works. Not a regression for desktop use.

---

## Still stuck

Open an issue with: kernel version (`uname -r`), `journalctl -k -b 0 | grep -i tas2783`, cold boot vs post-S2.

Deep investigation: branch **`resolution/bruteforce`**.

# PX13 install and verification protocol

English (canonical). **ASUS ProArt PX13 HN7306EAC**, kernel `7.0.0-27-generic`.

One-command diagnostic: `./scripts/px13-stack-check.sh`

Spanish mirror: [`docs/es/PROTOCOLO-INSTALACION.md`](es/PROTOCOLO-INSTALACION.md)

---

## Stack layers (bottom → top)

| Layer | What | Script / source | Required for |
|-------|------|-----------------|--------------|
| **L0** | Distro kernel modules (stock baseline) | `apt reinstall linux-modules-*` | Clean start |
| **L1** | Firmware + UCM + rebind | brainchillz `fix-px13-audio.sh` | Speaker in PipeWire |
| **L2** | Upstream patches A+B+C | `build-from-upstream.sh` | Stereo, capture -22, FW retry |
| **L3** | Resume hacks W1+W2 | `build-w1-w2.sh` | Audio after S2 |
| **L4** | UCM mic (optional) | `install-ucm-px13.sh` | Internal mic in GNOME |
| **L5** | Verification | `post-s2-user-witness.sh` | KPI-U contract |

**Do not mix** `px13-audio-resume.service` with **L3 (W1+W2)** — causes Dummy Output. See [post-s2-silent-playback-recovery-20260712.md](../research/experiments/post-s2-silent-playback-recovery-20260712.md).

---

## Phase 0 — Clean baseline (optional reset)

When stack is broken (Dummy, silent, mixed experiments):

```bash
sudo systemctl disable --now px13-audio-resume.service
sudo apt install --reinstall linux-modules-$(uname -r)
sudo depmod -a && sudo reboot
```

Kernel 7.0: **no** `linux-modules-extra-*` package.

After reboot:

```bash
./scripts/px13-stack-check.sh
```

Expect: `module flavor tas2783 = stock`, L2/L3 FAIL — that is correct before reinstall.

---

## Phase 1 — User layer (brainchillz)

```bash
# In brainchillz repo, firmware extracted:
./fix-px13-audio.sh
sudo reboot
```

### Check 1A — after reboot

```bash
./scripts/px13-stack-check.sh
ls -lh /lib/firmware/1714-1-8.bin /lib/firmware/1714-1-B.bin
wpctl status    # Audio Coprocessor Speaker, NOT Dummy Output
journalctl -k -b 0 | grep -iE 'tas2783|without fw|Direct firmware.*failed'
```

| Result | Action |
|--------|--------|
| Dummy Output | Re-run fix-px13-audio.sh, verify firmware files |
| Speaker visible | Continue to Phase 2 |
| `without fw download` in dmesg | Install firmware `.bin` |

### Check 1B — cold playback (ear)

```bash
speaker-test -D pipewire -c 2 -t sine -f 440 -l 1
```

May work on stock L2 — stereo / stability need Phase 2.

---

## Phase 2 — Kernel upstream (A+B+C)

```bash
cd /path/to/snd_repair
./scripts/prepare-kernel-tree.sh
./scripts/build-from-upstream.sh
sudo reboot
```

### Check 2 — after reboot

```bash
./scripts/px13-stack-check.sh
modinfo snd_soc_tas2783_sdw | grep vermagic   # must match uname -r
speaker-test -D plughw:1,2 -c 2 -t wav -l 1 -s 1   # left
speaker-test -D plughw:1,2 -c 2 -t wav -l 1 -s 2   # right
speaker-test -D pipewire -c 2 -t sine -f 440 -l 1
```

| Result | Action |
|--------|--------|
| vermagic mismatch | Re-run build on running kernel |
| Left only | sdw-utils not installed — rebuild |
| Cold OK | Phase 3 |

---

## Phase 3 — Resume (W1+W2)

```bash
sudo ./scripts/build-w1-w2.sh
sudo systemctl disable --now px13-audio-resume.service
sudo reboot
```

### Check 3 — after reboot

```bash
./scripts/px13-stack-check.sh
# expect: W2-resume, px13-audio-resume disabled
journalctl -k -b 0 | grep -E 'W2 ctx=tas|fw_ready'   # only after first S2
```

---

## Phase 4 — Mic (if needed)

```bash
sudo ./scripts/install-ucm-px13.sh
systemctl --user restart wireplumber pipewire
```

Check: Internal Microphone in `wpctl status`.

---

## Phase 5 — Full KPI-U verification

**Cold boot** (optional baseline):

```bash
speaker-test -D pipewire -c 2 -t sine -f 440 -l 1
```

**After S2:**

```bash
systemctl suspend
# wake, wait ~30 s (no px13-audio-resume)
./scripts/post-s2-user-witness.sh
```

PASS = mic record OK + **you confirm hearing** the 440 Hz tone.

Automation (weaker): `./scripts/post-s2-user-witness.sh --no-audible-confirm`

---

## Failure matrix (where it breaks)

| Symptom | Layer | Typical cause | Fix |
|---------|-------|---------------|-----|
| Dummy Output | L1 or L3 conflict | No firmware / W1+W2 + px13-resume | Phase 0–1; disable resume |
| No Speaker in wpctl | L1 | UCM / firmware | brainchillz |
| Left channel only | L2 | Stock sdw-utils | `build-from-upstream.sh` |
| `error -110` after S2 | L3 | Stock tas2783 resume | `build-w1-w2.sh` |
| Speaker + no sound after S2 | L3+ | Known open issue | witness + research/ |
| `Program params -22` | L2 | Capture path | upstream series A |
| vermagic mismatch | L0/L2 | Kernel updated, modules old | `post-kernel-update.sh` |

---

## After kernel upgrade

```bash
./scripts/post-kernel-update.sh
sudo ./scripts/build-w1-w2.sh
sudo reboot
./scripts/px13-stack-check.sh
./scripts/post-s2-user-witness.sh
```

Firmware and UCM survive; **modules must be rebuilt**.

---

## Quick reference

```text
px13-stack-check.sh     → where am I / what next
build-from-upstream.sh  → L2
build-w1-w2.sh          → L3
post-s2-user-witness.sh → KPI-U pass/fail
CLEAN-RESTART-20260712  → disaster recovery
```

# Patches

English · maintainer-oriented summary. Patch files live in `patches/`; base driver fixes in `upstream/`.

---

## Base driver series (`upstream/`)

Applied by `scripts/apply-upstream-patches.sh`, built by `scripts/build-from-upstream.sh`.

| Series | File(s) | What it fixes |
|--------|---------|---------------|
| **A — capture** | `series-A-capture/` | Skip invalid capture hw_params when codec has no source ports |
| **B — firmware** | `series-B-firmware/` | FW download retry, wait in hw_params, reload after system sleep |
| **C — channel map** | `series-C-channel-map/` | One playback channel per TAS2783 (stereo L/R on dual amps) |

These address cold-boot stereo, intermittent FW `-110`, and capture `-22` log noise on speaker-only topologies.

---

## Patch 0001 — post-sleep playback reinit

**File:** `patches/0001-tas2783-post-sleep-fw-reinit-on-hw-params.patch`  
**Build:** `scripts/build-upstream-post-sleep-reinit.sh`  
**Module:** `snd-soc-tas2783-sdw.ko`

### What it fixes

Internal speakers **silent after suspend** while PCM runs, firmware reports loaded, and `tas2783_fw_reinit()` returns success from the resume path.

### Why it exists

After s2idle, the first firmware reinitialization runs during SoundWire resume — **before** any real playback stream is opened. Register state and logs look correct, but the SmartAmp playback path stays non-functional.

Running the **same** `fw_reinit()` once at the **first `hw_params`** (when clocks, DAPM, and stream ports are set up) restores audible stereo.

### How to reproduce the bug

1. Install base series A+B+C (without 0001).
2. Cold boot: speakers work.
3. `systemctl suspend`, wake, wait ~10 s.
4. `speaker-test -D hw:1,2 -c 2 …` — PCM runs, **no sound**.
5. `journalctl -k -b 0 | grep tas2783` — FW reload `ret=0`, no obvious error.

### Why this solution

- **Event-driven:** hook at first playback `hw_params`, not a fixed sleep timer.
- **One-shot flag** `resume_playback_reinit_pending` — cleared after the second reinit; no overhead on every stream open.
- **Minimal:** reuses existing `tas2783_fw_reinit()`; no userspace daemon.

---

## Patch 0002 — AMD SoundWire resume IRQ kick

**File:** `patches/0002-amd-soundwire-resume-irq-kick.patch`  
**Build:** `scripts/build-amd-soundwire-resume.sh`  
**Module:** `soundwire-amd.ko`

### What it fixes

After s2idle, SoundWire codecs may not reach **ATTACHED** because a pending interrupt status bit is set but the IRQ worker never runs.

### Why it exists

On ACP7.x, `ACP_EXTERNAL_INTR_STAT & manager_mask` can be non-zero immediately after the manager returns to D0, while the shared PCI IRQ handler is not invoked. Enumeration stalls until a second suspend cycle or a full PCI reset.

### How to reproduce the bug

1. Stock or partially patched kernel without 0002.
2. Suspend/resume.
3. `ls /sys/bus/soundwire/devices/` — missing or stale slaves; card may be incomplete.
4. `/proc/interrupts` — SoundWire IRQ count unchanged despite pending STAT.

### Why this solution

Schedule the existing `amd_sdw_irq_thread` work item when masked status is pending after D0 — same handler path as a normal interrupt, without PCI unbind/bind userspace reset.

---

## Userspace (external)

| Component | Source |
|-----------|--------|
| TAS2783 firmware blobs | [brainchillz PX13 fix](https://github.com/brainchillz/asus-proart-px13-linux-speaker-fix) |
| Base UCM | same repo |
| Internal mic UCM overlay | `scripts/install-ucm-px13.sh` |

---

## Investigation archive

Full experiment log, rejected hypotheses, and reproducibility scripts: branch **`resolution/bruteforce`**.

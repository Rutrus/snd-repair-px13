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

## Patch 0001b — post-resume dual-trigger fw_reinit (Case A′)

**Apply:** `scripts/apply-0001b-post-resume-fw-reinit.py` (after 0001)  
**Build:** `scripts/build-upstream-post-sleep-reinit.sh`  
**Module:** `snd-soc-tas2783-sdw.ko`  
**Marker:** `snd_repair post-resume fw_reinit`

### What it fixes

0001 assumes a post-sleep **`hw_params`** that modern PipeWire does not always deliver when the PCM stays open across s2idle (Firefox playing, Broken-pipe recover). Same mute as Case A, but the 0001 gate never fires.

### Model

```text
resume → first fw_reinit → pending=true → schedule post_resume work (~100 ms)
                │                              │
           hw_params ──────────────────────────┤
                │                              │
                └──────── run_once() ←─────────┘
```

`tas2783_run_post_resume_fw_reinit_once()` claims pending once (requires ATTACHED + `fw_dl_success`); the other trigger is a no-op.

### Why ~100 ms

Not a physical magic constant — approx. `HZ/10` settle so the resume pipeline (including 0003b attach) can finish. Either trigger may win.

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

## Patch 0003 — force ping after resume D0

**File:** `patches/0003-amd-soundwire-resume-force-ping.patch`  
**Build:** `scripts/build-amd-soundwire-resume.sh` (applies 0002 then 0003)  
**Module:** `soundwire-amd.ko`  
**Marker:** `snd_repair resume enum kick`

### What it fixes

When `ACP_EXTERNAL_INTR_STAT` is **0** after D0, patch 0002 is a no-op and slaves stay `UNATTACHED` (`-110`). AMD has no Intel-style `start_bus_after_reset()`.

### Why this solution

Always run `amd_sdw_read_and_process_ping_status()` + `schedule_work(amd_sdw_work)` after D0 (and still kick IRQ work if any latch is set). Logs `stat/pend/sc07/sc811` for PASS/FAIL contrast.

---

## Patch 0003b — delayed resume enum re-kick (H7)

**File:** `patches/0003b-amd-soundwire-resume-delayed-enum-kick.patch`  
**Build:** `scripts/build-amd-soundwire-resume.sh` (applies 0002 → 0003 → 0003b)  
**Module:** `soundwire-amd.ko`  
**Marker:** `snd_repair resume enum kick delayed`

### What it fixes

0003 alone still fails when the immediate ping races ACP/bus settle (`stat=0`, slaves stay UNATTACHED). Case B — not TAS W8.

### Why this solution

Keep the immediate kick, then schedule `delayed_work` at **40 ms** for a second ping+status pass. Same race class as W8, one layer down (AMD SDW). Logs a second line with `kick delayed`.

Uses **static** `delayed_work` tables keyed by manager instance (overlay builds against stock `sdw_amd.h` and cannot extend `struct amd_sdw_manager`).

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

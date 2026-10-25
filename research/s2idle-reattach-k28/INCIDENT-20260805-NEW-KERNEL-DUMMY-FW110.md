# Incident postmortem — new kernel boot: mute + touchpad scroll + left-only (2026-08-05)

**Host:** colosal3 · PX13 HN7306EAC · `7.0.0-29-generic` (**new ABI**)  
**Window:** boot `2026-08-05 08:45:32` → snapshot `08:49`  
**Overlay:** **absent** on this kernel — stock `snd-soc-tas2783-sdw` / `soundwire-amd` (0001/0001b/0002/0003/0003b **MISSING**)  
**Staging:** only `build/staging/7.0.0-28-generic` present; **no** staging for `-29`  
**Snapshot:** `/tmp/snd-repair-postmortem-20260805/`  
**User symptom:** at first no sound and touchpad scroll gestures broken; later touchpad recovered and **left speaker** only; right still expected dead  
**Language:** English (canonical research note)

---

## Verdict

Three independent layers on first boot of `7.0.0-29-generic`:

1. **Product overlay not installed for the new kernel** → stock drivers; no 0003b / 0001b.
2. **TAS `:b` FW download failed `-110` at 08:45:39** → storm `error playback without fw download` / ASoC `-22`; PipeWire fell to **Dummy Output** / `auto_null`. Amp `:8` path later usable → matches **left-only** recovery.
3. **Touchpad (ASCF1A03 / hid-multitouch):** probe warning + libinput “Touch jump” flood early in session; gestures recovered without audio fix (I2C HID / libinput race, not SDW).

---

## Evidence

### Kernel

| Check | Result |
|-------|--------|
| SDW now | **Attached** ×3 |
| Overlay `/lib/modules/7.0.0-29-generic/updates/snd_repair` | **absent** |
| Live modules | in-tree under `kernel/…` — markers **MISSING** |
| 08:45:39 | `trf … failed:-110`; `:b` `FW download failed: -110`; `fw with no files` |
| After | `:b` `error playback without fw download` + `hw_params` `-22` (repeated) |
| 0003b / 0001b this boot | **not present** (stock) |

```text
ago 05 08:45:39 soundwire …: trf on Slave 1 failed:-110 write addr 8088 …
ago 05 08:45:39 slave-tas2783 …:b: FW download failed: -110
ago 05 08:45:39 slave-tas2783 …:b: fw with no files
ago 05 08:45:40 slave-tas2783 …:b: error playback without fw download
ago 05 08:45:40 … ASoC error (-22): at snd_soc_dai_hw_params() on tas2783-codec
```

### Userspace (08:49)

| Check | Result |
|-------|--------|
| Default sink/source | **`auto_null` / `auto_null.monitor`** |
| `wpctl` sinks | **Dummy Output** `*` only — no Speaker/Headphones nodes |
| Configured defaults | still prefer `…HiFi__Speaker__sink` / Mic (orphaned) |
| Jack controls | present; Jack = off |

### Touchpad

| Check | Result |
|-------|--------|
| Device | `ASCF1A03:00 2808:0357 Touchpad` via `hid-multitouch` |
| Probe | `Returned feature report did not match the request` |
| Userspace | libinput `Touch jump detected and discarded` (rate-limited) from ~08:45:48 |

---

## Causal chain

```text
boot 7.0.0-29-generic
    → no updates/snd_repair for this ABI          (overlay gap)
    → stock soundwire/tas2783
    → SDW attach race / FW xfer -110 on :b
    → :b no FW → hw_params -22 storm
    → PipeWire: Dummy Output / auto_null           (no sound)
    → :8 may load later → left speaker only        (asymmetric)
    → parallel: hid-multitouch feature mismatch
    → libinput touch jumps → scroll gestures flaky
    → touchpad recovers (time / libinput settle)
```

---

## Recovery applied

Session-local recoveries (PW restart, sink flip) **cannot** load overlay patches already missing from disk.

**Required for this boot class:**

1. Build + install overlay for `7.0.0-29-generic` (`snd` / `snd-repair build` + `sudo install-modules`).
2. **Reboot** once so live modules come from `updates/snd_repair`.
3. Then runtime reset without reboot if mute returns while markers OK (`snd` reset path).

**Reboot required?** yes to activate new overlay on `-29`.  
**PCI reset used?** no.

---

## Product implications

| Do | Do not |
|----|--------|
| After every kernel upgrade: `snd` (or `snd-repair status`) before relying on audio | Assume `-28` overlay applies to `-29` |
| Treat Dummy Output + FW `-110` on new ABI as **missing overlay / FW race**, not Scenario 2 alone | SDW rebind as first fix (HiFi collateral) |
| Document touchpad jump as **correlated boot glitch**, separate from TAS | Blame scroll loss on PipeWire |

**CLI:** `scripts/snd` → `~/.local/bin/snd` (check → install with sudo → runtime reset).  
See also: [INCIDENT-20260803-POSTMORTEM-S2-HIFI-JACK.md](INCIDENT-20260803-POSTMORTEM-S2-HIFI-JACK.md).

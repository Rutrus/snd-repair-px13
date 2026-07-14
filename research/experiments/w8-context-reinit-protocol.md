# W8 — context-triggered second `fw_reinit` (time vs pipeline)

English (canonical). **Goal:** same `tas2783_fw_reinit()` code, different **when** — distinguish temporal stabilization from ASoC/SoundWire execution context.

Prerequisite: W5 reproducible, W6@3000 PASS, W7 installed.

---

## Evidence summary (upstream-ready)

| Fact | Confidence |
|------|------------|
| FW downloads OK after S2 | Very high |
| `init_seq` + DAPM run | Very high |
| PCM / `hw_ptr` / DMA OK | Very high |
| Failure localized to TAS2783 (not PW / RT721) | Very high |
| Later second `fw_reinit()` restores audio | Very high |
| First resume-path `fw_reinit()` functionally insufficient | High |
| **"Too early" exclusively** | **Not yet** — time vs context still open |

Demonstrated:

> A `fw_reinit()` during resume fails functionally; a later one succeeds.

Not yet exclusive:

> The first reinit is too early (vs wrong context).

---

## Post-S2 timeline (maintainer diagram)

```text
system resume
 │
 ├─ SoundWire bus / manager resume
 ├─ TAS2783 update_status(ATTACHED)
 │    └─ W2 fw_reinit()          ← functional FAIL (silent amp path)
 │
 ├─ userspace / PipeWire settle
 ├─ first hw_params / port_prep / DAPM POST_PMU
 │
 ├─ [optional] deferred_work (W6 timer)
 │    or event trigger (W8)
 │    └─ 2nd fw_reinit()          ← PASS (audible)
 │
 └─ playback OK
```

---

## Trigger modes (one at a time)

| Mode | Module param | Fires on | Artificial delay |
|------|--------------|----------|------------------|
| **timer** | `deferred_reinit_ms=N` | `delayed_work` | N ms |
| **hw-params** | `deferred_reinit_on_hw_params=1` | First `hw_params` | **0 ms** |
| **port-prep** | `deferred_reinit_on_port_prep=1` | First SDW PRE_PREP | **0 ms** |
| **dapm-pmu** | `deferred_reinit_on_dapm_pmu=1` | First FU21 POST_PMU | **0 ms** |

W2 always runs first reinit on resume (reproduces bug). W8/W6 add **second** reinit only.

No `.trigger` hook in this driver — DAPM POST_PMU is the closest “stream power” milestone.

---

## Build

```bash
sudo ./scripts/build-w8-context-reinit.sh
sudo reboot
```

---

## Experiment order

### 1. Timer 1500 ms (close timing hypothesis)

```bash
sudo ./scripts/w8-context-reinit-test.sh --mode timer --delay 1500
```

If PASS with 0/3000 already known → **stop delay sweep** (no need for 1175 vs 1380 ms).

### 2. Context modes (one S2 each)

```bash
sudo ./scripts/w8-context-reinit-test.sh --mode hw-params
sudo ./scripts/w8-context-reinit-test.sh --mode port-prep
sudo ./scripts/w8-context-reinit-test.sh --mode dapm-pmu
```

Or full sweep:

```bash
sudo ./scripts/w8-context-sweep.sh
```

### 3. W7 timeline each cycle

```bash
./scripts/w7-ts-capture.sh --last-s2
```

Compare `w2_fw_reinit_end` ms vs `first_hw_params` vs `w8_fw_reinit_start`.

---

## Interpretation matrix

| Pattern | Conclusion |
|---------|------------|
| timer 1500+ PASS, all event modes FAIL | Pure stabilization window → upstream `delayed_work` |
| **hw-params PASS at 0 ms** | **Pipeline milestone** → upstream hook in `hw_params` (cleaner than sleep) |
| port-prep PASS, hw-params FAIL | SDW port prep is the gate |
| dapm-pmu PASS | DAPM ordering — defer until POST_PMU |
| timer PASS, all events FAIL | Context of workqueue/process matters |
| all FAIL except W5 manual | Automated path bug; W5 remains control |

---

## Upstream patch direction (after W8)

**Preferred (if hw-params or dapm passes):** schedule second `fw_reinit` on first playback `hw_params` after system sleep — no fixed sleep.

**Fallback (if only timer passes):** `delayed_work` with documented minimum window (e.g. ≥1500 ms from W7 anchor — justify with data, not guess).

**Never upstream as-is:** hardcoded 3000 ms without W7/W8 evidence.

---

## References

- [w5-w6-results-20260714.md](w5-w6-results-20260714.md)
- [w5-reproducibility-protocol.md](w5-reproducibility-protocol.md)
- [upstream-draft-tas2783-post-s2-reinit.md](../upstream/upstream-draft-tas2783-post-s2-reinit.md)

# Phase 6 hypotheses

Reorganized for **state transition analysis** — maintainer-facing framing.

---

## H1 — RT721 timeout triggers the cascade (strongest)

```
rt721 resume → init timeout → PM -110 → bus/slaves broken
```

**Evidence:** run 0001 @0ms — rt721 timeout before `:8` unattached; boot #40 same pattern.

**Falsify:** PASS run where rt721 times out but attach still succeeds.

---

## H2 — SDW framework abandons attach too early (strong)

After PM resume failure, does the core **retry** enumeration or **stop**?

**Evidence:** boot #40 post-PCI — probe but permanent `unattached`; no later attach in kmsg.

---

## H3 — Temporal races (split)

### H3a — PM ↔ FW

Kernel still resuming while FW reload path runs (or does not run because Unattached).

### H3b — FW ↔ PipeWire

Userspace opens PCM **before** attach/fw ready → `playback without fw` loop.

**Evidence run 0001:** Speaker in wpctl @0–1s while kernel already FAIL; `playback without fw` @+3s.

---

## H4 — ACP70 / platform timing sensitivity

Variable ACP/SMU resume latency; IO_PAGE_FAULT on `snd_pci_ps` correlates (not proven causal).

Record `load1` per run (run 0001: 1.12).

---

## H5 — Aggressive fixed timeout (new)

Hardware may be **slow** not **broken**:

```
timeout = 100 ms
hardware = 103 ms  →  FAIL branch
```

Would explain ~38% PASS / ~62% FAIL without permanent hardware fault.

**Test:** Compare rt721 init duration in PASS vs FAIL chronologies (ms from resume). Look for cluster just above threshold.

---

## Formal composite (Phase 6)

```
PASS :=
  attached(:8)
  ∧ fw_loaded(:8)
  ∧ speaker_present
  ∧ pcm_running      # STREAM READY — ALSA RUNNING or successful trigger
  ∧ speaker_test_ok

FAIL := pm_fail ∧ ¬attached   # hard kernel branch

WARN := everything else
```

---

## Investigation order (first divergence only)

1. Merge **hardware + kernel + userspace** event streams by `offset_ms`.
2. Compare PASS vs FAIL with `phase6-first-divergence.sh`.
3. **Stop at first diff** — later events may be consequences.
4. Only then choose patch layer (RT721 / SDW / ACP / PM / userspace).

---

## On hold (Phase 5)

| Item | Status |
|------|--------|
| TAS2783 0003 FW reload | Insufficient without Attached |
| px13 recovery | Mitigation; not root cause |

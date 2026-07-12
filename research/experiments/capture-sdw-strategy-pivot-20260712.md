# Capture SDW — strategy pivot (2026-07-12)

English (canonical). **Dual-lane:** functional laptop first; rigorous root cause in parallel.

Prior: [capture-triple-probe-case-b-20260712.md](capture-triple-probe-case-b-20260712.md) · [capture-sdw/README.md](../capture-sdw/README.md)

---

## End goal (do not lose sight)

**Laptop works after S2** — play + mic + PW, no manual steps. Not “elegant kernel story” alone.

---

## Knowledge table

| Topic | Status |
|-------|--------|
| W1 IRQ resume | ✓ empirical |
| W2 TAS2783 playback FW | ✓ empirical |
| UCM / PipeWire (boot) | ✓ |
| Playback post-S2 | ✓ |
| **Capture post-S2** | **✗ only remaining functional gap** |

---

## Single regression hypothesis

```text
            SoundWire capture path (common)
                   │
     ┌─────────────┼─────────────┐
     │             │             │
 RT721 cap    SmartAmp cap    DMIC
```

Case B: all three fail → not RT721-only, not DMIC-only.

---

## Asymmetry (evidence)

```text
playback:  … → CONFIGURED → prepare → DMA  ✓
capture:   ALLOCATED → prepare → -EINVAL  ✗
           (SmartAmp: inconsistent state 0 at prepare)
```

---

## Two lanes

| Lane | Priority | Action |
|------|----------|--------|
| **Functional** | **P0** | Small working patch → test triple probe + witness `--functional` |
| **Investigation** | **P1** | Who should run **ALLOCATED → CONFIGURED** for capture after resume? |

---

## Investigation P0 (refined)

**Not:** instrument only `sdw_prepare_stream()` — that proves we arrive **late**.

**Yes:** instrument **ALLOCATED → CONFIGURED** and every state transition.

| Question | Meaning |
|----------|---------|
| **H1** | Capture never reaches CONFIGURED — configure path never runs post-S2 |
| **H2** | Capture reaches CONFIGURED then regresses to ALLOCATED — who undoes it? |

### Who can perform ALLOCATED → CONFIGURED?

Stock kernel: **`sdw_stream_add_slave()`** sets CONFIGURED when first slave joins stream (via codec `set_stream` during hw_params / machine bring-up).

Trace must show **`caller=%pS`** on that transition for **dir=capture** vs **dir=playback** on same post-S2 boot.

Tool: SDWCAP patch — [../capture-sdw/patches/0001-sdwcap-stream-state-trace.patch](../capture-sdw/patches/0001-sdwcap-stream-state-trace.patch)

---

## Causal chain (today)

```text
resume → W1 ✓ → W2 ✓ → playback ✓
                      → capture stream ALLOCATED
                      → (no CONFIGURED)
                      → sdw_prepare_stream → -EINVAL
```

Peeling layers of one S2 recovery sequence — not independent random bugs.

---

## Frozen

W1, W2, UCM — no extension unless functional lane requires it.

---

## References

- Instrumentation: [../capture-sdw/INSTRUMENTATION-PLAN.md](../capture-sdw/INSTRUMENTATION-PLAN.md)
- Codec ops diff: `scripts/compare-codec-pm-ops.sh`
- Queue: [../MAKE-IT-WORK.md](../MAKE-IT-WORK.md)

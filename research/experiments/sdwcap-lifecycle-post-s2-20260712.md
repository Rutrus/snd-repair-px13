# SDWCAP capture lifecycle post-S2 — decisive witness

**2026-07-12 14:48** · boot with SDWCAP · S2 via `systemctl suspend`

Artifacts: `validation/sdwcap-lifecycle-post-s2-20260712-144803/`

Script: `scripts/sdwcap-lifecycle-post-s2.sh`

---

## Question

> What prevents capture streams from returning to CONFIGURED after S2?

SDWCAP answers the Case A vs Case B fork in one run.

---

## Userspace results (post-S2, PipeWire stopped)

| Probe | Result |
|-------|--------|
| `speaker-test hw:1,2` | EBUSY (-16) — device still held (PW restart race; not lifecycle evidence) |
| `arecord hw:1,1` RT721 | opens, **EIO on pcm_read** |
| `arecord hw:1,3` SmartAmp cap | **EINVAL hw_params** |
| `arecord hw:1,4` DMIC | opens, **EIO on pcm_read** |

---

## SDWCAP: two capture streams, two failure classes

Both named `subdevice #0-Capture` but different `stream=` pointers.

### Stream `00000000c5bd5e61` — RT721 multicodec path (hw:1,1)

```text
ALLOCATED → CONFIGURED   caller=rt721_sdca_pcm_hw_params [rt721]
         → PREPARED       caller=asoc_sdw_prepare
         → ENABLED        caller=asoc_sdw_trigger
         → DISABLED → DEPREPARED → RELEASED   caller=amd_sdw_hw_free [soundwire_amd]
sdw_program_params ret=0
```

**Verdict: Case B** — lifecycle reaches ENABLED; userspace still gets EIO on read.

CONFIGURED **does** happen post-S2 for this stream. The regression is **runtime data path**, not missing state transition.

### Stream `000000004f6ebbf4` — SDW1-PIN4-CAPTURE-SmartAmp (hw:1,3)

```text
prepare_enter state=0:ALLOCATED
prepare_fail (no slave/port yet)
inconsistent state state 0
ALLOCATED → RELEASED   caller=amd_sdw_hw_free [soundwire_amd]
```

**No `CONFIGURED` transition. No `tas_sdw_hw_params` caller.**

**Verdict: Case A** — prepare from ALLOCATED without prior CONFIGURED.

Contrast playback post-S2 (prior witness): `tas_sdw_hw_params` performs ALLOCATED → CONFIGURED.

**Missing component for SmartAmp capture:** same class of hw_params/add_slave that playback gets from TAS2783 SDW driver — never invoked on capture direction after S2.

---

## Refined answer

The problem is **not one monolithic capture bug**. Post-S2 capture splits into:

| Path | CONFIGURED post-S2? | Symptom | Class |
|------|---------------------|---------|-------|
| RT721 stream (`c5bd5e61`) | **Yes** (rt721 hw_params) | EIO read | **B** — DMA/IRQ/data after ENABLED |
| SmartAmp PIN4 (`4f6ebbf4`) | **No** | EINVAL prepare | **A** — lifecycle gap before CONFIGURED |
| DMIC (`hw:1,4`) | not SDWCAP-visible | EIO read | likely **B** (PDM/DMA); separate from PIN4 |

`amd_sdw_hw_free → RELEASED` appears on **both** streams after failed or completed sessions. For SmartAmp capture it is the **only** transition after ALLOCATED. For RT721 it follows a **complete** ENABLED cycle — teardown, not root cause of missing CONFIGURED.

---

## What to stop investigating

W1 ATTACH, W2 TAS playback FW, UCM, PipeWire topology, GNOME discovery — sufficient evidence these layers are not the functional blocker.

---

## Next steps (ordered)

1. **Lane B — SmartAmp capture Case A (P0 for patch target):**
   - Why does `tas_sdw_hw_params` run for playback but not capture post-S2?
   - Trace machine graph: `SDW1-PIN4-CAPTURE-SmartAmp` link prepare order vs RT721 link.

2. **Lane B — RT721 Case B:**
   - ENABLED + `sdw_program_params ret=0` but EIO: compare boot vs post-S2 DMA/period IRQ / hwptr (reuse W2b stall methodology on capture direction).

3. **Lane A opportunistic:**
   - Force capture stream re-configure (re-run codec hw_params or avoid premature `amd_sdw_hw_free` on ALLOCATED SmartAmp stream) and re-run triple probe + `--functional` witness.

---

## KPI impact

Desktop shows mic nodes ✓; functional capture ✗. Confirmed **runtime stream lifecycle**, not discovery.

Portable KPI remains **FAIL** until both SmartAmp capture CONFIGURED path and RT721/DMIC read path are fixed.

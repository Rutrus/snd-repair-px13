# E04 run protocol — first informative recovery

English (canonical). First edge with **VALID S2 witness** before recovery.

---

## Chain

```text
S0 → suspend → S2 (W2 VALID) → R04 → ALSA?
```

---

## PASS / FAIL (primary)

| Verdict | Criterion |
|---------|-----------|
| **PASS** | `witness_playback_alsa` OK (`plughw:1,2`) |
| **FAIL** | ALSA playback still broken |

PipeWire, `pactl`, dummy sink: **observations only** — not PASS/FAIL.

---

## R04 moments (informative)

| Moment | What to see |
|--------|-------------|
| **M1** | Platform `amd_sdw_manager.1` **unbound** (gone from driver sysfs) |
| **M2** | **bind** → platform back; kernel shows manager **probe** activity |
| **M3** | RT721 **ATTACHED** (sysfs `status` or journal) |

Logged as `R04-M1/M2/M3` in script output and edge report.

---

## Post-PASS: one suspend

If **PASS**, automatically (disable: `RESOLUTION_SUSPEND_ONCE=0`):

```text
PASS → suspend once → ALSA still OK?
```

Answers: *does R04 only repair current state, or make the system suspendible again?*

---

## Interpretation

| Outcome | Meaning |
|---------|---------|
| **PASS** | Manager `probe()` may do what `pm_resume()` does not → narrow research |
| **FAIL** | L2 unlikely sufficient → focus L4/L5 (PCI/PM/firmware) |
| **PASS + Suspend-once fail** | Repairs once but not durable across suspend |
| **PASS + Suspend-once pass** | Strong workaround candidate |

---

## Run

```bash
# Full cycle (from S0):
sudo ~/snd_repair/resolution/scripts/edge-cycle.sh E04

# Already in S2 after s2-reproduce (no second suspend):
sudo ~/snd_repair/resolution/scripts/edge-cycle.sh E04 --from-s2
```

Expected prediction (research): **FAIL** — STAT1 pending without INTx delivery is below manager reprobe.

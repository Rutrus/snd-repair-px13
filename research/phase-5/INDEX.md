# Phase 5 — Kernel contract investigation (suspend lifecycle)

> **Branch:** `research/suspend-lifecycle`  
> **Status:** active — **no new product patches** until information gain is proven  
> **Phase 4 outcome:** three root causes fixed (capture, ch_map, boot FW); suspend `:8` remains  
> **Phase 5 goal:** find **which layer contract is broken**, not add `usleep_range()` retries

English (canonical). Spanish summary: [`../es/FASE-5-INDICE.md`](../es/FASE-5-INDICE.md)

---

## Principle

We have demonstrated *what* fails (`:8 done=0`, `-110`, Dummy Output).  
Phase 5 asks *why the framework allows that state* — the property SoundWire/ASoC/ACP should guarantee and does not on resume.

---

## Parallel tracks

| ID | Track | Question | Document |
|----|-------|----------|----------|
| **T01** | State machine | What are all states and transitions boot → suspend → resume → Dummy? | [T01-state-machine.md](tracks/T01-state-machine.md) |
| **T02** | PM callbacks | Does `fw_ready()` / attach run again on resume? | [T02-pm-callbacks.md](tracks/T02-pm-callbacks.md) |
| **T03** | Ownership | Who owns `sdw_slave`, `tas_priv`, `fw_dl_success`, streams after PM? | [T03-ownership.md](tracks/T03-ownership.md) |
| **T04** | Codec comparison | What do CS35L56 / RT13xx drivers do on resume that TAS2783 does not? | [T04-codec-comparison.md](tracks/T04-codec-comparison.md) |
| **T05** | Resume ordering | Timestamps: ACP alive → bus ready → slave → FW start/end | [T05-resume-ordering.md](tracks/T05-resume-ordering.md) |
| **T06** | ACP70 resume | Boot vs resume path in `amd_manager` / `ps-sdw-dma` — same state? | [T06-acp70-resume.md](tracks/T06-acp70-resume.md) |
| **T07** | Invariants | When do `:8 done=1` ↔ Speaker, `:8 fail` ↔ `:b OK` break? | [T07-invariants.md](tracks/T07-invariants.md) |
| **T08** | FW binary diff | `1714-1-8.bin` vs `1714-1-B.bin` — structural diff only | [T08-firmware-diff.md](tracks/T08-firmware-diff.md) |
| **T09** | Automation | N× suspend loop → failure rate, correlations | [T09-automation-loop.md](tracks/T09-automation-loop.md) |
| **T10** | Upstream framing | General SoundWire/ASoC property violated (maintainer view) | [T10-upstream-framework.md](tracks/T10-upstream-framework.md) |

---

## Personal priority (T02 + T05 merged)

**Single spine investigation:** reconstruct full sequence from **ACP leaving suspend** to **first `trigger()` on TAS2783**.

→ [PRIORITY-RESUME-TRACE.md](PRIORITY-RESUME-TRACE.md)

---

## Deliverables (phase exit criteria)

1. **State diagram** with every transition labeled (who fires, which callback, stored state).
2. **Resume timeline CSV** with ms offsets for ≥10 resume events.
3. **Invariant table** — each marked always / sometimes / broken with boot id.
4. **Codec comparison note** — one page, philosophy not copy-paste.
5. **Framework hypothesis** — one sentence suitable for upstream cover letter.
6. **Only then:** minimal patch targeting the violated contract (not retry band-aids).

---

## Tools

| Tool | Purpose |
|------|---------|
| `scripts/phase5-resume-collect.sh` | One resume → timeline + wpctl + matrix row |
| `scripts/phase5-resume-stats-loop.sh` | N× suspend/resume → `validation/phase5-resume-stats.csv` |
| `templates/state-transition.csv` | Manual state machine rows |
| `templates/resume-timeline.csv` | Per-resume ms offsets |
| `templates/invariants.yaml` | Invariant definitions + test queries |

---

## Explicitly paused on this branch

- New `usleep_range` / retry-only patches (0006-style without lifecycle proof)
- Reopening capture / ch_map / UCM unless invariant T07 breaks on cold boot
- Userspace-only “fixes” without T02/T05 evidence

---

## Links

- Phase 4 state: [`../../docs/PROJECT-STATE.md`](../../docs/PROJECT-STATE.md)
- Last suspend eval: [`../SUSPEND-EVAL-2026-07-09-2240.md`](../SUSPEND-EVAL-2026-07-09-2240.md)
- Legacy tracks A–D: [`../INVESTIGATION-INDEX.md`](../INVESTIGATION-INDEX.md)

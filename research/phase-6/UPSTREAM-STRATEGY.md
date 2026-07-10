# Upstream strategy — if PASS never appears

English (canonical). Complements [UPSTREAM-REPORT-DRAFT.md](UPSTREAM-REPORT-DRAFT.md).

**Delimitation is complete** (run 0015). Missing PASS does **not** mean the investigation failed — it changes the upstream question.

---

## Three submission scenarios

| Scenario | Evidence | Upstream question |
|----------|----------|-------------------|
| **1 — Ideal** | PASS + FAIL, same 0003–0007 | *"First divergence between both paths is X."* |
| **2 — Strong (current)** | FAIL only, break localized before IRQ | *"Software path complete; where should HW programming continue?"* |
| **3 — Deterministic** | N/N FAIL (e.g. 20–30 clean-boot resumes) | *"This platform never presents first post-reset event — reproduction 100%."* |

Scenario **2 is already submittable** with conservative wording. Scenario **3** strengthens reproduction; it does not weaken the report.

---

## Key question (answer before chasing PASS forever)

> **Has there been a clean boot where kernel witness shows full re-enumeration on the first s2idle resume (`resume=1`), with 0003–0007 instrumentation, with no PCI reset, no `px13-audio-rebind`, and no other userspace recovery?**

### Current answer (as of run 0015)

| Criterion | Status |
|-----------|--------|
| Kernel witness PASS (`irq_handler` → `completion`, no `wait_init_timeout`) with 0003–0007 | **Not observed** |
| Instrumented FAIL-1 on clean boot `resume=1` | **Yes** — 0010, 0012, 0013, 0014, **0015** (repeated) |
| Userspace audio OK while kernel FAIL | Possible — FACT 9 |
| Early run 0002 `kernel_branch=PASS` | Pre-0003–0007 AMD trace; not comparable golden diff |

**Working hypothesis:** kernel resume path may be **deterministic FAIL** on this HW/FW/kernel combo; intermittent "working audio" may be **userspace recovery**, not a missing kernel PASS.

If after **20–30** masked-rebind clean-boot attempts there is still **zero** kernel witness PASS, document explicitly:

> No correct kernel resume path was observed with this instrumentation and configuration.

Then reframe upstream from *"why do PASS and FAIL diverge?"* to:

> *"Why does this platform never generate the expected first interrupt after `manager_reset` on s2idle resume?"*

---

## Alternative contrast (if kernel PASS does not exist)

Do not compare PASS vs FAIL kernel paths. Compare:

```text
FAIL (kernel witness)
    ↓
userspace recovery (rebind / PCI reset / PipeWire cycle)
    ↓
audio works again
```

That explains intermittent **user-visible** behaviour without a kernel PASS. Investigation scope stays kernel; userspace is the recovery layer, not the fix.

**Procedure to confirm:**

```bash
sudo systemctl mask --runtime px13-audio-rebind.service
# suspend → sm → note FAIL-1
# do NOT run rebind — audio should stay broken
# if audio "fixes itself" anyway, find which service did (journal, systemctl)
```

---

## PASS hunt protocol (bounded effort)

```bash
sudo reboot
./scripts/phase6-hunt.sh post-reboot --notes run-17-attempt
systemctl suspend
./scripts/phase6-hunt.sh post-suspend
```

Log: `validation/phase6-hunt-log.csv` (kernel witness per attempt).

Manual steps (equivalent):

**Stop chasing PASS when:**

- One kernel witness PASS captured → fill golden diff (scenario 1), or
- **≥20** clean-boot attempts, **0** PASS → declare scenario 3, submit scenario 2 report.

Do **not** add traces during the hunt.

---

## What to submit without PASS (scenario 2/3)

Use [UPSTREAM-REPORT-DRAFT.md](UPSTREAM-REPORT-DRAFT.md) as-is:

- **Observed** chain (manager_reset → … → STAT=0 → no handler → timeout)
- **Not demonstrated** (HW never fires, etc.)
- Reproduction: `systemctl suspend` / s2idle
- N_FAIL count when hunt completes
- Ask AMD to review post-`device_state_D0` HW sequencing on ACP70

---

## Pattern stability (why scenario 3 is plausible)

Runs 0004–0015 with increasing instrumentation: the **essential shape unchanged** — full software path, `STAT=0`, no handler, FAIL-1 on clean `resume=1`. Suggests platform-deterministic behaviour, not sampling noise.

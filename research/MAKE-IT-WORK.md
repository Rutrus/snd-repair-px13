# Make it work — resume audio KPI (Branch A)

English (canonical). **Primary project objective** as of 2026-07-12.

> Investigation was not wasted — it collapsed the search space. **KPI unchanged:** after `systemctl suspend` → resume, **Speaker works** (PCM2 `hw_params` PASS, no reboot).

**Root-cause doc (Branch B):** [UNIFIED-CAUSAL-MODEL.md](UNIFIED-CAUSAL-MODEL.md) · **C1 closed:** [experiments/q3.1-c1-boundary-witness-20260712.md](experiments/q3.1-c1-boundary-witness-20260712.md)

---

## Two branches (explicit)

| Branch | Question | Priority |
|--------|----------|----------|
| **A — Make it work** | What minimal intervention restores audio after S2? | **P0** |
| **B — Root cause** | Why does legacy IRQ not reach `acp63_irq_handler()` on resume? | **P1** (upstream) |

Branch A experiments **inform** Branch B (a working workaround is a causal probe). Branch B evidence **does not** replace Branch A when the laptop still has no sound.

Accept ugly fixes: manual worker kick, forced re-enumeration, codec re-init, module reload sequences — **if they restore playback**.

---

## KPI (unchanged)

```text
echo mem > /sys/power/state   # or systemctl suspend
↓
resume
↓
aplay -D hw:1,2 …  OR  speaker-test  →  PASS (no Dummy Output)
```

Matrix gate: ≥6/6 real S2 cycles in `validation/fw-matrix.csv` without reboot.

---

## Experiment queue — ranked by “probability of fixing the laptop”

Score: science value vs fix probability (user rubric 2026-07-12).

| ID | Intervention | Fix prob. | Science | Status / next |
|----|--------------|-----------|---------|----------------|
| **W1** | **0006a** — `schedule_work(amd_sdw_irq_thread)` when `STAT & manager_mask` | ★★★★☆ | ★★★★☆ | **Next trial** — prior run p7-0006a-d50: ATTACHED + RT721 OK |
| **W2** | Force codec path post-ATTACHED (0003 / `tas_io_init` if ATTACHED returns) | ★★★★★ | ★★★★☆ | Blocked until ATTACHED; try **after W1** |
| **W3** | Full SoundWire re-enumeration post-resume (salvage/rescue top-down) | ★★★★☆ | ★★★☆☆ | Negative history in bruteforce — retest **after W1** localizes |
| **W4** | More IRQ instrumentation only | ★☆☆☆☆ | ★★★★★ | **C1 closed** — deprioritize unless W1–W3 fail |

Do **not** treat W1 as upstream fix — treat as **workaround trial** + causal proof that downstream (Q2 chain) is sufficient when worker runs.

---

## W1 protocol — 0006a trial (recommended next)

**Hypothesis:** If worker is kicked when STAT&mask=0x4, ATTACHED returns → `io_init` → FW → PCM2 OK.

**Build** (Phase 6 base + 0006a experiment):

```bash
sudo ./scripts/build-phase6-amd-trace.sh   # if not already
sudo ./scripts/build-phase7.sh --experiment validate-manager-mask
sudo reboot
```

**Test:**

```bash
systemctl suspend && sleep 5
aplay -D hw:1,2 /usr/share/sounds/alsa/Front_Center.wav   # or witness script
./scripts/q3-sdw-reattach-collect.sh --label w1-0006a
journalctl -k -b 0 | grep -E 'ATTACHED|completion|0006a|schedule_work|fw_ready|hw_params'
```

**Pass:** ATTACHED + playback OK same boot after S2.  
**Fail:** still -110 / EINVAL → try W3 or escalate salvage.

Prior witness: [phase-7/experiments/0006a-run-p7-d50.md](phase-7/experiments/0006a-run-p7-d50.md).

---

## W2 protocol — codec path (after ATTACHED)

Only if W1 (or other) restores ATTACHED:

- Retest upstream series B **0003** (invalidate + fw_reinit on ATTACHED).
- Or minimal hack: force `tas_io_init()` when `status==ATTACHED` after resume (new patch — last resort).

Without ATTACHED, W2 cannot help (Q2 witness).

---

## W3 protocol — brute reattach

Reuse `resolution/salvage/` or `resolution/rescue/` **only as workaround trials**, not as “maybe PCI is broken”:

- Document each run in `validation/fw-matrix.csv`.
- Success = PCM2 PASS post-S2; mechanism secondary.

---

## Branch B — what continues in parallel (low duty cycle)

- Package C1 facts for upstream (F17–F18, Phase 8.1).
- No new IRQ trace unless W1 fails or contradicts.

Entry: [q2.5-sdw-reattach/Q3.1-IRQ-CHECKPOINTS.md](q2.5-sdw-reattach/Q3.1-IRQ-CHECKPOINTS.md).

---

## Success criteria summary

| Outcome | Branch |
|---------|--------|
| Speaker works after S2 (any acceptable hack) | **A — project success** |
| Upstream understands ACP delivery gap | **B — maintainer success** |
| Both | Ideal |

Investigation phases:

```text
"Why broken?"  →  "Where broken?"  →  "What minimal step restores work?"  (+ "Why?" in parallel)
```

We are at the third question for **Branch A**, while **Branch B** has C1 closed at the Linux handler boundary.

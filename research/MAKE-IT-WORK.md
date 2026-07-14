# Make it work — resume audio KPI (Branch A)

English (canonical). **Primary project objective** as of 2026-07-12.

> **KPI-U: CLOSED (2026-07-12)** — S2×3 PASS with `post-s2-persistence-run.sh 3`. See [SOLUTION-CLOSURE-KPI-U-20260712.md](SOLUTION-CLOSURE-KPI-U-20260712.md) and [experiments/kpi-u-s2x3-pass-20260712.md](experiments/kpi-u-s2x3-pass-20260712.md).

> **KPI-K (upstream):** direct `arecord` RW fails post-S2; MMAP passes — [experiments/capture-access-matrix-20260712.md](experiments/capture-access-matrix-20260712.md). Not user-blocking.

**Dual lanes:** [capture-sdw/README.md](capture-sdw/README.md) — functional fixes (P0) parallel to SDW investigation (P1).

**Root-cause doc (Branch B):** [UNIFIED-CAUSAL-MODEL.md](UNIFIED-CAUSAL-MODEL.md) · **W1 witness:** [experiments/w1-0006a-partial-20260712.md](experiments/w1-0006a-partial-20260712.md) · **W2 detail:** [make-it-work/README.md](make-it-work/README.md)

---

## Two branches (explicit)

| Branch | Question | Priority |
|--------|----------|----------|
| **A — Make it work** | What minimal intervention restores audio after S2? | **P0** |
| **B — Root cause** | Why does legacy IRQ not reach `acp63_irq_handler()` on resume? | **P2** (frozen until W2 fails) |

Branch B **C1 closed** at the Linux handler boundary. Do not add IRQ trace unless W2–W3 fail.

Accept ugly fixes: manual worker kick, forced FW reinit, capture stream kick — **if full card works after S2**.

---

## Dual lanes — capture (2026-07-12)

| Lane | Priority | Goal |
|------|----------|------|
| **Functional** | **P0** | Any small patch → triple probe + `--functional` PASS |
| **Investigation** | **P1** | Who runs **ALLOCATED → CONFIGURED** for capture? ([SDWCAP](../research/capture-sdw/)) |

Do not block functional wins waiting for root cause. Do not ship “fixes” without capture KPI.

---

## KPI — full card recovery (2026-07-12)

**Protocol:** [experiments/w2-full-card-recovery-kpi.md](experiments/w2-full-card-recovery-kpi.md)

| Rule | Detail |
|------|--------|
| **Phase A / B** | Never mix — A = untouched post-resume; B = after WP restart only |
| **Persistence** | S2 ×1 / ×3 / ×10 — [post-s2-persistence-run.sh](../scripts/post-s2-persistence-run.sh) |
| **Witness KPI-U** | [post-s2-user-witness.sh](../scripts/post-s2-user-witness.sh) · [post-s2-persistence-run.sh](../scripts/post-s2-persistence-run.sh) |
| **Closure** | [SOLUTION-CLOSURE-KPI-U-20260712.md](SOLUTION-CLOSURE-KPI-U-20260712.md) |

```bash
# Single decisive run (Phase A only)
systemctl suspend && sleep 45
./scripts/post-s2-card-witness.sh --phase-a

# Only if Phase A shows PW incomplete:
systemctl --user restart wireplumber pipewire
./scripts/post-s2-card-witness.sh --phase-b
```

**Post-S2:** UCM mic fix applies to **boot/desktop discovery only**. After suspend, expect nodes in `wpctl` but **verify** with `--functional` — streams may EIO ([expectations](experiments/post-s2-expectations-after-ucm-dmic.md)).

---

## Experiment queue (2026-07-12 pivot)

| ID | Intervention | Fix prob. | Status |
|----|--------------|-----------|--------|
| **W1** | 0006a — manual `schedule_work(amd_sdw_irq_thread)` | ★★★★☆ | **Done** — frozen |
| **W2** | Force `tas2783_fw_reinit()` after system sleep | ★★★★★ | **Done** — frozen (play runtime PASS post-S2) |
| **W2b / Case C** | W1+W2, px13 off | ★★★★★ | **Playback PASS** ([Case C](experiments/w2b-prime-case-c-20260712.md)) |
| **UCM DMIC** | Internal Mic in GNOME (boot) | ★★★★☆ | **Done** — frozen ([PASS](experiments/ucm-dmic-install-pass-20260712.md)) |
| **Capture triple** | Case B — all capture fail | ★★★★★ | **Done** ([witness](experiments/capture-triple-probe-case-b-20260712.md)) |
| **Lane A functional** | Opportunistic capture fix post-S2 | ★★★★★ | **Open** — test any candidate immediately |
| **Lane B SDWCAP** | ALLOCATED→CONFIGURED trace + caller | ★★★★☆ | **Ready** — [patch](../research/capture-sdw/patches/0001-sdwcap-stream-state-trace.patch), `build-sdwcap-trace.sh` |
| **W2d** | WP restart | ★★☆☆☆ | **Closed** — PW topology OK; EIO is ALSA direct |
| W3 | px13 / PCI re-enumeration | ★★★☆☆ | **Deprioritized** — conflicts with W2; Case D only |
| W4 | More IRQ instrumentation | ★☆☆☆☆ | **Frozen** (C1 closed) |
| **W4′** | TAS2783 lifecycle + readback trace | ★★★★☆ | **Done** — identical PASS/FAIL ([summary](experiments/w4-w6-tas2783-double-reinit-20260714.md)) |
| **W5** | Second manual `fw_reinit()` post-S2 | ★★★★★ | **Reproducible** — PASS ([results](experiments/w5-w6-results-20260714.md)) |
| **W6** | Deferred 2nd reinit | ★★★★☆ | **3000 ms PASS**, 0 ms FAIL — test 1500 ms for threshold |
| **W7** | ms timeline W2/W5/playback | ★★★★☆ | Installed — capture on S2 |
| **W8** | Context 2nd reinit (hw_params/dapm) | ★★★★★ | **Active** — time vs pipeline |

**Causal tree after W1:**

```text
Resume → [W1 fixes] → ATTACHED
                            ↓
                     [W2 fixes] → force_fw_reinit() runs
                            ↓
                     [W2b fixes] → fw_ready / fw_dl_success ✓ (kernel)
                            ↓
                     [W2b′] → speaker-test without px13 contamination
                            ↓
                          PCM2 OK
```

Left side (ACP/IRQ) is **sufficient** with 0006a. W2b showed W2 leaves `:8`/`:b` at `success=1` on the **PM resume path**; px13 PCI reprobe ~11 s later left slaves UNATTACHED **without** `force_fw_reinit` — W2 may have been **overwritten**, not ineffective.

---

## Three mechanisms — do not mix

```text
(1) Resume PM path     →  often broken without patches
(2) W1 + W2 patches   →  ATTACHED + force_fw_reinit on system sleep
(3) px13 after resume →  PCI destroy/reprobe (partial ACP cold boot) — different path
```

Only **(2)** is under test in Case C. **(3)** must be off until Case C is decided. Case D tests **(2)+(3)** coexistence only.

---

## Case C — immediate priority (P0)

**Do not run Case D until Case C is complete.** No new IRQ instrumentation.

```bash
# 1. Isolate
sudo systemctl disable --now px13-audio-resume.service && sudo systemctl daemon-reload
systemctl is-enabled px13-audio-resume.service          # disabled
systemctl list-dependencies suspend.target | grep px13 || echo "clean"

# 2. S2 (W1+W2 already installed)
systemctl suspend

# 3. After resume: do nothing for 30–60 s (no manual px13, no wpctl spam)
sleep 45

# 4. KPI first — logs second
speaker-test -D hw:1,2 -c 2 -r 48000 -t sine -l 1

# 5. Only after you know pass/fail by ear:
journalctl -b -u px13-audio-resume.service --no-pager   # must be empty
journalctl -k -b 0 | grep -E 'TAS2783Q2|W2 ctx|fw download|px13-audio'
export XDG_RUNTIME_DIR=/run/user/$(id -u); wpctl status | head -30
```

| Outcome | Meaning |
|---------|---------|
| **Heard tone** | W2 works functionally — document, then run matrix A/B for attribution |
| **No tone, px13 journal empty** | W2 insufficient — use Q2 trace to classify |
| **px13 ran anyway** | Abort row — fix disable, retry |

Full matrix: [experiments/w2b-prime-matrix-protocol.md](experiments/w2b-prime-matrix-protocol.md) · px13 anatomy: [experiments/px13-audio-fix-vs-w1w2.md](experiments/px13-audio-fix-vs-w1w2.md).

---

## W2b′ — matrix reference

See [experiments/w2b-prime-matrix-protocol.md](experiments/w2b-prime-matrix-protocol.md). Cases A–C: px13 off. **Case D only after Case C.**

---

## W2b protocol — Q2 trace (done, boot #133)

Witness: [experiments/w2b-q2-trace-20260712.md](experiments/w2b-q2-trace-20260712.md).

**Valid:** W2 FW ladder `success=1` on PM resume path (12:58:08). H1–H3 rejected.  
**Invalid for KPI:** no audible test before px13; timeout at 12:58:38 is **post-px13**, not post-W2.

---

## W2 protocol — force FW reinit (partial PASS)

Witness: [experiments/w2-force-fw-partial-20260712.md](experiments/w2-force-fw-partial-20260712.md).

Confirmed loaded module: `strings` on installed `snd-soc-tas2783-sdw.ko.zst` shows `W2 ctx=tas` + `tas2783_fw_reinit`.

**One-shot build (W1 + W2):**

```bash
sudo ./scripts/build-w1-w2.sh
sudo reboot
```

**Test:**

```bash
systemctl suspend && sleep 5
speaker-test -D hw:1,2 -c 2 -r 48000 -t sine -l 1
journalctl -k -b 0 | grep -E 'W2 ctx=tas|manual_irq_schedule|ATTACHED|fw_ready'
```

**Pass:** tone audible + `W2 ctx=tas fn=force_fw_reinit` + no fw timeout on `:8`.  
**Fail:** still EINVAL → W3 or extend W2 (delayed reinit hook).

Patch: [make-it-work/patches/w2-force-fw-reinit.patch](make-it-work/patches/w2-force-fw-reinit.patch) (on upstream series B 0001–0003).

---

## W1 protocol — 0006a (done for this cycle)

Partial PASS documented. Keep 0006a in the combined W1+W2 build — ATTACHED precondition for W2.

Prior: [phase-7/experiments/0006a-run-p7-d50.md](phase-7/experiments/0006a-run-p7-d50.md).

---

## W3 protocol — brute reattach

Reuse `resolution/salvage/` or `resolution/rescue/` only if W2 fails. Success = PCM2 PASS post-S2.

---

## Branch B — low duty cycle

Package C1 for upstream (F17–F18). Entry: [q2.5-sdw-reattach/Q3.1-IRQ-CHECKPOINTS.md](q2.5-sdw-reattach/Q3.1-IRQ-CHECKPOINTS.md).

---

## Success criteria

| Outcome | Branch |
|---------|--------|
| **Full card** Phase A + persistence (S2×3/×10) | **A — project success** |
| Upstream understands ACP delivery gap | **B — maintainer success** |

We are at **one capture regression** — dual lane: ship functional fix if found; SDWCAP finds **who configures capture** (ALLOCATED→CONFIGURED in `sdw_stream_add_slave`, not prepare alone).

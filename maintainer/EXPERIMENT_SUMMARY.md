# Experiment summary (lab → patch)

English · one page for maintainers. **Full lab:** branch `resolution/bruteforce`.

Internal experiment IDs are preserved here only for traceability to the research branch.

| ID | Question | Result | One-line conclusion |
|----|----------|--------|---------------------|
| W1 | AMD IRQ / SoundWire attach after S2? | PASS | Manual IRQ schedule restores ATTACHED |
| W2 | Force FW reload on resume? | partial | ret=0 but **silent** speakers |
| W3 | DAPM sync after reinit? | FAIL | Not the differentiator |
| W4 | Register / lifecycle drift? | FAIL | Identical readback PASS vs silent |
| W5 | Second manual `fw_reinit()`? | **PASS** | **Inflection point** — same code, later works |
| W6 | Timer-delayed 2nd reinit? | PASS @ 3s | Time = readiness **proxy**, not root cause |
| W7 | Resume timeline? | data | Resume is busy; context changes over time |
| W8 | 2nd reinit at first `hw_params`? | **PASS** | **Final hook** — 0 ms delay, stereo L+R |
| Upstream module | Clean one-shot flag in driver | PASS | Reproducible from clean tree reset |

---

## Convergence

```text
Not a missing register write (W4)
Not DAPM absent (W3)
Not “wait 3 seconds” (W6 alone)
→ Same fw_reinit() when playback stream context exists (W5, W8)
```

---

## Documents on `main`

- [ROOT_CAUSE.md](ROOT_CAUSE.md)
- [DESIGN.md](DESIGN.md)
- [../PATCHES.md](../PATCHES.md)

## Documents on `resolution/bruteforce` only

- `research/experiments/` — full protocols and results  
- `research/SOLUTION-CLOSURE-TAS2783-POST-S2-20260714.md` — long-form closure  
- `research/upstream/BUG-REPORT-DRAFT.md` — email template  
- W4–W8 instrumented modules and scripts  

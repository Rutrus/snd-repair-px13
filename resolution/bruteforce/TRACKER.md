# Bruteforce tracker

English (canonical). Log **PASS** with strategy ID — one line per run.

**Branch:** `resolution/bruteforce`

---

## Results

| Date | Strategy | Campaign | Result | Notes |
|------|----------|----------|--------|-------|
| 2026-07-12 | S070 | R550 | **FALSE_PASS** | plughw opened; hw PCM dead; Dummy Output — see chain witness |
| 2026-07-12 | S010–S060 | R200–R700 | FAIL | RUN-01: partial unload (snd_sof holds soundwire) |

---

## RUN-02: S070 FALSE_PASS (2026-07-12)

`RESULT=PASS` was **invalid**:

- Witness was only `speaker-test` on ALSA — can return 0 without audible output on PX13
- No gate for RT721 attached, -110 cleared, or userspace non-dummy
- Only `BF_SETTLE_SEC=3s` before test (RT721 needs ~8–12s)
- Sysfs before/after nearly identical — **no functional S0 restoration**

**Fix applied:** strict L1–L4 witness (`hw` not `plughw`) · `witness-audio-chain.sh` · `RESULT=FALSE_PASS` / `PARTIAL` rejected by runner.

**Chain insight:** L1 PASS + L2 **hw FAIL** + plughw PASS + Dummy Output = S2 symptom. Investigation focus → DAPM / TAS2783 RUN / codec route, not PCI enumeration.

**Re-test:** `s2-reproduce.sh` → `--from-s2` (not after `--validate --phase unload`).

---

## RUN-01 interpretation (not "all ideas dead")

Several FAILs mean **strategy did not execute intended transition**, not that recovery is impossible:

- **S020/S040/S060:** `pci_reset` ran after `rmmod snd_pci_ps` → driver sysfs gone → reprobe skipped
- **S010/S030/S050:** module unload partial; `snd_soc_amd_ps` / `snd_soc_amd_acp_mach` do not exist on kernel 7.0.0-27
- **S050:** `power/state` not writable on PCI (expected) — only runtime PM ran
- **Convergence:** all reach `modprobe snd_pci_ps` + FAIL → question shifts to **what stays alive after anchor unload** (V004)

**Next:** `--validate --phase unload` on S2, then re-run bruteforce with fixed scripts.

---

## PASS template

```text
RUN-YYYY-MM-DD strategy=S020 campaign=R300 PASS hw:1,2 + real sink
Sequence: stop_pw → pci_reset → rmmod_anchor → modprobe_anchor → start_pw
```

---

## Related

- [README.md](README.md)
- Lab frozen at `resolution/lab` @ 114c067

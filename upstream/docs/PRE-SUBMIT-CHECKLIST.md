# Upstream pre-submit checklist

> **English** | [Español](es/PRE-SUBMIT-CHECKLIST.md)

Answer **yes** to all four questions before `git send-email`. Status as of 2026-07-09.

---

## Series A — capture without `source_ports`

| Question | Answer |
|----------|--------|
| **Generic?** | **Yes.** Any TAS2783 SDW whose DisCo does not advertise `source_ports` (playback-only `sink_ports`). Not DMI-specific. |
| **Respects SDW/ASoC?** | **Yes.** Does not program a non-existent DPN; aligns driver with runtime slave properties (`sdw_slave.prop`). |
| **Breaks other platforms?** | **No** when codec has real `source_ports` (mic/feedback): guard does not run. Only speaker-only topologies on shared capture dailinks. |
| **Cause in git history?** | Pre-existing: driver always assumed port 2 on capture. Run `git log -S source_ports -- sound/soc/codecs/tas2783-sdw.c` on mainline before send. |

**Maturity:** high — send first.

---

## Series B — firmware `-110` (RFC)

| Question | Answer |
|----------|--------|
| **Generic?** | **Partial.** Seen on AMD ACP70 + 2× TAS2783; mechanism (`sdw_nwrite_no_pm` timeout) plausible on other multislave SDW topologies. |
| **Respects SDW/ASoC?** | **Yes** as bounded retry; open question: codec vs SDW bus layer? |
| **Breaks other platforms?** | Low risk (retries only on `-ETIMEDOUT`/`-EAGAIN`), but not proven across wide matrix. |
| **Cause in git history?** | Investigate FW async timing race vs `hw_params`; possible AMD multislave enumeration interaction. |

**Maturity:** experimental — see `series-B-firmware/VALIDATION-TODO.md` (20–30 boots, S3, rates).

---

## Series C — multicodec playback `ch_mask`

| Question | Answer |
|----------|--------|
| **Generic?** | **Yes** for `num_codecs > 1 && ch == num_codecs` in playback. Affects AMD ACP70 (2× TAS2783) and Intel MTL (up to 4× in `soc-acpi-intel-mtl-match.c`). Does not touch intentional `step=0` (mono duplicated to N codecs). |
| **Respects SDW/ASoC?** | **Yes.** `snd_sdw_params_to_config()` documents driver may override `port_config`; `ch_maps` is standard ASoC (capture already used it with `step > 0`). |
| **Breaks other platforms?** | Designs requiring full stereo on each codec in playback (`ch != num_codecs` or single codec) keep prior behaviour. |
| **Cause in git history?** | `asoc_sdw_hw_params()` comment *"Identical data will be sent to all codecs in playback"* — deliberate for mono duplicate; `ch == num_codecs` extension is minimal fix. |

**Maturity:** high — **L/R validated** on PX13 (2026-07-09).

---

## Series D — documentation

Not a patch. Attach `INVESTIGATION-SUMMARY.md` or `expert-report.md` if maintainer requests context.

---

## Recommended send order

1. **Series A** (capture) — independent
2. **Series C** (channel map) — independent of A and B
3. **Series B** (RFC) — after `VALIDATION-TODO.md`
4. **Series D** — on request

## Before `git send-email`

- [ ] Replace `Signed-off-by: ASUS ProArt PX13 debug <snd-repair@local>` with your identity
- [ ] Rebase on `linux-next` or maintainer branch
- [ ] `checkpatch.pl` on touched files
- [ ] Confirm debug modules (ENZOPLAY/ENZODBG) are **not** in sent tree

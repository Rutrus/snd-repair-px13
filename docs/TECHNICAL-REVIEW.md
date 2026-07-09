# Technical diagnosis review

> **English** | [Español](es/REVISION-TECNICA.md)

This document summarizes the investigation in maintainer-review style: what is demonstrated, what is interpretation, and what remains open. For full trace logs and timeline, see [`expert-report.md`](expert-report.md).

---

## Overview

The work shows a clear progression from an initially poorly bounded problem to a specific root cause supported by runtime evidence. Hypotheses were eliminated through kernel instrumentation and experimental validation until the issue was localized in the interaction between the generic ASoC SoundWire layer and the TAS2783 driver.

Patch **0009** demonstrates that hardware, SoundWire transport, AMD manager programming, and the PCM path function correctly. The defect was in **logical channel assignment** when building the multicodec playback stream.

The investigation separates demonstrated facts from hypotheses, which supports both technical review and upstream discussion.

---

## Root cause analysis (Problem C)

Experimental validation shows the failure arises from the **combination of two independent components**.

### 1. Behaviour of `soc_sdw_utils.c`

When the calculation yields `step = 0`, the generic utility assigns the same `ch_map` to every codec on the link.

On a stereo system with two amplifiers, both initially receive:

```text
ch_mask = 0x3
```

This is valid for some topologies (e.g. duplicated mono playback, or codecs that split channels internally). It cannot be called universally wrong.

It does **not** cover the case where there is a one-to-one mapping between:

- PCM channel count, and
- SoundWire codec count.

In that case, the natural distribution is one independent channel per codec.

### 2. Behaviour of `tas2783-sdw.c`

The TAS2783 driver did not use the channel map computed by the machine layer.

During `hw_params()` it rebuilt `ch_mask` locally with a contiguous mask (`GENMASK(...)`), ignoring the information provided by ASoC infrastructure.

As a result, both amplifiers were configured to receive the same channel set.

Instrumentation confirmed this behaviour at runtime.

---

## Experimental validation

After modifying both:

- `soc_sdw_utils.c`
- `tas2783-sdw.c`

the stream was distributed as:

```text
PCM Stereo
      │
      ├──► UID 0x8   ch_mask = 0x1
      │
      └──► UID 0xb   ch_mask = 0x2
```

Testing with:

```bash
speaker-test -s 1
speaker-test -s 2
```

showed:

| Test | Result |
|------|--------|
| `-s 1` | left channel only |
| `-s 2` | right channel only |

Kernel traces showed both TAS2783 devices completing:

```text
hw_params → stream_add_slave → prepare → trigger
```

The second amplifier is therefore **not** excluded from the playback pipeline.

What is **not** demonstrated: internal DSP post-firmware configuration beyond successful load and correct port programming. Avoid inferring DSP-side channel discard without direct evidence.

---

## Upstream submission strategy

### Series A

Addresses an **independent** issue: opening capture streams on a device that only advertises `sink_ports` in its SoundWire DisCo description.

The patch rule is consistent with dynamically discovered capabilities:

```text
source_ports == 0  →  do not add codec to capture stream
```

This is a localized change based on device-advertised properties.

Maintainers may still ask whether the fix belongs in the machine driver, DAI description, or codec driver. The investigation evidence supports discussing any of those placements.

### Series C

Modifies two **complementary** components.

**First patch:** the generic utility assigns one channel per codec when:

```text
PCM channels == SoundWire codec count
```

Existing behaviour is unchanged for:

- mono playback,
- configurations with more codecs than channels,
- topologies that expect full-stream broadcast.

**Second patch:** TAS2783 stops rebuilding `ch_mask` and uses the map from ASoC infrastructure.

Both changes are required:

- utils alone is insufficient — the codec ignored the received map;
- tas2783 alone is insufficient — both codecs still received `ch_mask = 0x3`.

Experimental validation shows both are needed for correct stereo separation.

### Series B

Firmware download mitigation should remain an **RFC**.

Current data suggest `-110` failures disappeared after experimental changes, but the sample is still limited.

Before proposing a definitive fix, extend validation with:

- multiple reboots,
- suspend/resume,
- different sample rates,
- varied load scenarios.

That will make it easier to justify retry logic to maintainers.

---

## Residual `prepare ret=-22`

The residual message on:

```text
SDW1-PIN4-CAPTURE-SmartAmp
```

does not affect playback but shows a capture pipeline still includes the SmartAmp.

Since TAS2783 is playback-only, the next step is to determine why the machine driver still builds that capture route.

Review focus:

```text
sound/soc/amd/acp/acp-sdw-legacy-mach.c
```

Check:

- how `dai_links` are constructed,
- how playback and capture directions are assigned,
- whether TAS2783 can be excluded from capture links at topology creation.

If that can be fixed at machine-driver level, the system stays consistent without extra checks in `hw_params()`.

---

## Related documents

| Document | Content |
|----------|---------|
| [`expert-report.md`](expert-report.md) | Full investigation log, ENZOPLAY traces |
| [`../upstream/docs/SERIE-C-DEFENSA.md`](../upstream/docs/SERIE-C-DEFENSA.md) | Series C maintainer Q&A |
| [`../upstream/docs/MAINTAINER-REVIEW.md`](../upstream/docs/MAINTAINER-REVIEW.md) | checkpatch, recipients, matrices |
| [`../upstream/SUBMISSION-PLAN.md`](../upstream/SUBMISSION-PLAN.md) | Submission schedule |

---

*July 2026 — ASUS ProArt PX13 / snd_repair*

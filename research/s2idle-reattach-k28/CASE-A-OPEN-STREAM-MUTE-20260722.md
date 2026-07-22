# Causal report — mute after S2 with open PipeWire stream

**Host:** colosal3 · PX13 HN7306EAC · `7.0.0-28-generic`  
**Incident:** overnight s2idle `2026-07-21 21:54:07` → wake `2026-07-22 05:55:31`  
**Overlay:** 0001 + 0002 + 0003 + 0003b (`installed_at=2026-07-19T11:28:59+02:00`)  
**Symptom (user):** no sound after last suspend  
**Language:** English (canonical research note)

---

## Verdict (one line)

**Case B (SDW re-attach) succeeded; Case A recovery did not run** because an open ALSA/PipeWire playback stream never produced a new `hw_params`, so patch 0001’s second `fw_reinit()` never fired.

---

## Evidence (this boot, last cycle)

### Kernel — resume window `05:55:31`

```text
snd_repair resume enum kick:         inst=1 stat=0x0 pend=0x0 sc07=0x0 sc811=0x0
snd_repair resume enum kick delayed: inst=1 stat=0x4 pend=0x4 sc07=0x3 sc811=0x80000
PM: suspend exit
```

| Check | Result |
|-------|--------|
| Immediate kick `STAT==0` | expected (too early) |
| Delayed (+40 ms) `pend=0x4` | **0003b path fired** |
| `-110` / UNATTACHED / `fw download wait timeout` | **absent** |
| Slaves after wake | **Attached** ×3 (`:8`, `:b`, `rt721`) |

→ **Not** the post-S2 UNATTACHED / FW-timeout storm (Case B FAIL).

### Userspace — same second

```text
pipewire[…]: spa.alsa: hw:amdsoundwire,2p: … snd_pcm_avail after recover: Broken pipe
```

| Check | Result |
|-------|--------|
| PipeWire tried to keep `hw:amdsoundwire,2p` | yes (broken-pipe recover) |
| After wake: PCM `RUNNING` | yes (`owner_pid` = pipewire) |
| Default sink | Speaker `*` (not Soft-A / Dummy) |
| Firefox streams | several `active` / `init` on Speaker |
| 0001 marker in loaded `.ko` | OK |

→ Playback path stayed **open across S2**; PipeWire recovered the device without a clean close→open that would call `hw_params` again.

### Contrast with Case B FAIL (ruled out)

| | Case B FAIL (pre-0003b) | This incident |
|--|-------------------------|---------------|
| Slaves | UNATTACHED | **Attached** |
| Kick delayed | N/A or still dead | `pend=0x4` |
| Kernel spam | `-110`, `fw download wait timeout`, `trf -5` | **none** |
| PCM | often cannot prepare | **RUNNING** (silent) |

---

## Causal chain (delimited)

```text
s2idle (~8 h)
    → amd_resume_runtime / D0
    → 0003 immediate kick          (STAT=0 — race window)
    → 0003b delayed kick +40 ms    (pend=0x4 — PASS)
    → SDW slaves → ATTACHED        (Case B closed)
    → tas2783 resume / ATTACHED path fw_reinit()   (ret=0, DSP still mute — Case A)
    → resume_playback_reinit_pending = true        (0001 arms)
    → ???  gap
    → PipeWire: stream still open; Broken pipe recover on 2p
    → no new snd_pcm hw_params on tas2783 DAI
    → 0001 second fw_reinit() NEVER RUNS
    → PCM RUNNING + Speaker selected + silence
```

**Witnesses (not root):** “no sound”, Firefox still “playing”, `speaker-test` may open and write while DSP stays mute.

**Root layer:** TAS2783 Case A recovery is **gated on first post-sleep `hw_params`**. That gate is a no-op when the ALSA PCM stays open (or is recovered in place) across suspend.

Same class of failure already seen **2026-07-19 ~12:34** with Firefox playing during S2 (Attached + kick delayed OK, mute).

---

## Why 0001 is insufficient here

Patch 0001 (`patches/0001-tas2783-post-sleep-fw-reinit-on-hw-params.patch`):

1. On system sleep: arm `post_system_sleep`.
2. On ATTACHED / system resume: `fw_reinit()` + set `resume_playback_reinit_pending`.
3. On **first** `hw_params` while pending: second `fw_reinit()`, clear pending.

Assumes: after S2, userspace **opens a new stream** (or reopens PCM) so `hw_params` runs once.

Reality with GNOME + Firefox + PipeWire:

```text
stream open before S2
    → still open (or recovered) after S2
    → no hw_params
    → pending stays true forever (or is cleared without the useful reinit)
    → mute until something forces a new hw_params
```

Manual “fix that seemed to work earlier”: stop playback / new `speaker-test` → **new** `hw_params` → 0001 runs → sound returns. That is a **userspace reopen**, not Case B magic.

**Confirmed 2026-07-22 (user):** GNOME — unselect then reselect Speaker output restored audio after the overnight mute. Same mechanism: PCM reopen → `hw_params` → 0001 second `fw_reinit`.

---

## Two-bug map (keep separate for upstream)

| | **Case A** | **Case A′ (this gap)** | **Case B** |
|--|------------|-------------------------|------------|
| Layer | `tas2783-sdw` | `tas2783-sdw` + stream lifecycle | `soundwire-amd` |
| Bus | Attached | Attached | UNATTACHED |
| FW | loaded | loaded | never / timeout |
| PCM | new open → OK with 0001 | **stays open → mute** | prepare fails |
| Fix now | 0001 @ `hw_params` | **missing (0001b candidate)** | 0003 + **0003b** |
| Upstream | codec | codec (or document PW reopen) | AMD SDW resume |

Do **not** fold A′ into “0003b failed” — kernel kick lines prove Case B PASS.

---

## Candidate fix (not applied in this note)

Full design: **[PROPOSED-0001b-deferred-fw-reinit.md](PROPOSED-0001b-deferred-fw-reinit.md)**.

**0001b — deferred second `fw_reinit` after ATTACHED**, independent of `hw_params`:

- Keep 0001 `hw_params` path (cold reopen / unselect-reselect).
- After post-sleep ATTACHED + first `fw_reinit`, schedule one delayed work (~80 ms) for the second `fw_reinit`.
- Serialize with `hw_params` so only one second reinit runs.
- Marker: `snd_repair post-sleep deferred fw_reinit`.

Binary test: Firefox playing → S2 → sound returns **without** changing output device.

---

## Operational triage (quick)

```bash
# After a “silent” wake:
grep . /sys/bus/soundwire/devices/sdw:*/status
journalctl -k -b 0 | grep 'snd_repair resume enum kick' | tail -4

# Attached + kick delayed + no -110  → Case B OK → suspect A′
# Then: stop browser audio / restart pipewire OR new speaker-test
# If sound returns → A′ confirmed (hw_params gate)
```

Safe recover while Attached: reopen stream (stop PW clients / `systemctl --user restart pipewire wireplumber`).  
**Cold power** only if UNATTACHED (Case B). Never PCI reset with overlay.

---

## Status of product stack after this incident

| Patch | Role | This wake |
|-------|------|-----------|
| 0003b | Case B race | **PASS** |
| 0001 | Case A @ `hw_params` | **did not run** (no new `hw_params`) |
| 0001b | Case A′ open-stream | **implemented** — awaiting install + V1 |

Automation today: S2 re-attach is automatic; **open-stream mute recovery is not**.

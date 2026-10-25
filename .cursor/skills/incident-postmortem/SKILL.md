---
name: incident-postmortem
description: >-
  Extract logs and runtime evidence into a structured malfunction postmortem
  (verdict, evidence tables, causal chain, recovery, product implications).
  Use when the user asks for a postmortem, incident report, failure analysis,
  after-action from dmesg/journal/wpctl, or to document a bad audio/S2/kernel
  event in research/ or docs/.
---

# Incident postmortem (log → report)

Turn a malfunction into an **evidence-backed** English research note. Prefer facts from logs and live probes over hypotheses.

Companion methodology for *finding* the break layer: [layered-kernel-bisect](../layered-kernel-bisect/SKILL.md). This skill is for **capturing and writing** after (or during) an incident.

## When to apply

- User reports loss of sound / mic / jack / resume failure and wants it documented
- “Haz un postmortem”, “documenta el incidente”, “extrae los logs”
- Need a `research/**/INCIDENT-YYYYMMDD-….md` or troubleshooting update from a live machine

## Hard rules

1. **Docs on disk = English** (canonical). Chat with the user may stay in Spanish.
2. **No PCI unbind/bind** of `0000:c4:00.5` / `PX13_AFTER_SUSPEND` — hard freeze risk. Prefer PipeWire reopen, `pro-audio` route script, or SDW slave rebind only with explicit sudo.
3. **Separate stacked failures** (e.g. Scenario 2 mute + WirePlumber Source=Speaker). Do not collapse into one root cause without evidence.
4. **Numeric PipeWire IDs are ephemeral** — quote stable names (`…pro-output-2`, `…HiFi__Mic__source`).
5. Cite **markers and timestamps**, not vibes.

## Workflow

Copy and track:

```text
Postmortem Progress:
- [ ] 1. Scope window (symptom + approx time)
- [ ] 2. Collect snapshot (script or manual)
- [ ] 3. Classify stack layers (kernel / UCM / PipeWire)
- [ ] 4. Write INCIDENT note from TEMPLATE.md
- [ ] 5. Link from research README / troubleshooting if actionable
```

### 1 — Scope the window

Ask or infer:

| Field | Example |
|-------|---------|
| Host / SKU | colosal3 · PX13 HN7306EAC |
| Kernel | `uname -r` |
| Trigger | S2 / jack plug / PW restart / recover script |
| Symptom (user words) | “no sound”, “no input device” |
| Time window | wake `HH:MM` → now |

### 2 — Collect evidence

Prefer the project collector (run on the affected machine):

```bash
./.cursor/skills/incident-postmortem/scripts/collect-snapshot.sh \
  [outdir] [since-journal-time]
# e.g. ./…/collect-snapshot.sh /tmp/pm-20260803 "2026-08-03 14:00"
```

If the script is unavailable, gather the same probes manually (see [collectors.md](collectors.md)).

Read the snapshot **before** writing conclusions. Do not invent markers that are not in the files.

### 3 — Classify (quick triage table)

Fill from evidence only:

| Layer | PASS look like | FAIL look like |
|-------|----------------|----------------|
| Case B (SDW) | Attached ×3; delayed kick `pend=0x4`; no `-110` | UNATTACHED; FW timeout storm |
| 0001 / 0001b | `snd_repair post-resume fw_reinit` (once per wake) | missing after mute with open stream |
| Scenario 2 | PCM `prepare`/`START` + silence until reopen | — |
| WirePlumber mic | `Audio/Source` = Mic/Headset name | Source = `…Speaker__sink` or missing Sources |
| UCM / profile | HiFi + Speaker/Headphones/Mic | only `stereo-fallback` / broken `Headphone Switch` |
| Jack | `Headphone Jack` / `Headset Mic Jack` = on when plugged | off while plugged; or HiFi gone |

Mark stacked rows independently.

### 4 — Write the postmortem

1. Create `research/<track>/INCIDENT-YYYYMMDD-<short-slug>.md` (English).
2. Follow [TEMPLATE.md](TEMPLATE.md) structure **in order**.
3. Verdict: **one short paragraph or bullet list** of independent failures.
4. Causal chain: ASCII `→` with PASS/FAIL labels; put `???` only where evidence is missing.
5. Recovery: what was tried, what worked, **without reboot** vs needs reboot.
6. Product implications: Do / Do not (no speculative patches).

Update the track `README.md` status row if one exists.

### 5 — Optional ops docs

If the recovery is reusable, add a short section to `docs/troubleshooting.md` (English) and link the incident.

## Output quality bar

- Every claim in Verdict has a row in Evidence or a quoted log line.
- Contrast with a known-good class when useful (e.g. Case B FAIL vs this incident).
- No “should fix with more delayed fw_reinit” unless lifecycle contrast demands it (see Case A′ notes).

## Additional resources

- [TEMPLATE.md](TEMPLATE.md) — incident file skeleton
- [collectors.md](collectors.md) — probe commands and marker glossary
- Example: `research/s2idle-reattach-k28/INCIDENT-20260727-S2-MUTE-MIC-DEFAULT.md`

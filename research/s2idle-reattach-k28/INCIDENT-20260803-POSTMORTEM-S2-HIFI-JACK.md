# Incident postmortem — S2 mute, mic default, HiFi break, jack routing (2026-07-27 → 2026-08-03)

**Host:** colosal3 · PX13 HN7306EAC · `7.0.0-28-generic`  
**Window:** 2026-07-27 ~18:57 (S2 wake) → 2026-08-03 14:42 (live snapshot)  
**Overlay:** `installed_at=2026-07-23T13:35:52+02:00` — markers 0001 / 0001b / 0002 / 0003 / 0003b **OK**  
**Snapshot:** `/tmp/snd-repair-postmortem-20260803/` (`collect-snapshot.sh`, since `2026-07-27 18:00`)  
**User symptoms (verbatim arc):** no sound after S2; no recording / no input; jack input dead; after recover, headphones OK but input inactive; unplug → speakers silent + input deconfigured  
**Language:** English (canonical research note)  
**Skill:** `.cursor/skills/incident-postmortem`

---

## Verdict

Four **independent** failure classes stacked across one campaign (not one root cause):

1. **Scenario 2 mute (2026-07-27):** Case B + 0001b PASS; PCM still silent until reopen / later TAS path; 0001b does not re-fire on the same wake.
2. **WirePlumber mic default:** `Audio/Source` pointed at Speaker sink (monitor) / later vanished under `stereo-fallback`.
3. **HiFi UCM collapse (collateral):** SDW slave rebind recovery removed Jack/`Headphone Switch` → only `pro-audio` + `stereo-fallback`; jack auto-switch broken.
4. **Jack unplug under broken HiFi:** WirePlumber selected `stereo-fallback` → zero capture sources + wrong/silent playback path.

**At snapshot time (2026-08-03 14:42):** reboot at `11:43:39` restored **HiFi**; slaves Attached ×3; defaults Speaker + Digital Mic; Jack controls present (`off` = unplugged). A later S2 at `14:24:42` showed 0003b + 0001b PASS again.

---

## Evidence

### Kernel

| Check | Result |
|-------|--------|
| SDW slave status (now) | **Attached** ×3 (`:8`, `:b`, rt721) |
| Resume 2026-08-03 14:24:42 | kick `stat=0x0`; delayed `pend=0x4` (**0003b**) |
| 0001b same second | `snd_repair post-resume fw_reinit` on `:b` then `:8` |
| `-110` / UNATTACHED / FW timeout storm (post-resume) | **absent** on 14:24 path |
| Boot 11:43:44 | one `trf on Slave 1 failed:-110 write addr 8108` (boot-time; not the 14:24 resume storm) |
| PCM lifecycle (trace build) | `prepare` / `trigger_START` present after resumes |
| Overlay | all product markers OK in `snd-repair status` |

```text
ago 03 14:24:42 amd_sdw_manager.1: snd_repair resume enum kick: … stat=0x0 pend=0x0 …
ago 03 14:24:42 amd_sdw_manager.1: snd_repair resume enum kick delayed: … stat=0x4 pend=0x4 …
ago 03 14:24:42 slave-tas2783 …:b: snd_repair post-resume fw_reinit
ago 03 14:24:43 slave-tas2783 …:8: snd_repair post-resume fw_reinit
```

Jul 27 wake markers lived on the previous boot and are **not** in this journal after reboot; see prior note [INCIDENT-20260727-S2-MUTE-MIC-DEFAULT.md](INCIDENT-20260727-S2-MUTE-MIC-DEFAULT.md).

### Userspace (live 2026-08-03 14:42)

| Check | Result |
|-------|--------|
| Card profile | **HiFi** active (Headphones/Headset ports *not available* — jack unplugged) |
| Default sink | `…HiFi__Speaker__sink` |
| Default source | `…HiFi__Mic__source` |
| Nodes | Speaker `*`, Headphones, Digital Microphone `*`, Headset Microphone |
| Jack controls | `Headphone Jack` / `Headset Mic Jack` = **off**; `Headphone Switch` present again |
| `default-nodes` | Speaker + Mic primary; still lists legacy `pro-*` / `stereo-fallback` as lower prefs |

### Userspace (2026-07-27 session — from contemporaneous diagnosis)

| Phase | Result |
|-------|--------|
| After S2 | Case B OK; 0001b OK; Scenario 2 mute; Source=`…Speaker__sink` |
| After PW restart | full `hw_params`→`START`; still mute possible (0001b already claimed) |
| After `recover-post-s2-mute-no-reboot.sh` | HiFi gone (`Headphone Switch` missing); `stereo-fallback` / `pro-audio` only |
| Jack plugged + `pro-audio` | Headphones = `pro-output-0`; headset mic = `pro-input-1` (user heard HP) |
| Jack unplugged | profile → **`stereo-fallback`**: no Sources; speakers not recovered until forced `pro-output-2` + `pro-input-4` |

---

## Classification (skill triage)

| Layer | This campaign |
|-------|----------------|
| Case B (SDW) | **PASS** (Jul 27 session + Aug 3 14:24) |
| 0001b | **PASS** (fires once per wake) |
| Scenario 2 | **FAIL** Jul 27 (mute despite reopen attempts until stronger recovery / reboot) |
| WirePlumber mic | **FAIL** Jul 27 (Speaker-as-source); OK now |
| UCM / profile | **FAIL** after SDW rebind; **PASS** after Aug 3 reboot |
| Jack auto | **FAIL** while HiFi broken; **PASS** controls restored post-reboot (unplugged = off) |

---

## Causal chain

```text
S2 (2026-07-27 ~18:57)
    → 0003b delayed kick pend=0x4 → Attached ×3     (Case B PASS)
    → 0001b post-resume fw_reinit                     (PASS, one-shot)
    → open PW streams / Scenario 2 silence
    → WP default Source = Speaker sink                (“no mic”)
    → sink-flip / PW restart                          (partial)
    → sudo SDW TAS+rt721 rebind                       (intended mute fix)
    → Headphone Switch / Jack controls missing
    → HiFi UCM cannot set _verb                       (HiFi gone)
    → pro-audio workaround (HP + headset OK)
    → jack unplug → stereo-fallback                   (no inputs; speakers lost)
    → px13-pro-audio-route.sh jack-out                (workaround)
    → reboot 2026-08-03 11:43                         (HiFi restored)
    → S2 14:24 → 0003b + 0001b again                  (Case B/A path OK at snapshot)
```

---

## Recovery applied

1. `wpctl` / `default-nodes` scrub for Mic (Jul 27) — mic UX fixed; mute often remained.  
2. PipeWire full restart + sink flip — Scenario 2 partial.  
3. `scripts/recover-post-s2-mute-no-reboot.sh` (SDW rebind) — **HiFi collateral damage**.  
4. `pactl set-card-profile … pro-audio` + name-based defaults — jack audio worked.  
5. `scripts/px13-pro-audio-route.sh jack-in|jack-out` — manual plug/unplug routing.  
6. **Reboot** (2026-08-03) — restored HiFi + Jack controls (confirmed in snapshot).

**Reboot required?** for durable HiFi restore after rebind collateral: **yes**. Partial workarounds without reboot: **yes** (`pro-audio` route script).  
**PCI reset used?** **no** (forbidden).

---

## Product implications

| Do | Do not |
|----|--------|
| Treat mute + “no mic” + jack as **separate** checks (SDW / WP / UCM) | Collapse all symptoms into Case B |
| Prefer PW reopen / `px13-pro-audio-route.sh` before SDW rebind | Assume SDW rebind is safe for UCM/Jack |
| Persist defaults by **stable names**; never hardcode wpctl IDs | Leave `stereo-fallback` as preferred sink |
| After rebind: verify `amixer` Jack + `alsaucm set _verb HiFi` | Add another delayed `fw_reinit` for Scenario 2 without lifecycle contrast |
| Collect with `incident-postmortem` snapshot before reboot (journal rotates) | PCI unbind ACP |

**Scripts:** `scripts/px13-pro-audio-route.sh`, `scripts/recover-post-s2-mute-no-reboot.sh` (warn: may break HiFi).  
**Docs:** [docs/troubleshooting.md](../../docs/troubleshooting.md) (stereo-fallback / pro-audio section).  
**Prior note:** [INCIDENT-20260727-S2-MUTE-MIC-DEFAULT.md](INCIDENT-20260727-S2-MUTE-MIC-DEFAULT.md).

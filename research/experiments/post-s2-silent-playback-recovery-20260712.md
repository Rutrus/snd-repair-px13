# Post-S2 silent playback + recovery outcomes (2026-07-12)

English (canonical). **Incident report** — supersedes naive KPI-U “playback PASS” for speaker output.

**Machine:** ProArt PX13 · kernel `7.0.0-27-generic`  
**Context:** W1+W2 installed · `px13-audio-resume.service` **disabled** (KPI-U clean-test guidance)

---

## Symptom (user)

After suspend/resume:

- GNOME **Settings → Sound test** — no audible output
- User hears **nothing** despite normal-looking UI
- `wpctl status` shows **Audio Coprocessor Speaker** (not Dummy Output)
- Internal mic may still work (PipeWire MMAP capture)

This is **not** Dummy Output and **not** the KPI-K `arecord` RW failure.

---

## Software vs audible (what we measured)

| Check | Result | Implication |
|-------|--------|-------------|
| `post-s2-user-witness.sh` | **KPI-U PASS** | Automated contract insufficient |
| `pw-play` bell | exit 0 | No audible verification |
| `hw:1,2` speaker-test | exit 0 | Software path OK |
| `/proc/.../pcm2p/status` | RUNNING, **hw_ptr advancing** | DMA active |
| TAS2783 mixers | Amp/Speaker 100%, Spk switches ON | Not a simple mute |
| W1+W2 @ resume | `force_fw_reinit` + FW success=1 | Kernel resume path ran |
| **User hears sound** | **NO** | **Silent playback** |

**Failure class:** logical playback OK, **physical/analog path silent** (DAPM / amp enable / post-W2 state — TBD upstream).

---

## KPI-U gap (witness bug)

`post-s2-user-witness.sh` marks `playback=PASS` when:

```bash
pw-play --target="$def_snk" "$BELL"   # exit 0 only
```

It does **not** require:

- Audible output
- Sustained `hw_ptr` during PW playback
- GNOME sound test pass

**Mic PASS + playback “PASS” can coexist with silent speakers.**

Future: ~~add optional human gate~~ **Done** — `playback_audible_confirm` on TTY (default). `playback_hwptr` gate on pcm2p.

**Script (2026-07-12):** `post-s2-user-witness.sh` now requires:

1. No Dummy Output
2. `speaker-test -D pipewire` + pcm2p **RUNNING** + `hw_ptr` delta ≥ 8192
3. **Interactive ear confirm** (default on TTY): user must answer `y` after 440 Hz tone

Automation: `./scripts/post-s2-user-witness.sh --no-audible-confirm` (hw_ptr only — may still false PASS on silent amp path).

**Limit:** hw_ptr advancing does **not** guarantee audible output (DAPM/analog). Ear confirm catches that case.

---

## Stack configuration at incident

| Component | State |
|-----------|--------|
| W1 (`soundwire-amd` 0006a) | Installed |
| W2 (`force_fw_reinit`) | Installed |
| `px13-audio-resume.service` | **disabled** (per earlier KPI-U isolation) |
| `px13-audio-rebind.service` | enabled (boot) |

Disabling brainchillz **resume** removed the PCI-reset safety net while W1+W2 alone did not restore **audible** playback on this session.

See also: [px13-audio-fix-vs-w1w2.md](px13-audio-fix-vs-w1w2.md)

---

## Recovery attempts (same session)

### Option A — manual `px13-audio-fix.sh`

```bash
sudo PX13_AFTER_SUSPEND=1 /usr/local/sbin/px13-audio-fix.sh
```

**Observed outcome:**

- Audio device **disappeared** from GNOME Settings
- System prompted **reboot** to restore audio stack
- **Do not use as inline hotfix without expecting reboot** on this machine

Script actions: stop PipeWire → PCI unbind/bind → FW settle → optional speaker-test → restart PipeWire. Mid-flight state can leave WP/UCM inconsistent until reboot.

### Option B — re-enable `px13-audio-resume.service`

```bash
sudo systemctl enable --now px13-audio-resume.service
```

**Observed outcome (2026-07-12 evening, with W1+W2 installed): WORSE — Dummy Output.**

Timeline on boot `#2` after user enabled Option B:

```text
16:14:44  resume → W2 force_fw_reinit → :8/:b success=1 done=1
16:14:57  px13-audio-resume starts (~13 s later)
16:14:57  PCI unbind/bind (destroys W2 FW state)
16:15:11  px13: "no FW errors" → starts PipeWire
16:15:15+ :8 playback without fw download (EINVAL flood)
          → WirePlumber: Dummy Output only
```

**Conclusion:** **Do not combine W1+W2 with `px13-audio-resume`.** They fight; px13 PCI reset wins and breaks SmartAmp FW.

**Recovery from Dummy Output:**

```bash
sudo systemctl disable --now px13-audio-resume.service
sudo reboot
```

After reboot: W1+W2 only, px13 resume **disabled**, test cold boot audio before next S2.

---

## Revised daily-driver guidance (2026-07-12 evening)

**Pick one resume path — never both:**

| Path | Stack | Post-S2 |
|------|-------|---------|
| **A (kernel)** | W1 + W2 + UCM · **px13-audio-resume DISABLED** | May be silent but Speaker visible; investigate DAPM |
| **B (userspace)** | brainchillz only · **px13-audio-resume ENABLED** · stock or base kernel modules | PCI reset daily-driver (no W2) |

**Combining W1+W2 + px13-audio-resume → Dummy Output** (measured 16:14–16:17).

Verify audibly (GNOME test or `speaker-test -D pipewire` + ear / witness prompt).

---

## Verification checklist (human)

After S2, wait **~15 s** if `px13-audio-resume` is enabled, then:

```bash
wpctl status | grep -E 'Speaker|Dummy'
speaker-test -D pipewire -c 2 -t sine -f 440 -l 1    # must HEAR tone
# optional:
./scripts/post-s2-user-witness.sh                     # mic + software playback
```

---

## References

- [SOLUTION-CLOSURE-KPI-U-20260712.md](../SOLUTION-CLOSURE-KPI-U-20260712.md) — original closure (playback caveat added there)
- [kpi-u-vs-kpi-k-20260712.md](kpi-u-vs-kpi-k-20260712.md) — KPI split
- [pcm-s2-set-params-witness.md](../pcm-s2-set-params-witness.md) — DAPM / TAS2783 RUN hypothesis
- [../ROADMAP-POST-KPI-U-20260712.md](../ROADMAP-POST-KPI-U-20260712.md)

---

## Open work

1. Re-test S2 with Option B after reboot — document PASS/FAIL **audible**
2. Harden `post-s2-user-witness.sh` playback probe
3. Upstream: why W1+W2 + FW OK → RUNNING + hw_ptr but no sound?

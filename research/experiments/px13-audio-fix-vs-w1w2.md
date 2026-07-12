# px13-audio-fix vs W1/W2 — what it does and why it confounds PM tests

English (canonical). Inspect before more kernel instrumentation.

**Script:** [`../../scripts/px13-audio-fix.sh`](../../scripts/px13-audio-fix.sh) (installed as `/usr/local/sbin/px13-audio-fix.sh`)  
**Trigger:** [`px13-audio-resume.service`](../../docs/INSTALL.md) — `WantedBy=suspend.target`, not a no-op wrapper.

---

## Service anatomy

| Piece | Effect |
|-------|--------|
| Unit `ExecStartPre=/bin/sleep 3` | 3 s after unit start |
| Drop-in `snd-repair-fw-validation.conf` | **+8 s** `ExecStartPre`, sets `PX13_AFTER_SUSPEND=1` |
| `ExecStart=/usr/local/sbin/px13-audio-fix.sh` | Full userspace + PCI reset |
| **Total delay post-resume** | **~11 s** before first script line |

Because the unit is `WantedBy=suspend.target`, it runs automatically after **every** system suspend unless **disabled**.

---

## What `px13-audio-fix.sh` does (ordered)

```text
1. flock lock (/run/px13-audio-fix.lock)
2. Optional: extend timeouts if journal shows SDW resume -110
3. For each logged-in user:
      systemctl --user stop wireplumber pipewire pipewire-pulse + sockets
      (timeout → SIGKILL; runtime mask on pipewire.socket)
4. Up to 2× (3× if -110):
      a. echo PCI_DEV > /sys/bus/pci/drivers/snd_pci_ps/unbind
      b. sleep 2
      c. echo PCI_DEV > /sys/bus/pci/drivers/snd_pci_ps/bind
      d. poll /proc/asound/cards for amd-soundwire (≤10 s)
      e. sleep 12 s (FW_SETTLE_SEC) — wait async FW
      f. speaker-test plughw:1,2 pink noise (unless SKIP_SPEAKER_TEST)
      g. grep dmesg for :8/:b FW errors → retry if broken
5. alsaucm set _verb HiFi (optional)
6. systemctl --user start pipewire wireplumber pipewire-pulse
7. schedule fw-validation-suspend-hook (background)
```

**Does not:** `rmmod` / `modprobe` kernel modules, write SDW sysfs beyond PCI bind, or call W1/W2 hooks.

**Does:** destroy and recreate the **entire ACP PCI function** (`0000:c4:00.5`), which re-probes SoundWire from cold-driver state.

---

## Comparison with W1 / W2

| Action | W1 (0006a) | W2 (force FW) | px13-audio-fix |
|--------|------------|---------------|----------------|
| When | SDW manager IRQ path on resume | `tas_update_status` ATTACHED after **system** sleep | ~11 s after resume (systemd) |
| PCI unbind/bind | No | No | **Yes** (2× typical) |
| PipeWire stop/start | No | No | **Yes** |
| SDW ATTACHED kick | `schedule_work(amd_sdw_irq_thread)` | — | Side effect of PCI reprobe |
| TAS2783 FW reload | No | `tas2783_fw_reinit()` if `post_system_sleep` | Only if reprobe + ATTACHED path runs **without** W2 flag |
| ALSA UCM HiFi | No | No | Optional `alsaucm` |
| FW probe | No | Q2 trace / hw_params | `speaker-test` after 12 s settle |

**Overlap:** none at code level. **Conflict:** px13 **replaces** the post-resume hardware state W1+W2 just established. Boot #133: W2 left `:8`/`:b` at `success=1 done=1` (12:58:08); px13 PCI bind (12:58:23) left slaves UNATTACHED with `success=0` and **no** `W2 force_fw_reinit`.

---

## Why PM experiments need px13 off (Cases A–C)

```text
Natural S2 PM path:  suspend → resume → [W1] → [W2] → KPI?

With px13 on:         suspend → resume → [W1] → [W2] → ~11s → PCI reset → new probe path → KPI?
```

You cannot attribute KPI to W2 if px13 runs in the same window.

---

## Clean experiment — px13 isolation

**Prefer disable** (removes `WantedBy` links); mask + `.bak` only if disable is insufficient.

```bash
# Before suspend (Cases A–C)
sudo systemctl disable --now px13-audio-resume.service
sudo systemctl daemon-reload

systemctl is-enabled px13-audio-resume.service   # → disabled
systemctl is-active px13-audio-resume.service    # → inactive
systemctl list-dependencies suspend.target | grep px13 || echo "px13 not in suspend.target"

systemctl cat px13-audio-resume.service          # inspect unit + drop-ins (know what you disabled)
```

**After resume:**

```bash
journalctl -b -u px13-audio-resume.service --no-pager
# Empty / no Started → px13 did not run (clean)
journalctl -b | grep px13-audio-fix || echo "no px13 in journal"
```

If `disable` is not enough (unit still starts):

```bash
sudo mv /etc/systemd/system/px13-audio-resume.service{,.bak}
sudo systemctl mask px13-audio-resume.service && sudo systemctl daemon-reload
```

**Restore for Case D:**

```bash
sudo systemctl unmask px13-audio-resume.service 2>/dev/null || true
sudo mv /etc/systemd/system/px13-audio-resume.service.bak .../px13-audio-resume.service 2>/dev/null || true
sudo systemctl enable px13-audio-resume.service && sudo systemctl daemon-reload
```

---

## Case D expectation

With px13 **on** + W1+W2: W2 may PASS at resume, then px13 PCI reset may **undo** FW state — same as boot #133. Case D measures whether daily-driver workflow is compatible with W2, not whether W2 alone fixes KPI.

---

## References

- Matrix protocol: [w2b-prime-matrix-protocol.md](w2b-prime-matrix-protocol.md)
- W2b contamination witness: [w2b-q2-trace-20260712.md](w2b-q2-trace-20260712.md)
- Track D: [../tracks/TRACK-D-PIPEWIRE-PM.md](../tracks/TRACK-D-PIPEWIRE-PM.md)

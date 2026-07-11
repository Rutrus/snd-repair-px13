# R002 — Boot sequence replay

English (canonical). **Priority 2.**

**Question:** Boot works. Resume fails. What **order of steps** does boot take that resume skips?

Not register diff first — **sequence replay**.

---

## Boot sequence (target)

```text
PCI probe (snd_acp_pci)
    ↓
request_irq (devm_request_threaded_irq)
    ↓
platform / ACP device init
    ↓
SoundWire manager probe
    ↓
manager → D0
    ↓
RT721 attach
    ↓
audio OK
```

## Resume sequence (broken)

```text
PCI resume (snd_acp_resume)
    ↓
manager resume
    ↓
RT721 resume / wait
    ↓
FAIL (-110)
```

**Missing?** Possibly: fresh `request_irq` path, full manager **probe** (not resume), IRQ thread scheduling, ordering of enable vs reset.

Reference calls: [../../research/phase-8/ACP-BOOT-VS-RESUME-CALLS.md](../../research/phase-8/ACP-BOOT-VS-RESUME-CALLS.md)

---

## Mode A — sysfs replay (no kernel rebuild)

After failed resume, manually walk the boot graph:

### Step 1 — manager unbind + bind

```bash
# Discover paths on PX13 first:
ls /sys/bus/soundwire/devices/
ls /sys/bus/platform/drivers/

# R04 script wraps this
./resolution/scripts/recovery/R04-rebind-manager.sh
```

**If PASS:** problem is below manager (ACP/PCI) or manager resume ≠ probe.

### Step 2 — PCI unbind + bind

```bash
./resolution/scripts/recovery/R07-rebind-pci.sh
```

**If PASS:** manager layer insufficient; PCI re-probe required.

### Step 3 — remove + rescan (full PCI re-enumeration)

```bash
./resolution/scripts/recovery/R08-remove-rescan-pci.sh
```

**If PASS:** need full device teardown like cold plug.

---

## Mode B — kernel replay (M04)

Extract probe-tail functions into `acp70_boot_replay()` called from resume **or** from recovery hook after timeout.

Candidate call order (from research matrix):

```text
acp70_reset → clock/bridge → acp70_enable_interrupts (boot variant)
    ↓
manager full init (probe path, not pm_resume)
    ↓
schedule_work if STAT pending  [0006a proved sufficient]
```

Patches: `resolution/experiments/proposed/`

---

## Decision tree

```text
R04 rebind manager → PASS?
    yes → workaround at L2; resume should call probe path
    no  → R07 rebind PCI → PASS?
              yes → workaround at L4
              no  → R002 Mode B or R009 runtime PM
```

---

## Result

| Run | Mode | Deepest step needed | Result | Notes |
|-----|------|---------------------|--------|-------|
| — | — | — | — | |

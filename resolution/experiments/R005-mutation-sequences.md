# R005 — Mutation sequences

English (canonical). **Priority 4.**

**Method:** mutate order and timing. Do not instrument. Do not log beyond PASS/FAIL.

**Goal:** find a **stable sequence** that resurrects audio even if cause is unknown.

---

## Rules

- One sequence per kernel build or per hook script
- Change **order** or **timing** — not multiple knobs at once
- PASS = audio after system resume **without** post-hoc recovery script

---

## M01 — delayed disable/enable

```text
system resume entry
    ↓
msleep(200)
    ↓
acp70_disable_interrupts()   # or skip if mutation variant
    ↓
acp70_enable_interrupts()    # boot-style
    ↓
manager_reset
    ↓
manager D0
```

Variants: 200 ms / 500 ms anchor; anchor before vs after manager_reset.

Research note: 0005 delay-only **FAIL** — this mutates **full** sequence, not delay alone.

---

## M02 — remove → probe on resume

```text
snd_acp_resume()
    ↓
simulate remove (driver internal teardown)
    ↓
pci probe path (partial)
    ↓
continue resume
```

Heavy-handed. May overlap R08 recovery. Kernel patch required.

---

## M03 — runtime PM on resume tail

See [R004-runtime-pm-repair.md](R004-runtime-pm-repair.md) — can be hook (no rebuild) or patched into `snd_acp_resume()` tail.

---

## M04 — boot order replay

See [R002-boot-sequence-replay.md](R002-boot-sequence-replay.md).

---

## M05 — double manager reset

```text
resume → manager_reset → msleep(50) → manager_reset → D0
```

Doc: [../workarounds/0004-reset-twice.md](../workarounds/0004-reset-twice.md)

---

## M06 — invert enable/reset order

```text
resume: enable_interrupts BEFORE manager_reset
```

vs current: reset then enable.

---

## Build

```bash
# Future:
# ./resolution/scripts/build-mutation.sh M01
./scripts/build-from-upstream.sh   # rollback
```

Patches land in `resolution/experiments/proposed/`.

---

## Result

| Id | Sequence | Build | Result | Notes |
|----|----------|-------|--------|-------|
| M01 | | | `?` | |
| M02 | | | `?` | |
| M05 | | | `?` | |
| M06 | | | `?` | |

# Capture after S2 — dual-lane roadmap

English (canonical). **2026-07-12**

---

## Project KPI — split U vs K (2026-07-12)

Two contracts; do not merge verdicts. Full write-up: [../experiments/kpi-u-vs-kpi-k-20260712.md](../experiments/kpi-u-vs-kpi-k-20260712.md)

| KPI | Question | Witness |
|-----|----------|---------|
| **KPI-U (User)** | Laptop usable after S2 (GNOME/PW/apps)? | `./scripts/post-s2-user-witness.sh` |
| **KPI-K (Kernel)** | Direct `hw:X,Y` after S2 (upstream)? | `./scripts/post-s2-kernel-witness.sh` |

**KPI-U end goal:** playback + Internal/Headset mic + PW routes + S2×3/×10 — **PipeWire untouched** after resume.

**KPI-K:** `arecord` / `speaker-test` with PW stopped — informative for upstream; **not** laptop PASS/FAIL.

### Status (2026-07-12 evening)

```text
Playback post-S2       ✓  (W1+W2)
KPI-U capture          ✓  pw-record + GNOME meter (post-s2-user-witness PASS)
KPI-K capture MMAP     ✓  arecord -M (both geometries)
KPI-K capture RW       ✗  arecord default — copy path only
SmartAmp PIN4          ✗  structural (boot); parked
```

Matrix: [../experiments/capture-access-matrix-20260712.md](../experiments/capture-access-matrix-20260712.md). **KPI-U S2×3: PASS** [kpi-u-s2x3-pass-20260712.md](../experiments/kpi-u-s2x3-pass-20260712.md).

---

## Two lanes (do not merge)

| Lane | Priority | Rule |
|------|----------|------|
| **A — Functional** | **P0** | If a **small patch** restores capture post-S2, **try it** even without full root cause. Ugly fixes welcome if laptop works. |
| **B — Investigation** | **P1** | Find **who** should run **ALLOCATED → CONFIGURED** for capture after resume. Upstream-quality fix later. |

Lane A does not wait for Lane B. Lane B does not block opportunistic Lane A wins.

---

## What we know

```text
W1 (IRQ)     ✓    W2 (TAS play FW)  ✓    UCM/PW (boot)  ✓
Playback post-S2  ✓
KPI-U capture   ✓  (PipeWire / MMAP)
KPI-K RW        ✗  snd_pcm_read / copy path post-S2
KPI-K MMAP      ✓
SmartAmp PIN4   ✗  never CONFIGURED (boot); parked
```

KPI-K matrix: [../experiments/capture-access-matrix-20260712.md](../experiments/capture-access-matrix-20260712.md).

---

## Investigation question (Lane B — KPI-K upstream)

> **Why does `SNDRV_PCM_ACCESS_RW_INTERLEAVED` fail post-S2 while MMAP works on the same PCM?**

Focus: `snd_pcm_readi` / driver `.copy` vs mmap path — **not** SDW CONFIGURED / DMA dead (ruled out by matrix).

### Kernel site (stock 7.0)

| Step | Function | State change |
|------|----------|--------------|
| Stream created | `sdw_alloc_stream()` | → **ALLOCATED (0)** |
| Slave bound | **`sdw_stream_add_slave()`** | → **CONFIGURED (1)** |
| PCM prepare | `sdw_prepare_stream()` | requires CONFIGURED — **fails here if still ALLOCATED** |

So **`sdw_prepare_stream()` is late witness** — the gap is **before** prepare, at configure/add_slave.

Candidates for missing configure path:

- Machine driver (`acp-sdw-legacy-mach.c`)
- ASoC link / `asoc_sdw_*` hw_params → `set_stream` → `sdw_stream_add_slave`
- AMD SoundWire manager (transport after resume)
- SDW core (`sdw_config_stream`)

---

## SDWCAP trace (Lane B tool)

Patch: [patches/0001-sdwcap-stream-state-trace.patch](patches/0001-sdwcap-stream-state-trace.patch)

Logs **every** `stream->state` write with `caller=%pS`. **Parse for:**

```bash
grep 'SDWCAP trans.*dir=capture.*new=1:CONFIGURED'   # H1 falsified if absent post-S2
grep 'SDWCAP trans.*dir=capture.*CONFIGURED.*ALLOCATED'  # H2 regression
```

Build: `sudo ./scripts/build-sdwcap-trace.sh`

---

## Functional lane (Lane A) — open

1. Post-S2 `./scripts/post-s2-user-witness.sh` → **KPI-U PASS/FAIL**
2. Optional: `./scripts/post-s2-kernel-witness.sh` → KPI-K (upstream)
3. Persistence S2×3/×10 on **KPI-U** only

Do not use `--functional` on `post-s2-card-witness.sh` for user capture verdict (false FAIL vs GNOME).

---

## References

- Strategy: [../experiments/capture-sdw-strategy-pivot-20260712.md](../experiments/capture-sdw-strategy-pivot-20260712.md)
- Case B: [../experiments/capture-triple-probe-case-b-20260712.md](../experiments/capture-triple-probe-case-b-20260712.md)
- Queue: [../MAKE-IT-WORK.md](../MAKE-IT-WORK.md)

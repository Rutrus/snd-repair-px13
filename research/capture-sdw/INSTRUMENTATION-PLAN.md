# SDWCAP — stream state transition trace

English (canonical). P0 for [capture-sdw-strategy-pivot](../experiments/capture-sdw-strategy-pivot-20260712.md).

---

## Question (refined)

`sdw_prepare_stream()` only proves we arrive **late**. The gap is earlier:

> **Who should run ALLOCATED → CONFIGURED for capture after resume — and why doesn't it?**

Stock 7.0: transition happens in **`sdw_stream_add_slave()`** (not in prepare). SDWCAP must show whether that path runs for `dir=capture` post-S2, and `caller=%pS` if state regresses.

---

## Patch scope

File: `drivers/soundwire/stream.c`

| Mechanism | Logs |
|-----------|------|
| **`sdwcap_stream_set_state()`** | Every `stream->state` write: `old`, `new`, `caller=%pS`, stream name, direction |
| **Regression** | `dump_stack()` if `CONFIGURED+ → ALLOCATED` |
| **`sdw_prepare_stream()` entry** | state, update_params, caller |
| **prepare_fail** | `sdwcap_log_stream_ctx()` — slave uid, status, port, directions |
| **`sdw_stream_add_slave()` → CONFIGURED** | transition logged (did configure run for capture?) |
| **`sdw_stream_remove_master()` → RELEASED** | transition logged (post-S2 cleanup?) |

Direction inferred from stream name (`*-Playback` / `*-Capture`).

---

## Hypotheses to falsify

| H1 | Capture never reaches CONFIGURED after S2 — no `trans … new=1:CONFIGURED dir=capture` |
| H2 | Capture reaches CONFIGURED then regresses — look for `CONFIGURED → ALLOCATED` + stack |

If H1: focus **common** SDW path (manager/core/machine), not RT721/TAS2783 alone.

If H2: **`caller=%pS`** on regression transition is the fix target.

---

## Build / install

```bash
sudo ./scripts/build-sdwcap-trace.sh
sudo reboot
```

Patch: [patches/0001-sdwcap-stream-state-trace.patch](patches/0001-sdwcap-stream-state-trace.patch)

Rebuilds **`soundwire-bus.ko`** only. W1/W2/UCM unchanged.

---

## Protocol

```bash
sudo systemctl disable --now px13-audio-resume.service
systemctl suspend && sleep 45

systemctl --user stop wireplumber pipewire pipewire-pulse

# 1 playback (baseline — expect trans chain to PREPARED/ENABLED)
speaker-test -D hw:1,2 -c 2 -r 48000 -t sine -l 1

# 2 capture probes
arecord -D hw:1,1 -f S16_LE -r 48000 -c 2 -d 1 /tmp/rt721.wav
arecord -D hw:1,3 -f S16_LE -r 48000 -c 2 -d 1 /tmp/smartamp.wav
arecord -D hw:1,4 -f S32_LE -r 48000 -c 2 -d 1 /tmp/dmic.wav

journalctl -k --since "10 minutes ago" | grep SDWCAP | tee validation/sdwcap-$(date +%Y%m%d-%H%M).log
```

### Parse

```bash
grep 'SDWCAP trans' validation/sdwcap-*.log | grep -i capture
grep 'SDWCAP trans' validation/sdwcap-*.log | grep -i playback
grep 'SDWCAP REGRESSION\|dump_stack' validation/sdwcap-*.log
```

---

## Expected trace shapes

**H1 — never configured:**

```text
capture … old=0:ALLOCATED … (no new=1:CONFIGURED for capture)
SDWCAP prepare_enter … dir=capture state=0:ALLOCATED
```

**H2 — regression:**

```text
capture … old=0:ALLOCATED new=1:CONFIGURED caller=…
capture … old=1:CONFIGURED new=0:ALLOCATED caller=…   ← fix here
```

---

## Do not

- Add functional capture patches before SDWCAP log exists
- Extend W2 / UCM for this experiment

---

## Rollback

```bash
sudo cp ~/soundwire-bus.ko.zst.orig /lib/modules/$(uname -r)/kernel/drivers/soundwire/soundwire-bus.ko.zst
sudo depmod -a && sudo reboot
```

Or reset kernel tree + rebuild production modules.

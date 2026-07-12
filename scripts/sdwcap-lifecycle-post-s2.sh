#!/usr/bin/env bash
# One-shot: S2 → ALSA capture probes → SDWCAP lifecycle extract (Case A vs B).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MARK="$(date +%Y%m%d-%H%M%S)"
OUT="${ROOT}/validation/sdwcap-lifecycle-post-s2-${MARK}"
mkdir -p "$OUT"

log() { echo "[$(date -Iseconds)] $*" | tee -a "$OUT/timeline.txt"; }

log "=== SDWCAP lifecycle post-S2 experiment ==="
log "pre-suspend"
SUSPEND_AT="$(date -Iseconds)"

log "suspending (45s target sleep after resume)"
systemctl suspend || true
sleep 45

RESUME_AT="$(date -Iseconds)"
log "post-resume at $RESUME_AT"

systemctl --user stop wireplumber pipewire pipewire-pulse 2>/dev/null || true
sleep 2

log "probe: speaker-test hw:1,2"
if speaker-test -D hw:1,2 -c 2 -r 48000 -t sine -l 1 >"$OUT/speaker-test.log" 2>&1; then
  log "speaker-test: PASS"
else
  log "speaker-test: FAIL exit=$?"
fi

probe_cap() {
  local dev=$1 fmt=$2 dur=$3 out=$4
  log "probe: arecord -D $dev"
  if arecord -D "$dev" -f "$fmt" -r 48000 -c 2 -d "$dur" "$out" >"$OUT/arecord-${dev//[:.]/-}.log" 2>&1; then
    log "arecord $dev: PASS ($(stat -c%s "$out" 2>/dev/null || echo 0) bytes)"
  else
    log "arecord $dev: FAIL exit=$?"
  fi
}

probe_cap hw:1,1 S16_LE 2 "$OUT/rt721.wav"
probe_cap hw:1,3 S16_LE 1 "$OUT/smartamp.wav"
probe_cap hw:1,4 S32_LE 1 "$OUT/dmic.wav"

log "extracting kernel SDW traces since $RESUME_AT"
journalctl -k -b 0 --no-pager --since "$RESUME_AT" >"$OUT/kernel-since-resume.log" 2>/dev/null || true
grep SDWCAP "$OUT/kernel-since-resume.log" >"$OUT/sdwcap-all.log" || true
grep -E 'inconsistent state|sdw_prepare_stream|ASoC error' "$OUT/kernel-since-resume.log" >"$OUT/kernel-sdw-errors.log" || true
grep 'dir=capture' "$OUT/sdwcap-all.log" >"$OUT/sdwcap-capture.log" || true
grep 'dir=playback' "$OUT/sdwcap-all.log" >"$OUT/sdwcap-playback.log" || true

# Classify lifecycle per capture stream pointer
python3 - "$OUT/sdwcap-capture.log" >"$OUT/lifecycle-summary.txt" <<'PY'
import re, sys
from collections import defaultdict

path = sys.argv[1]
try:
    lines = open(path).read().splitlines()
except FileNotFoundError:
    print("NO_CAPTURE_SDWCAP_LINES")
    sys.exit(0)

streams = defaultdict(list)
for ln in lines:
    m = re.search(r'stream=([0-9a-f]+).*name=([^ ]+(?: [^ ]+)*?) dir=capture', ln)
    if not m:
        m = re.search(r'stream=([0-9a-f]+).*dir=capture', ln)
    sid = m.group(1) if m else "unknown"
    if "trans stream=" in ln:
        t = re.search(r'old=(\d+):(\w+) new=(\d+):(\w+) caller=(.+)$', ln)
        if t:
            streams[sid].append(f"TRANS {t.group(1)}:{t.group(2)} -> {t.group(3)}:{t.group(4)} | {t.group(5)}")
    elif "prepare_enter" in ln:
        t = re.search(r'state=(\d+):(\w+).*caller=(.+)$', ln)
        if t:
            streams[sid].append(f"PREPARE_ENTER {t.group(1)}:{t.group(2)} | {t.group(3)}")

for sid, evs in streams.items():
    print(f"=== stream {sid} ===")
    for e in evs:
        print(e)
    states = [e for e in evs if e.startswith("TRANS")]
    has_configured = any("-> 1:CONFIGURED" in e or "-> 1:CONFIGURED" in e for e in states)
    has_configured = any("new=1:CONFIGURED" in ln for ln in lines if sid in ln)
    has_enabled = any("new=3:ENABLED" in ln for ln in lines if sid in ln)
    prepare_from_alloc = any("PREPARE_ENTER 0:ALLOCATED" in e for e in evs)
    print(f"VERDICT: configured={has_configured} enabled={has_enabled} prepare_from_allocated={prepare_from_alloc}")
    if prepare_from_alloc and not has_configured:
        print("CLASS: Case A — prepare from ALLOCATED without prior CONFIGURED")
    elif has_configured and not has_enabled:
        print("CLASS: partial — CONFIGURED but never ENABLED")
    elif has_enabled:
        print("CLASS: Case B candidate — reached ENABLED (check runtime EIO separately)")
    else:
        print("CLASS: inconclusive")
    print()
PY

log "artifacts: $OUT"
echo "$OUT"

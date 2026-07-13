#!/usr/bin/env bash
# W6 — one delay value per S2 cycle (timing curve experiment).
#
# Sets deferred_reinit_ms, suspends, wakes, plays speaker-test, captures W6 logs.
#
# Usage:
#   sudo ./scripts/w6-deferred-reinit-sweep.sh --delay 1500
#   sudo ./scripts/w6-deferred-reinit-sweep.sh --port-prep   # event-driven mode
#   sudo ./scripts/w6-deferred-reinit-sweep.sh --delay 1000 --no-suspend  # post-S2 only
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
MOD_PARAM="/sys/module/snd_soc_tas2783_sdw/parameters"
DELAY_MS=""
PORT_PREP=0
DO_SUSPEND=1
DO_PLAY=1

usage() {
	sed -n '3,16p' "$0"
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	--delay) DELAY_MS="${2:-}"; shift 2 ;;
	--port-prep) PORT_PREP=1; shift ;;
	--no-suspend) DO_SUSPEND=0; shift ;;
	--no-play) DO_PLAY=0; shift ;;
	-h|--help) usage; exit 0 ;;
	*) echo "Unknown: $1" >&2; usage >&2; exit 1 ;;
	esac
done

if [[ "$PORT_PREP" -eq 0 && -z "$DELAY_MS" ]]; then
	echo "Provide --delay N or --port-prep" >&2
	exit 1
fi

if [[ ! -d "$MOD_PARAM" ]]; then
	echo "Module not loaded — rebuild W6 and reboot" >&2
	exit 1
fi

TS="$(date +%Y%m%d-%H%M%S)"
if [[ "$PORT_PREP" -eq 1 ]]; then
	LABEL="port-prep"
else
	LABEL="delay-${DELAY_MS}ms"
fi
OUT="${REPO}/validation/w6-${LABEL}-${TS}"
mkdir -p "$OUT"

exec > >(tee "${OUT}/run.log") 2>&1

echo "=== W6 deferred reinit sweep ==="
echo "time=$(date -Iseconds)"
echo "label=$LABEL"

echo
echo "==> Configure module params"
if [[ "$PORT_PREP" -eq 1 ]]; then
	echo 0 | tee "$MOD_PARAM/deferred_reinit_ms" >"${OUT}/param-deferred_reinit_ms.txt"
	echo 1 | tee "$MOD_PARAM/deferred_reinit_on_port_prep" >"${OUT}/param-deferred_reinit_on_port_prep.txt"
else
	echo 0 | tee "$MOD_PARAM/deferred_reinit_on_port_prep" >"${OUT}/param-deferred_reinit_on_port_prep.txt"
	echo "$DELAY_MS" | tee "$MOD_PARAM/deferred_reinit_ms" >"${OUT}/param-deferred_reinit_ms.txt"
fi
cat "$MOD_PARAM/deferred_reinit_ms" "$MOD_PARAM/deferred_reinit_on_port_prep" \
	>"${OUT}/params-after.txt"

if [[ "$DO_SUSPEND" -eq 1 ]]; then
	echo
	echo "==> S2 suspend (20s)"
	systemctl suspend || true
	sleep 20
fi

echo
echo "==> Post-resume kernel markers"
journalctl -k -b 0 --no-pager | grep -E 'W2 ctx=tas|W6 ctx=' \
	>"${OUT}/w6-kernel-pre-play.txt" || true
tail -20 "${OUT}/w6-kernel-pre-play.txt" || true

if [[ "$DO_PLAY" -eq 1 ]]; then
	echo
	if [[ "$PORT_PREP" -eq 1 ]]; then
		echo "==> speaker-test (triggers port PRE_PREP → W6 reinit)"
	else
		echo "==> Waiting for deferred reinit (${DELAY_MS}ms + margin)"
		sleep $(( DELAY_MS / 1000 + 2 ))
	fi
	echo "==> speaker-test hw:1,2 — confirm audio with your ears"
	speaker-test -D hw:1,2 -c 2 -r 48000 -t sine -f 440 -l 1 \
		2>&1 | tee "${OUT}/speaker-test.txt" || true
fi

journalctl -k -b 0 --no-pager | grep -E 'W2 ctx=tas|W6 ctx=' \
	>"${OUT}/w6-kernel-full.txt" || true

{
	echo "label=$LABEL"
	echo "deferred_reinit_ms=$(cat "$MOD_PARAM/deferred_reinit_ms")"
	echo "deferred_reinit_on_port_prep=$(cat "$MOD_PARAM/deferred_reinit_on_port_prep")"
	echo "suspend_count=$(journalctl -k -b 0 --no-pager | grep -c 'PM: suspend entry' || true)"
	echo "result=USER_CONFIRM_REQUIRED"
} >"${OUT}/meta.txt"

cat <<EOF

==> W6 sweep point saved: $OUT

Fill meta after listening:
  audio=PASS|FAIL in ${OUT}/meta.txt

Expected W6 log sequence (timer mode):
  W2 ctx=tas fn=force_fw_reinit when=...
  W6 ctx=schedule fn=deferred_reinit uid=N delay_ms=$DELAY_MS
  W6 ctx=deferred fn=fw_reinit uid=N ret=0

Port-prep mode:
  W6 ctx=arm fn=port_prep_reinit uid=N
  W6 ctx=port_prep fn=fw_reinit uid=N (on first speaker-test / hw_params path)
EOF

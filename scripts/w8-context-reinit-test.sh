#!/usr/bin/env bash
# W8 — one S2 cycle per 2nd-reinit trigger context (same fw_reinit(), different when).
#
# Modes (mutually exclusive — script clears others):
#   timer       — W6 delayed_work (requires --delay ms)
#   hw-params   — first hw_params after W2 (0 ms artificial delay)
#   port-prep   — first port PRE_PREP
#   dapm-pmu    — first DAPM POST_PMU on FU21
#
# Usage:
#   sudo ./scripts/w8-context-reinit-test.sh --mode hw-params
#   sudo ./scripts/w8-context-reinit-test.sh --mode timer --delay 1500
#   sudo ./scripts/w8-context-reinit-test.sh --mode port-prep
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
MOD="/sys/module/snd_soc_tas2783_sdw/parameters"
MODE=""
DELAY_MS=0
DO_SUSPEND=1
STOP_PW=1

usage() { sed -n '3,20p' "$0"; }

_pw_user_env() {
	PW_USER="${SUDO_USER:-${USER:-}}"
	[[ -n "$PW_USER" ]] || return 1
	PW_RT="/run/user/$(id -u "$PW_USER" 2>/dev/null || echo 0)"
	[[ -d "$PW_RT" ]] || return 1
	return 0
}

_pw_run() {
	[[ "$STOP_PW" -eq 1 ]] || return 0
	_pw_user_env || return 0
	sudo -u "$PW_USER" env XDG_RUNTIME_DIR="$PW_RT" systemctl --user "$@"
}

_pw_stop() {
	[[ "$STOP_PW" -eq 1 ]] || return 0
	echo "==> Stop + mask PipeWire (resume must not grab pcm2p before speaker-test)"
	_pw_run stop wireplumber pipewire pipewire-pulse 2>/dev/null || true
	_pw_run mask wireplumber pipewire pipewire-pulse 2>/dev/null || true
	sleep 1
}

_pw_start() {
	[[ "$STOP_PW" -eq 1 ]] || return 0
	echo "==> Unmask + start PipeWire"
	_pw_run unmask wireplumber pipewire pipewire-pulse 2>/dev/null || true
	_pw_run start pipewire pipewire-pulse wireplumber 2>/dev/null || true
}

_pcm_release() {
	local st pid
	st="$(cat /proc/asound/card1/pcm2p/sub0/status 2>/dev/null || true)"
	if [[ "$st" == *"state: RUNNING"* || "$st" == *"state: PREPARED"* || "$st" == *"state: OPEN"* ]]; then
		pid="$(awk '/owner_pid/ {print $3}' <<<"$st")"
		echo "==> PCM busy (owner_pid=${pid:-?}) — stop PipeWire again"
		_pw_run stop wireplumber pipewire pipewire-pulse 2>/dev/null || true
		sleep 1
		if [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null; then
			echo "   kill $pid"
			kill "$pid" 2>/dev/null || true
			sleep 0.5
		fi
	fi
}

_wait_second_reinit() {
	# W2 blocks ~2.7s for both chips; 2nd reinit adds ~3s each — poll up to 20s.
	local i u8 u11 w8
	echo "==> Wait for 2nd fw_reinit complete (both uid 8+11 if timer/W8)"
	for i in $(seq 1 40); do
		u8="$(journalctl -k -b 0 --no-pager 2>/dev/null | grep -E 'W6 ctx=deferred fn=fw_reinit uid=8 ret=0|W8 ctx=.* fn=fw_reinit uid=8 ret=0' | tail -1 || true)"
		u11="$(journalctl -k -b 0 --no-pager 2>/dev/null | grep -E 'W6 ctx=deferred fn=fw_reinit uid=11 ret=0|W8 ctx=.* fn=fw_reinit uid=11 ret=0' | tail -1 || true)"
		w8="$(journalctl -k -b 0 --no-pager 2>/dev/null | grep 'W8 ctx=hw_params fn=fw_reinit uid=8 ret=0' | tail -1 || true)"
		if [[ -n "$u8$u11$w8" ]]; then
			# timer: need both; hw-params: w8 line enough for uid8 path
			if [[ "$MODE" == timer && -n "$u8" && -n "$u11" ]]; then
				echo "   both uid reinit ret=0 (${i}x0.5s)"
				return 0
			fi
			if [[ "$MODE" != timer && -n "$w8$u8$u11" ]]; then
				echo "   reinit marker seen (${i}x0.5s)"
				return 0
			fi
		fi
		sleep 0.5
	done
	echo "   (timeout — check kernel.txt for ret=-11 / end_err)"
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	--mode) MODE="${2:-}"; shift 2 ;;
	--delay) DELAY_MS="${2:-0}"; shift 2 ;;
	--no-suspend) DO_SUSPEND=0; shift ;;
	--keep-pw) STOP_PW=0; shift ;;
	-h|--help) usage; exit 0 ;;
	*) echo "Unknown: $1" >&2; exit 1 ;;
	esac
done

[[ -n "$MODE" ]] || { usage >&2; exit 1; }
[[ -d "$MOD" ]] || { echo "Module not loaded" >&2; exit 1; }

clear_params() {
	echo 0 >"$MOD/deferred_reinit_ms"
	echo 0 >"$MOD/deferred_reinit_on_hw_params"
	echo 0 >"$MOD/deferred_reinit_on_port_prep"
	echo 0 >"$MOD/deferred_reinit_on_dapm_pmu"
}

case "$MODE" in
timer)
	[[ "$DELAY_MS" -gt 0 ]] || { echo "timer mode needs --delay N" >&2; exit 1; }
	;;
hw-params|port-prep|dapm-pmu) ;;
*) echo "Unknown mode: $MODE" >&2; exit 1 ;;
esac

TS="$(date +%Y%m%d-%H%M%S)"
OUT="${REPO}/validation/w8-${MODE}-${TS}"
mkdir -p "$OUT"

exec > >(tee "${OUT}/run.log") 2>&1

echo "=== W8 context reinit test ==="
echo "time=$(date -Iseconds) mode=$MODE delay=${DELAY_MS}ms"

clear_params
case "$MODE" in
timer) echo "$DELAY_MS" >"$MOD/deferred_reinit_ms" ;;
hw-params) echo 1 >"$MOD/deferred_reinit_on_hw_params" ;;
port-prep) echo 1 >"$MOD/deferred_reinit_on_port_prep" ;;
dapm-pmu) echo 1 >"$MOD/deferred_reinit_on_dapm_pmu" ;;
esac
cat "$MOD"/deferred_reinit_* >"${OUT}/params.txt"

_pw_stop

if [[ "$DO_SUSPEND" -eq 1 ]]; then
	echo "==> S2 suspend"
	systemctl suspend || true
	sleep 3
	# Resume often restarts masked units via socket activation — re-stop before pcm open.
	_pw_run stop wireplumber pipewire pipewire-pulse 2>/dev/null || true
	sleep 2
fi

if [[ "$MODE" == timer && "$DELAY_MS" -gt 0 ]]; then
	# W2 ~2.7s + delay + 2nd reinit ~3s per chip
	echo "==> Waiting for timer reinit (W2 ~2.7s + ${DELAY_MS}ms + 2nd init)"
	sleep $(( DELAY_MS / 1000 + 6 ))
	_wait_second_reinit || true
else
	# W2 serial reinit ~2.7s; speaker-test must be first hw_params opener for W8.
	echo "==> Wait W2 (~3s) then speaker-test opens pcm → W8 hw_params"
	sleep 3
fi

_pcm_release

echo "==> speaker-test hw:1,2 (PipeWire masked — opens pcm for W8 + audio check)"
# -l 3: three ~59 ms periods per channel; -l 1 is too easy to miss Left then Right.
speaker-test -D hw:1,2 -c 2 -r 48000 -t sine -f 440 -l 3 \
	2>&1 | tee "${OUT}/speaker-test.txt" || true

_wait_second_reinit || true

_pw_start

journalctl -k -b 0 --no-pager | grep -E 'W2 ctx=tas|W6 ctx=|W8 ctx=|W7 ctx=ts' \
	>"${OUT}/kernel.txt" || true

"${SCRIPT_DIR}/w7-ts-capture.sh" --last-s2 >"${OUT}/w7-timeline.txt" 2>/dev/null || true

{
	echo "mode=$MODE"
	echo "delay_ms=$DELAY_MS"
	echo "result=USER_CONFIRM_REQUIRED"
} >"${OUT}/meta.txt"

cat <<EOF

==> Saved: $OUT
Mark audio=PASS|FAIL in ${OUT}/meta.txt

Interpretation:
  hw-params PASS with 0 ms delay → pipeline milestone, not sleep
  timer PASS only at 1500+ ms     → stabilization window
  dapm-pmu PASS                   → DAPM/ASoC ordering hypothesis
EOF

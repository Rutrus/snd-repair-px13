#!/usr/bin/env bash
# KPI-U — post-S2 user-path witness (PipeWire / GNOME contract).
#
# Run after suspend → resume, 30–45 s settle. Do NOT restart PipeWire.
#
# Usage:
#   ./scripts/post-s2-user-witness.sh
#   ./scripts/post-s2-user-witness.sh --out-dir validation/post-s2-user-witness/TIMESTAMP
#
# Pass: pw-record default + headset (if present) produce valid WAVs; playback probe OK.
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${SND_REPAIR_REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"
OUT_DIR=""
RECORD_SEC="${KPI_U_RECORD_SEC:-3}"
UID_SELF="$(id -u)"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID_SELF}"

while [[ $# -gt 0 ]]; do
	case "$1" in
	--out-dir) OUT_DIR="$2"; shift 2 ;;
	-h|--help)
		sed -n '3,12p' "$0"
		exit 0
		;;
	*) echo "Unknown: $1" >&2; exit 1 ;;
	esac
done

TS="$(date -Iseconds)"
TS_FILE="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="${OUT_DIR:-${REPO}/validation/post-s2-user-witness/${TS_FILE}}"
mkdir -p "$OUT_DIR"

exec > >(tee "${OUT_DIR}/witness.log") 2>&1

echo "=== KPI-U POST-S2 USER WITNESS ==="
echo "time=$TS"
echo "output_dir=$OUT_DIR"
echo "RULE: PipeWire must stay running — do not restart wireplumber/pipewire before this run."
echo

need_cmd() {
	command -v "$1" >/dev/null 2>&1 || {
		echo "FAIL: missing command $1"
		exit 1
	}
}

need_cmd wpctl
need_cmd pw-record

if ! systemctl --user is-active --quiet pipewire 2>/dev/null; then
	echo "FAIL: pipewire not active"
	echo "kpi_u=FAIL reason=pipewire_inactive" > "${OUT_DIR}/kpi-u.txt"
	exit 1
fi

echo "--- wpctl status ---"
wpctl status 2>&1 | tee "${OUT_DIR}/wpctl-status.txt" | sed -n '/Audio/,/^Video/p' | head -40 || true
echo

_default_source_id() {
	wpctl status 2>/dev/null | awk '
		/^Audio/ { in_audio=1 }
		in_audio && /Sources:/ { in_src=1; next }
		in_src && /^(Settings|Video|$)/ { exit }
		in_src && /^\s*[├└│]/ && !/\*/ && /Microphone/ { next }
		in_src && /\*/ && /Microphone/ {
			if (match($0, /\*[[:space:]]+([0-9]+)/, a)) { print a[1]; exit }
		}
	'
}

_headset_source_id() {
	wpctl status 2>/dev/null | awk '
		/^Audio/ { in_audio=1 }
		in_audio && /Sources:/ { in_src=1; next }
		in_src && /^(Settings|Video|$)/ { exit }
		in_src && /Headset Microphone/ {
			if (match($0, /[[:space:]]([0-9]+)\.[[:space:]]/, a)) { print a[1]; exit }
		}
	'
}

_default_sink_id() {
	wpctl status 2>/dev/null | awk '
		/^Audio/ { in_audio=1 }
		in_audio && /Sinks:/ { in_snk=1; next }
		in_snk && /Sources:/ { exit }
		in_snk && /\*/ && /Speaker|Headphones/ {
			if (match($0, /\*[[:space:]]+([0-9]+)/, a)) { print a[1]; exit }
		}
	'
}

_wav_ok() {
	local f="$1" min="${2:-4096}"
	[[ -f "$f" ]] || return 1
	local sz
	sz="$(stat -c%s "$f" 2>/dev/null || echo 0)"
	[[ "$sz" -ge "$min" ]] || return 1
	file "$f" 2>/dev/null | grep -qi 'WAVE audio' || return 1
	return 0
}

_pcm_snapshot() {
	local label="$1" pcm_proc="$2"
	[[ -r "$pcm_proc" ]] || return 0
	echo "=== $label $pcm_proc ==="
	cat "$pcm_proc" 2>/dev/null || true
	echo
}

record_pw() {
	local id="$1" name="$2" out="$3"
	local log="${OUT_DIR}/pw-record-${name}.log"
	echo "--- pw-record target=$id ($name) ${RECORD_SEC}s ---"
	if pw-record --target="$id" "$out" >"$log" 2>&1 &
	then
		local pid=$!
		sleep "$RECORD_SEC"
		kill -INT "$pid" 2>/dev/null || true
		wait "$pid" 2>/dev/null || true
	fi
	if _wav_ok "$out"; then
		echo "RESULT ${name}=PASS size=$(stat -c%s "$out")"
		return 0
	fi
	echo "RESULT ${name}=FAIL"
	tail -5 "$log" 2>/dev/null || true
	return 1
}

int_ok=0 hs_ok=0 pb_ok=0 hs_skip=0

def_src="$(_default_source_id || true)"
def_snk="$(_default_sink_id || true)"
hs_src="$(_headset_source_id || true)"

echo "default_source_id=${def_src:-none} default_sink_id=${def_snk:-none} headset_source_id=${hs_src:-none}"
echo

if [[ -n "$def_src" ]]; then
	wpctl inspect "$def_src" 2>&1 | tee "${OUT_DIR}/wpctl-inspect-default-source.txt" | head -30 || true
	echo
	if record_pw "$def_src" "internal-mic" "${OUT_DIR}/internal-mic.wav"; then
		int_ok=1
	fi
else
	echo "FAIL: no default audio source"
fi

if [[ -n "$hs_src" && "$hs_src" != "$def_src" ]]; then
	if record_pw "$hs_src" "headset-mic" "${OUT_DIR}/headset-mic.wav"; then
		hs_ok=1
	fi
else
	echo "NOTE: Headset Microphone not listed or same as default — skip"
	hs_skip=1
	hs_ok=1
fi

_pcm_snapshot "during/after internal" /proc/asound/card1/pcm4c/sub0/status
_pcm_snapshot "rt721 capture" /proc/asound/card1/pcm1c/sub0/status

echo "--- playback (pw-play bell) ---"
BELL="/usr/share/sounds/freedesktop/stereo/bell.oga"
if [[ -n "$def_snk" && -f "$BELL" ]] && command -v pw-play >/dev/null; then
	if pw-play --target="$def_snk" "$BELL" >"${OUT_DIR}/pw-play.log" 2>&1; then
		pb_ok=1
		echo "RESULT playback=PASS"
	else
		echo "RESULT playback=FAIL"
		tail -3 "${OUT_DIR}/pw-play.log" || true
	fi
else
	echo "NOTE: pw-play skipped (no sink, bell file, or pw-play)"
	pb_ok=1
fi
echo

kpi_u=FAIL
[[ "$int_ok" -eq 1 && "$hs_ok" -eq 1 && "$pb_ok" -eq 1 ]] && kpi_u=PASS

cat > "${OUT_DIR}/kpi-u.txt" <<EOF
kpi_u=$kpi_u
time=$TS
default_source_id=${def_src:-}
default_sink_id=${def_snk:-}
headset_source_id=${hs_src:-}
headset_skipped=$hs_skip
internal_mic_record=$int_ok
headset_mic_record=$hs_ok
playback=$pb_ok
EOF
cat "${OUT_DIR}/kpi-u.txt"
echo
echo "=> KPI-U: $kpi_u"
echo "witness complete: $OUT_DIR"

[[ "$kpi_u" == PASS ]]

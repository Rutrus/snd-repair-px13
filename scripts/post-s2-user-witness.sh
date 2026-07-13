#!/usr/bin/env bash
# KPI-U — post-S2 user-path witness (PipeWire / GNOME contract).
#
# Run after suspend → resume, 30–45 s settle. Do NOT restart PipeWire.
#
# Usage:
#   ./scripts/post-s2-user-witness.sh
#   ./scripts/post-s2-user-witness.sh --no-audible-confirm   # automation (weaker)
#
# Playback PASS requires SmartAmp PCM RUNNING + hw_ptr delta during probe.
# Interactive default: prompt to confirm you HEARD the test tone (prevents silent playback false PASS).
#
# Env:
#   KPI_U_RECORD_SEC=3
#   KPI_U_PLAYBACK_MIN_HWPTR=8192
#   KPI_U_AUDIBLE_CONFIRM=1|0   (default: 1 if stdin is a TTY, else 0)
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${SND_REPAIR_REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"
OUT_DIR=""
RECORD_SEC="${KPI_U_RECORD_SEC:-3}"
PLAYBACK_MIN_HWPTR="${KPI_U_PLAYBACK_MIN_HWPTR:-8192}"
AUDIBLE_CONFIRM="${KPI_U_AUDIBLE_CONFIRM:-}"
UID_SELF="$(id -u)"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID_SELF}"

while [[ $# -gt 0 ]]; do
	case "$1" in
	--out-dir) OUT_DIR="$2"; shift 2 ;;
	--no-audible-confirm) AUDIBLE_CONFIRM=0; shift ;;
	--audible-confirm) AUDIBLE_CONFIRM=1; shift ;;
	-h|--help)
		sed -n '3,18p' "$0"
		exit 0
		;;
	*) echo "Unknown: $1" >&2; exit 1 ;;
	esac
done

if [[ -z "$AUDIBLE_CONFIRM" ]]; then
	if [[ -t 0 ]]; then
		AUDIBLE_CONFIRM=1
	else
		AUDIBLE_CONFIRM=0
	fi
fi

TS="$(date -Iseconds)"
TS_FILE="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="${OUT_DIR:-${REPO}/validation/post-s2-user-witness/${TS_FILE}}"
mkdir -p "$OUT_DIR"

exec > >(tee "${OUT_DIR}/witness.log") 2>&1

echo "=== KPI-U POST-S2 USER WITNESS ==="
echo "time=$TS"
echo "output_dir=$OUT_DIR"
echo "playback_min_hwptr=$PLAYBACK_MIN_HWPTR audible_confirm=$AUDIBLE_CONFIRM"
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
need_cmd speaker-test

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

_pcm_status_field() {
	local proc="$1" field="$2"
	[[ -r "$proc" ]] || return 1
	grep -E "^${field}[[:space:]]*:" "$proc" 2>/dev/null | head -1 | sed -n 's/^[^:]*:[[:space:]]*//p'
}

_soundwire_card() {
	awk '/amdsoundwire|amd-soundwire/ { print $1; exit }' /proc/asound/cards 2>/dev/null
}

_smartamp_playback_proc() {
	local card="${1:-$(_soundwire_card)}"
	[[ -n "$card" ]] || return 1
	echo "/proc/asound/card${card}/pcm2p/sub0/status"
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

probe_playback() {
	local def_snk="$1"
	local pcm_proc log
	local hwptr_ok=0 confirm_ok=0 dummy_ok=1
	local h0 h1 st0 st1 delta rc=0

	log="${OUT_DIR}/playback-probe.log"
	pcm_proc="$(_smartamp_playback_proc || true)"

	echo "--- playback probe (SmartAmp hw_ptr + optional audible confirm) ---"

	if wpctl status 2>/dev/null | grep -qiE 'Dummy Output|Dummy-Driver'; then
		dummy_ok=0
		echo "RESULT playback_dummy=FAIL (Dummy Output present)"
	else
		echo "RESULT playback_dummy=PASS"
	fi

	if [[ -z "$def_snk" ]]; then
		echo "RESULT playback=FAIL reason=no_default_sink"
		echo "playback_hwptr=0 playback_audible_confirm=0 playback_dummy=$dummy_ok" \
			> "${OUT_DIR}/playback-probe.txt"
		return 1
	fi

	if [[ -z "$pcm_proc" || ! -r "$pcm_proc" ]]; then
		echo "WARN: SmartAmp pcm2p status not found — hw_ptr gate skipped"
		pcm_proc=""
	fi

	# ~3 s 440 Hz left via PipeWire (same path as GNOME / apps)
	speaker-test -D pipewire -c 2 -r 48000 -t sine -f 440 -l 1 -s 1 >"$log" 2>&1 &
	local pid=$!
	sleep 1

	if [[ -n "$pcm_proc" ]]; then
		st0="$(_pcm_status_field "$pcm_proc" state || echo closed)"
		h0="$(_pcm_status_field "$pcm_proc" hw_ptr || echo 0)"
		h0="${h0//[^0-9]/}"
		h0="${h0:-0}"
		echo "playback t+1s: pcm2p state=$st0 hw_ptr=$h0"
		cat "$pcm_proc" > "${OUT_DIR}/playback-during-status.txt" 2>/dev/null || true
		sleep 2
		st1="$(_pcm_status_field "$pcm_proc" state || echo closed)"
		h1="$(_pcm_status_field "$pcm_proc" hw_ptr || echo 0)"
		h1="${h1//[^0-9]/}"
		h1="${h1:-0}"
		echo "playback t+3s: pcm2p state=$st1 hw_ptr=$h1"
		delta=$((h1 - h0))
		echo "playback hw_ptr_delta=$delta (min=$PLAYBACK_MIN_HWPTR)"
		if [[ "$st0" == RUNNING || "$st1" == RUNNING ]] && [[ "$delta" -ge "$PLAYBACK_MIN_HWPTR" ]]; then
			hwptr_ok=1
			echo "RESULT playback_hwptr=PASS"
		else
			echo "RESULT playback_hwptr=FAIL (not RUNNING or delta too small)"
		fi
	else
		hwptr_ok=0
		echo "RESULT playback_hwptr=FAIL (pcm2p status unavailable)"
	fi

	wait "$pid" || rc=$?
	if [[ "$rc" -ne 0 ]]; then
		echo "RESULT playback_speaker_test=FAIL rc=$rc"
		tail -5 "$log" || true
		hwptr_ok=0
	else
		echo "RESULT playback_speaker_test=PASS rc=0"
	fi

	if [[ "$AUDIBLE_CONFIRM" -eq 1 ]]; then
		echo
		echo ">>> Se ha reproducido un tono 440 Hz (canal izquierdo) por PipeWire."
		if read -r -p ">>> ¿Lo has OÍDO? [y/N] " ans; then
			if [[ "$ans" =~ ^[Yy]$ ]]; then
				confirm_ok=1
				echo "RESULT playback_audible_confirm=PASS"
			else
				echo "RESULT playback_audible_confirm=FAIL (user did not hear tone)"
			fi
		else
			echo "RESULT playback_audible_confirm=FAIL (no input)"
		fi
	else
		confirm_ok=1
		echo "RESULT playback_audible_confirm=SKIP (use TTY or drop --no-audible-confirm for ear check)"
	fi

	{
		echo "playback_hwptr=$hwptr_ok"
		echo "playback_audible_confirm=$confirm_ok"
		echo "playback_dummy=$dummy_ok"
		echo "playback_speaker_test_rc=$rc"
		echo "hw_ptr_delta=${delta:-0}"
	} > "${OUT_DIR}/playback-probe.txt"

	[[ "$dummy_ok" -eq 1 && "$hwptr_ok" -eq 1 && "$confirm_ok" -eq 1 ]]
}

int_ok=0 hs_ok=0 pb_ok=0 hs_skip=0
pb_hwptr=0 pb_confirm=0 pb_dummy=1

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

if probe_playback "$def_snk"; then
	pb_ok=1
	echo "RESULT playback=PASS"
else
	echo "RESULT playback=FAIL"
fi

if [[ -f "${OUT_DIR}/playback-probe.txt" ]]; then
	pb_hwptr="$(grep '^playback_hwptr=' "${OUT_DIR}/playback-probe.txt" | cut -d= -f2)"
	pb_confirm="$(grep '^playback_audible_confirm=' "${OUT_DIR}/playback-probe.txt" | cut -d= -f2)"
	pb_dummy="$(grep '^playback_dummy=' "${OUT_DIR}/playback-probe.txt" | cut -d= -f2)"
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
playback_hwptr=$pb_hwptr
playback_audible_confirm=$pb_confirm
playback_dummy=$pb_dummy
audible_confirm_mode=$AUDIBLE_CONFIRM
EOF
cat "${OUT_DIR}/kpi-u.txt"
echo
echo "=> KPI-U: $kpi_u"
if [[ "$AUDIBLE_CONFIRM" -eq 0 ]]; then
	echo "NOTE: audible confirm skipped — silent playback may still false PASS; re-run on a TTY or omit --no-audible-confirm"
fi
echo "witness complete: $OUT_DIR"

[[ "$kpi_u" == PASS ]]

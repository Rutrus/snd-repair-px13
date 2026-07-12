#!/usr/bin/env bash
# Post-S2 full card witness — Phase A (untouched) OR Phase B (after userspace recovery).
# NEVER mix both phases in one run.
#
# Usage:
#   Phase A — after resume, do not touch PipeWire:
#     ./scripts/post-s2-card-witness.sh --phase-a
#     ./scripts/post-s2-card-witness.sh          # default = phase-a
#
#   Phase B — only AFTER explicit userspace recovery (e.g. wireplumber restart):
#     systemctl --user restart wireplumber pipewire
#     ./scripts/post-s2-card-witness.sh --phase-b
#
#   Legacy --functional (direct ALSA — KPI-K style, NOT user KPI):
#     ./scripts/post-s2-card-witness.sh --phase-a --functional
#   Prefer:
#     ./scripts/post-s2-user-witness.sh      # KPI-U (PipeWire path)
#     ./scripts/post-s2-kernel-witness.sh    # KPI-K (direct hw:)
#   See: research/experiments/kpi-u-vs-kpi-k-20260712.md
#
# Env:
#   SND_REPAIR_REPO     — output under validation/post-s2-witness/
#   POST_S2_WITNESS_DIR — override output directory
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${SND_REPAIR_REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"
PHASE="a"
OUT_DIR=""
FUNCTIONAL=0

while [[ $# -gt 0 ]]; do
	case "$1" in
	--phase-a|-a) PHASE="a"; shift ;;
	--phase-b|-b) PHASE="b"; shift ;;
	--functional|-f) FUNCTIONAL=1; shift ;;
	--out-dir) OUT_DIR="$2"; shift 2 ;;
	-h|--help)
		sed -n '3,18p' "$0"
		exit 0
		;;
	*) echo "Unknown: $1" >&2; exit 1 ;;
	esac
done

TS="$(date -Iseconds)"
TS_FILE="$(date +%Y%m%d-%H%M%S)"
UID_SELF="$(id -u)"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID_SELF}"

if [[ -z "$OUT_DIR" ]]; then
	OUT_DIR="${REPO}/validation/post-s2-witness/phase-${PHASE}-${TS_FILE}"
fi
mkdir -p "$OUT_DIR"

exec > >(tee "${OUT_DIR}/witness.log") 2>&1

echo "=== POST-S2 FULL CARD WITNESS ==="
echo "time=$TS phase=$PHASE (A=post-resume untouched, B=after userspace recovery)"
echo "output_dir=$OUT_DIR"
echo

if [[ "$PHASE" == "a" ]]; then
	echo "RULE: Phase A — do NOT restart wireplumber/pipewire before this run."
else
	echo "RULE: Phase B — run ONLY after explicit userspace recovery step."
fi
echo

echo "--- px13 ---"
systemctl is-enabled px13-audio-resume.service 2>&1 || true
journalctl -b -u px13-audio-resume.service --no-pager 2>&1 | tail -5 || true
echo

echo "--- ALSA: aplay -l ---"
aplay -l 2>&1 || true
echo

echo "--- ALSA: arecord -l ---"
arecord -l 2>&1 || true
echo

echo "--- ALSA: arecord -L (head) ---"
arecord -L 2>&1 | head -40 || true
echo

echo "--- ALSA: /proc/asound/pcm ---"
cat /proc/asound/pcm 2>&1 || true
cp -f /proc/asound/pcm "${OUT_DIR}/proc-asound-pcm.txt" 2>/dev/null || true
echo

echo "--- UCM ---"
CARD="$(awk '/ProArtPX13|amdsoundwire/ {print $1; exit}' /proc/asound/cards 2>/dev/null || true)"
echo "card_id=$CARD"
alsaucm listcards 2>&1 || true
if [[ -n "$CARD" ]]; then
	alsaucm -c "$CARD" list _devices 2>&1 || true
	alsaucm -c "$CARD" dump 2>&1 | tee "${OUT_DIR}/ucm-dump.txt" | head -80 || true
fi
echo

echo "--- PipeWire: wpctl ---"
if [[ -d "$XDG_RUNTIME_DIR" ]] && command -v wpctl >/dev/null; then
	wpctl status 2>&1 | tee "${OUT_DIR}/wpctl-status.txt" | sed -n '/Audio/,/^Video/p' | head -35 || true
else
	echo "(no user runtime / wpctl)"
fi
echo

echo "--- PipeWire: pactl ---"
if [[ -d "$XDG_RUNTIME_DIR" ]] && command -v pactl >/dev/null; then
	pactl list short sinks 2>&1 | tee "${OUT_DIR}/pactl-sinks.txt" || true
	pactl list short sources 2>&1 | tee "${OUT_DIR}/pactl-sources.txt" || true
else
	echo "(no pactl)"
fi
echo

echo "--- PipeWire: pw-cli (capture-related) ---"
if [[ -d "$XDG_RUNTIME_DIR" ]] && command -v pw-cli >/dev/null; then
	pw-cli ls Node 2>/dev/null | grep -iE 'Capture|Microphone|Source|Sink|Speaker|Dummy|node.name|node.description' \
		| tee "${OUT_DIR}/pw-cli-nodes.txt" | head -50 || true
else
	echo "(no pw-cli)"
fi
echo

echo "--- PipeWire: pw-dump ---"
if [[ -d "$XDG_RUNTIME_DIR" ]] && command -v pw-dump >/dev/null; then
	pw-dump > "${OUT_DIR}/pw-dump.json" 2>&1 || echo "(pw-dump failed)" >&2
	echo "wrote ${OUT_DIR}/pw-dump.json"
else
	echo "(no pw-dump)"
fi
echo

echo "--- KPI: topology ---"
has_pb=0 has_cap=0 has_pw_spk=0 has_pw_src=0 has_dummy=0
grep -q 'playback' /proc/asound/pcm 2>/dev/null && has_pb=1
grep -q 'capture' /proc/asound/pcm 2>/dev/null && has_cap=1
wpctl status 2>/dev/null | grep -q 'Speaker' && has_pw_spk=1 || true
wpctl status 2>/dev/null | grep -qiE 'Microphone|Headset' && has_pw_src=1 || true
wpctl status 2>/dev/null | grep -q 'Dummy Output' && has_dummy=1 || true
echo "alsa_playback_pcm=$has_pb alsa_capture_pcm=$has_cap pw_speaker=$has_pw_spk pw_source=$has_pw_src pw_dummy=$has_dummy"
echo

func_pb=-1 func_cap=-1
if [[ "$FUNCTIONAL" -eq 1 ]]; then
	echo "--- KPI: functional (SmartAmp hw:1,2 + RT721 cap hw:1,1) ---"
	echo "--- fuser /dev/snd (ALSA exclusive check) ---"
	fuser -v /dev/snd/* 2>&1 | head -20 || true
	pcm12_busy=0
	if fuser /dev/snd/pcmC1D2p 2>/dev/null | grep -q .; then
		pcm12_busy=1
		echo "WARN: pcmC1D2p busy — PipeWire may hold hw:1,2 (EBUSY -16)"
		echo "      For direct ALSA: systemctl --user stop wireplumber pipewire pipewire-pulse"
		echo "      Or test desktop path: pw-play /usr/share/sounds/freedesktop/stereo/bell.oga"
	fi
	echo
	if grep -q '01-02.*playback' /proc/asound/pcm 2>/dev/null; then
		if speaker-test -D hw:1,2 -c 2 -r 48000 -t sine -l 1 \
			>"${OUT_DIR}/speaker-test-hw12.log" 2>&1; then
			func_pb=1
		else
			func_pb=0
			echo "speaker-test hw:1,2 FAILED (see speaker-test-hw12.log)"
			tail -5 "${OUT_DIR}/speaker-test-hw12.log" || true
		fi
	else
		func_pb=0
		echo "speaker-test hw:1,2 skipped — PCM missing"
	fi
	if grep -q '01-01.*capture' /proc/asound/pcm 2>/dev/null; then
		if arecord -D hw:1,1 -f S16_LE -r 48000 -c 2 -d 2 \
			"${OUT_DIR}/capture-hw11.wav" >"${OUT_DIR}/arecord-hw11.log" 2>&1; then
			func_cap=1
		else
			func_cap=0
			echo "arecord hw:1,1 FAILED (see arecord-hw11.log)"
			tail -5 "${OUT_DIR}/arecord-hw11.log" || true
		fi
	else
		func_cap=0
	fi
	echo "func_playback_hw12=$func_pb func_capture_hw11=$func_cap"
	echo
fi

cat > "${OUT_DIR}/kpi-flags.txt" <<EOF
phase=$PHASE
time=$TS
alsa_playback_pcm=$has_pb
alsa_capture_pcm=$has_cap
pw_speaker_sink=$has_pw_spk
pw_source=$has_pw_src
pw_dummy_default=$has_dummy
func_playback_hw12=$func_pb
func_capture_hw11=$func_cap
EOF
cat "${OUT_DIR}/kpi-flags.txt"
echo

topo_ok=0
[[ "$has_pb" -eq 1 && "$has_cap" -eq 1 && "$has_pw_spk" -eq 1 && "$has_pw_src" -eq 1 ]] && topo_ok=1

if [[ "$has_pb" -eq 1 && "$has_cap" -eq 0 ]]; then
	echo "=> topology category 1: kernel capture (RT721 / ASoC)"
elif [[ "$has_pb" -eq 1 && "$has_cap" -eq 1 && ( "$has_pw_spk" -eq 0 || "$has_pw_src" -eq 0 ) ]]; then
	echo "=> topology category 2: ALSA visible, PipeWire incomplete"
elif [[ "$topo_ok" -eq 1 ]]; then
	echo "=> topology category 4: ALSA + PipeWire nodes present"
fi

if [[ "$topo_ok" -eq 1 && "$FUNCTIONAL" -eq 0 ]]; then
	echo "=> topology OK — run --functional to confirm audible playback (topology alone is NOT PASS)"
elif [[ "$topo_ok" -eq 1 && "$func_pb" -eq 1 && ( "$func_cap" -eq 1 || "$func_cap" -eq -1 ) ]]; then
	echo "=> FULL PASS — topology + SmartAmp playback OK"
elif [[ "$func_pb" -eq 0 ]]; then
	echo "=> FUNCTIONAL FAIL — SmartAmp stream (hw:1,2); likely mid-stream EIO / hw_ptr stall (not -EINVAL)"
	echo "   next: resolution/scripts/witness-stream-hang.sh during speaker-test; dmesg | grep -iE tas2783|sdw"
elif [[ "$PHASE" == "a" && "$has_pb" -eq 1 && "$has_cap" -eq 1 && "$has_pw_spk" -eq 0 ]]; then
	echo "=> Phase A partial — run Phase B: systemctl --user restart wireplumber pipewire"
fi

echo
echo "witness complete: $OUT_DIR"

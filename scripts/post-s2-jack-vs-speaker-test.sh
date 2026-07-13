#!/usr/bin/env bash
# E1 — discriminate jack vs internal speakers after S2.
#
# Plug headphones BEFORE running. Close other audio apps if hw:1,2 is busy.
#
# Usage:
#   ./scripts/post-s2-jack-vs-speaker-test.sh
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT="${REPO}/validation/jack-vs-speaker-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"

exec > >(tee "${OUT}/run.log") 2>&1

echo "=== E1 jack vs speaker discrimination ==="
echo "time=$(date -Iseconds)"
echo "suspend_count=$(journalctl -k -b 0 --no-pager 2>/dev/null | grep -c 'PM: suspend entry' || true)"
echo

wpctl status 2>&1 | sed -n '/Audio/,/^Video/p' | tee "${OUT}/wpctl.txt"

_sink_id() {
	local pattern="$1"
	wpctl status 2>/dev/null | awk -v pat="$pattern" '
		/^Audio/ { in_audio=1 }
		in_audio && /Sinks:/ { in_snk=1; next }
		in_snk && /Sources:/ { exit }
		in_snk && $0 ~ pat {
			if (match($0, /[[:space:]]([0-9]+)\.[[:space:]]/, a)) { print a[1]; exit }
		}
	'
}

SPK_ID="$(_sink_id 'Audio Coprocessor Speaker' || true)"
HP_ID="$(_sink_id 'Audio Coprocessor Headphones' || true)"

echo "speaker_sink_id=${SPK_ID:-none} headphone_sink_id=${HP_ID:-none}"
echo

{
	echo "=== Headphone Jack (CARD numid=15) ==="
	amixer -c 1 cget numid=15 2>&1 || true
	echo "=== Headphone Switch ==="
	amixer -c 1 cget name='Headphone Switch' 2>&1 || true
} | tee "${OUT}/jack-detect.txt"
echo

_ear_prompt() {
	local label="$1"
	echo
	echo ">>> $label — tono 440 Hz, ~3 s"
	read -r -p ">>> ¿OÍSTE el tono? [y/N] " ans
	if [[ "$ans" =~ ^[Yy]$ ]]; then echo "heard=yes"; return 0; fi
	echo "heard=no"
	return 1
}

heard_spk=no heard_hp=no heard_hw12=skip heard_hw10=no

if [[ -n "$SPK_ID" ]]; then
	echo "--- speaker-test → Speaker sink id=$SPK_ID ---"
	wpctl set-default "$SPK_ID" 2>&1 | tee -a "${OUT}/wpctl-set-default.log" || true
	timeout 6 speaker-test -D pipewire -c 2 -r 48000 -t sine -f 440 -l 1 -s 1 \
		| tee "${OUT}/speaker-test-spk.log" || true
	_ear_prompt "Altavoces integrados (Speaker)" && heard_spk=yes || heard_spk=no
else
	echo "WARN: Speaker sink id not found"
fi

if [[ -n "$HP_ID" ]]; then
	echo "--- speaker-test → Headphones sink id=$HP_ID ---"
	wpctl set-default "$HP_ID" 2>&1 | tee -a "${OUT}/wpctl-set-default.log" || true
	timeout 6 speaker-test -D pipewire -c 2 -r 48000 -t sine -f 440 -l 1 -s 1 \
		| tee "${OUT}/speaker-test-hp.log" || true
	_ear_prompt "Auriculares (jack)" && heard_hp=yes || heard_hp=no
else
	echo "WARN: Headphones sink id not found"
fi

# Direct ALSA — release PipeWire hold on SmartAmp if busy
echo "--- ALSA direct: plughw:1,2 (SmartAmp) ---"
if timeout 6 speaker-test -D plughw:1,2 -c 2 -r 48000 -t sine -f 440 -l 1 -s 1 \
	>"${OUT}/speaker-test-hw12.log" 2>&1; then
	read -r -p ">>> plughw:1,2 (SmartAmp directo) — ¿OÍSTE? [y/N] " ans_hw12
	[[ "$ans_hw12" =~ ^[Yy]$ ]] && heard_hw12=yes || heard_hw12=no
else
	echo "EBUSY/skipped — PipeWire holds pcm2p. Retry after: systemctl --user stop pipewire wireplumber" \
		| tee -a "${OUT}/speaker-test-hw12.log"
	heard_hw12=busy
fi

echo "--- ALSA direct: plughw:1,0 (rt721 SimpleJack) ---"
timeout 6 speaker-test -D plughw:1,0 -c 2 -r 48000 -t sine -f 440 -l 1 -s 1 \
	| tee "${OUT}/speaker-test-hw10.log" || true
read -r -p ">>> plughw:1,0 (rt721 jack path) — ¿OÍSTE? [y/N] " ans_hw10
[[ "$ans_hw10" =~ ^[Yy]$ ]] && heard_hw10=yes || heard_hw10=no

JACK_PLUGGED=unknown
if grep -q 'values=on' "${OUT}/jack-detect.txt" 2>/dev/null; then
	JACK_PLUGGED=yes
elif grep -q 'values=off' "${OUT}/jack-detect.txt" 2>/dev/null; then
	JACK_PLUGGED=no
fi

cat >"${OUT}/result.txt" <<EOF
time=$(date -Iseconds)
jack_plugged_detect=$JACK_PLUGGED
heard_speaker_pw=$heard_spk
heard_headphone_pw=$heard_hp
heard_smartamp_hw12=$heard_hw12
heard_rt721_hw10=$heard_hw10
EOF

echo
echo "=== Interpretation ==="
if [[ "$JACK_PLUGGED" == no ]]; then
	echo "INCONCLUSIVE: jack not detected — plug headphones and re-run E1"
elif [[ "$heard_hp" == yes && "$heard_spk" == no ]]; then
	echo "LOCALIZED: jack OK, speakers silent → TAS2783 SmartAmp path (post-fw_reinit)"
elif [[ "$heard_hw10" == yes && "$heard_hw12" == no ]]; then
	echo "LOCALIZED: rt721 OK, SmartAmp silent → TAS2783 analog/DSP"
elif [[ "$heard_hw12" == busy && "$heard_hp" == yes ]]; then
	echo "LIKELY TAS2783 — confirm: stop PW, test plughw:1,2"
elif [[ "$heard_hw10" == no && "$heard_spk" == no ]]; then
	echo "BROAD: both paths silent — shared upstream"
elif [[ "$heard_hw12" == yes || "$heard_spk" == yes ]]; then
	echo "SmartAmp path audible"
else
	echo "INCONCLUSIVE — review ${OUT}/result.txt"
fi
echo "output: $OUT"

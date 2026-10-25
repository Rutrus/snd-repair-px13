#!/usr/bin/env bash
# Collect a read-only evidence bundle for an incident postmortem.
# Usage:
#   collect-snapshot.sh [outdir] [since]
#   since: journalctl --since string, default "2 hours ago"
set -euo pipefail

TS=$(date +%Y%m%d-%H%M%S)
OUT=${1:-/tmp/snd-repair-postmortem-$TS}
SINCE=${2:-2 hours ago}
mkdir -p "$OUT"

# Desktop session (PipeWire) — best effort
if [[ -z "${XDG_RUNTIME_DIR:-}" ]] && [[ -d /run/user/"${SUDO_UID:-$UID}" ]]; then
	export XDG_RUNTIME_DIR=/run/user/"${SUDO_UID:-$UID}"
fi
if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]] && [[ -S "${XDG_RUNTIME_DIR:-}/bus" ]]; then
	export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
fi

REPO_ROOT=
# Prefer cwd if it looks like snd_repair
if [[ -x ./scripts/snd-repair ]]; then
	REPO_ROOT=$(pwd)
elif [[ -n "${BASH_SOURCE[0]:-}" ]]; then
	HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
	# …/incident-postmortem/scripts → repo root four levels up? skills live in .cursor/skills/
	CAND=$(cd "$HERE/../../../.." && pwd)
	[[ -x "$CAND/scripts/snd-repair" ]] && REPO_ROOT=$CAND
fi

{
	echo "collected_at=$(date -Iseconds)"
	echo "hostname=$(hostname 2>/dev/null || true)"
	echo "uname=$(uname -a)"
	echo "since=$SINCE"
	echo "xdg_runtime=${XDG_RUNTIME_DIR:-}"
	echo "repo_root=${REPO_ROOT:-}"
} >"$OUT/meta.txt"

grep . /sys/bus/soundwire/devices/sdw:*/status >"$OUT/sdw-status.txt" 2>/dev/null || \
	echo "no sdw sysfs" >"$OUT/sdw-status.txt"

if [[ -n "$REPO_ROOT" ]]; then
	(cd "$REPO_ROOT" && ./scripts/snd-repair status) >"$OUT/snd-repair-status.txt" 2>&1 || \
		echo "snd-repair status failed" >"$OUT/snd-repair-status.txt"
else
	echo "snd-repair not found" >"$OUT/snd-repair-status.txt"
fi

journalctl -k --since "$SINCE" --no-pager >"$OUT/journal-kernel-raw.txt" 2>/dev/null || true
grep -iE 'snd_repair|tas2783|rt721|soundwire|UNATTACH|fw download|-110|amd_sdw' \
	"$OUT/journal-kernel-raw.txt" >"$OUT/journal-kernel.txt" 2>/dev/null || \
	echo "(no marker lines)" >"$OUT/journal-kernel.txt"

dmesg -T 2>/dev/null | grep -iE 'snd_repair|tas2783|rt721|soundwire|UNATTACH|fw download|-110' \
	| tail -n 200 >"$OUT/dmesg-markers.txt" || echo "(dmesg unavailable)" >"$OUT/dmesg-markers.txt"

wpctl status >"$OUT/wpctl-status.txt" 2>&1 || echo "wpctl failed" >"$OUT/wpctl-status.txt"
pactl list cards >"$OUT/pactl-cards.txt" 2>&1 || true
pactl info >"$OUT/pactl-info.txt" 2>&1 || true
pactl list short sinks >"$OUT/pactl-sinks.txt" 2>&1 || true
pactl list short sources >"$OUT/pactl-sources.txt" 2>&1 || true
{
	echo "=== pactl defaults ==="
	pactl info 2>/dev/null | grep -E 'Destino|Fuente|Default' || true
} >"$OUT/pactl-defaults.txt"

DN="${XDG_STATE_HOME:-$HOME/.local/state}/wireplumber/default-nodes"
if [[ -f "$DN" ]]; then
	cp -a "$DN" "$OUT/default-nodes.txt"
else
	echo "(missing $DN)" >"$OUT/default-nodes.txt"
fi

{
	amixer -c 1 controls 2>/dev/null | grep -iE 'jack|headphone|headset|spk' || true
	echo "---"
	amixer -c 1 contents 2>/dev/null | grep -A2 -iE 'Jack|Headphone Switch|Headset Mic' || true
} >"$OUT/amixer-jack.txt"

{
	for s in /proc/asound/card*/pcm*/sub*/status; do
		[[ -f "$s" ]] || continue
		echo "==== $s ===="
		cat "$s"
		echo
	done
} >"$OUT/pcm-status.txt" 2>/dev/null || true

# Compact index for the agent
{
	echo "# Postmortem snapshot index"
	echo "outdir=$OUT"
	echo
	echo "## SDW"
	cat "$OUT/sdw-status.txt"
	echo
	echo "## Defaults"
	cat "$OUT/pactl-defaults.txt"
	echo
	echo "## Markers (tail)"
	tail -n 40 "$OUT/journal-kernel.txt"
} >"$OUT/SUMMARY.txt"

echo "$OUT"
ls -la "$OUT"

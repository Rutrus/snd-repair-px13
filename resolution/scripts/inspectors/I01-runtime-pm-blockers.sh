#!/usr/bin/env bash
# I01 — Runtime PM blockers (Snapshot inspector). Who prevents runtime_suspend?
# Usage: sudo ./I01-runtime-pm-blockers.sh
# Safe: no sysfs writes, no suspend, no recovery.
set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${_SCRIPT_DIR}/../recovery/_lib.sh"

PCI="${PX13_PCI_DEV:-0000:c4:00.5}"
SYSFS="/sys/bus/pci/devices/${PCI}/power"
TS="$(date -Iseconds)"

section() { echo ""; echo "=== $* ==="; }

show_if_readable() {
	local path="$1" label="${2:-$1}"
	if [[ -r "$path" ]]; then
		printf '  %-28s %s\n' "$label:" "$(cat "$path")"
	else
		printf '  %-28s (not readable)\n' "$label:"
	fi
}

echo "=== I01 RUNTIME PM BLOCKERS ==="
echo "Time:     ${TS}"
echo "PCI:      ${PCI}"
echo "Question: Who prevents runtime_suspend?"
section "PCI runtime PM (${SYSFS})"
[[ -d "$SYSFS" ]] || { echo "  power/ missing" >&2; exit 1; }
show_if_readable "${SYSFS}/runtime_status"
show_if_readable "${SYSFS}/runtime_enabled"
show_if_readable "${SYSFS}/control"
for f in runtime_usage runtime_active_time runtime_suspended_time runtime_auto autosuspend_delay_ms; do
	show_if_readable "${SYSFS}/${f}" "$f"
done

section "ALSA cards"
if [[ -r /proc/asound/cards ]]; then
	cat /proc/asound/cards | sed 's/^/  /'
else
	echo "  (unavailable)"
fi
echo "  plughw playback: $(witness_playback_alsa && echo OK || echo FAIL)"

section "/dev/snd holders (fuser)"
if command -v fuser >/dev/null 2>&1; then
	fuser -v /dev/snd/* 2>&1 | sed 's/^/  /' || echo "  (none)"
else
	echo "  fuser not installed"
fi

section "/dev/snd open files (lsof)"
if command -v lsof >/dev/null 2>&1; then
	lsof /dev/snd/* 2>/dev/null | sed 's/^/  /' || echo "  (none)"
else
	echo "  lsof not installed"
fi

section "PipeWire/Pulse sinks (logged-in user)"
echo "  userspace_sink_state: $(userspace_sink_state)"
echo "  default_dummy: $(userspace_default_sink_is_dummy && echo yes || echo no)"

section "Kernel — recent PM on this PCI (last 3 min)"
journalctl -k -b 0 --no-pager --since "3 min ago" 2>/dev/null \
	| grep -E "${PCI}|snd_pci_ps|runtime PM|pm_runtime" | tail -20 | sed 's/^/  /' || echo "  (no lines)"

section "Verdict hint"
rs="$(cat "${SYSFS}/runtime_status" 2>/dev/null || echo ?)"
ru="$(cat "${SYSFS}/runtime_usage" 2>/dev/null || echo ?)"
wp_pcm=""
if command -v fuser >/dev/null 2>&1; then
	wp_pcm="$(fuser /dev/snd/pcm* 2>/dev/null | tr -s ' ' || true)"
fi
if [[ "$rs" == "active" && "${ru:-?}" == "0" ]]; then
	echo "  runtime_usage=0 + status=active → NOT a PCI refcnt block"
	echo "  driver stays active internally OR autosuspend path never fires post-S2"
elif [[ "$rs" == "active" && "${ru:-0}" != "0" && "$ru" != "?" ]]; then
	echo "  runtime_usage=${ru} — kernel reports active references"
fi
[[ -n "$wp_pcm" ]] && echo "  PCM open (fuser):${wp_pcm} — may block ALSA; PCI usage may still be 0"
echo "==============================="
echo "Log → resolution/TRACKER.md (I01 section)"

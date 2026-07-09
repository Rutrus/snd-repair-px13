#!/usr/bin/env bash
# Read-only probe: tracefs / dynamic_debug for SoundWire resume tracing.
# Run before planning kernel instrumentation. Some checks need root.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${REPO}/validation/phase6-trace-probe.txt"
KERNEL="$(uname -r)"

{
	echo "# Phase 6 trace probe $(date -Is) kernel=${KERNEL}"
	echo ""

	echo "## tracefs mount"
	mount | grep -E 'tracefs|debugfs' || true
	echo ""

	echo "## soundwire trace events"
	for base in /sys/kernel/tracing/events/soundwire \
		/sys/kernel/debug/tracing/events/soundwire; do
		echo "### ${base}"
		if [[ -d "$base" ]]; then
			ls "$base" 2>/dev/null | head -30 || echo "(empty or permission denied)"
		else
			echo "(missing)"
		fi
		echo ""
	done

	echo "## ASoC trace events (sample)"
	ls /sys/kernel/tracing/events/asoc/ 2>/dev/null | head -15 || true
	echo ""

	echo "## PM-related trace categories"
	ls /sys/kernel/tracing/events/ 2>/dev/null | grep -iE 'pm|power|runtime|bus' | head -20 || true
	echo ""

	echo "## dynamic_debug (soundwire)"
	if [[ -r /sys/kernel/debug/dynamic_debug/control ]]; then
		grep -c soundwire /sys/kernel/debug/dynamic_debug/control 2>/dev/null \
			|| echo "0 soundwire lines (or unreadable)"
		grep -m5 soundwire /sys/kernel/debug/dynamic_debug/control 2>/dev/null || true
	else
		echo "Need root to read /sys/kernel/debug/dynamic_debug/control"
	fi
	echo ""

	echo "## Loaded SDW modules"
	lsmod | grep -iE 'soundwire|snd_soc|snd_pci_ps|rt721|tas2783' || true
	echo ""

	echo "## Recommendation (kernel ${KERNEL})"
	if [[ ! -d /sys/kernel/tracing/events/soundwire ]] \
		|| [[ -z "$(ls -A /sys/kernel/tracing/events/soundwire 2>/dev/null)" ]]; then
		echo "- No in-tree soundwire trace events → use kmsg chronology (phase6-kmsg-parse.sh)"
		echo "- Optional: dynamic_debug +file soundwire/*.c (root)"
		echo "- Optional: minimal RT721 resume trace patch ONLY after chronology diff pins rt721 window"
	fi
} | tee "$OUT"

echo "Wrote ${OUT}"

#!/usr/bin/env bash
# W8 context sweep — priority order after W5 repro + W6@3000 PASS.
#
#   1. timer 1500 ms  (close scenario A)
#   2. hw-params      (context vs time)
#   3. port-prep
#   4. dapm-pmu
#
# Usage: sudo ./scripts/w8-context-sweep.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

run_one() {
	echo
	echo "########################################"
	"$SCRIPT_DIR/w8-context-reinit-test.sh" "$@"
	if [[ -t 0 ]]; then
		read -r -p "Audio PASS for $*? [y/N] " ans || ans=n
		latest="$(ls -td "${SCRIPT_DIR}/../validation/w8-"* 2>/dev/null | head -1 || true)"
		[[ -n "$latest" ]] && echo "audio=${ans,,}" >>"${latest}/meta.txt"
	fi
}

echo "W8 context sweep — 4 S2 cycles (confirm each by ear)"
run_one --mode timer --delay 1500
run_one --mode hw-params
run_one --mode port-prep
run_one --mode dapm-pmu

echo
echo "Done. Summarize in research/experiments/w8-context-results.md"

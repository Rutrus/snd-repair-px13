#!/usr/bin/env bash
# Evaluate C02 kill_closure four gates from environment (post R07).
# Usage: source after run-recovery or export RESOLUTION_R07_* and call.
set -euo pipefail

g1="${C02_G1:-?}"
g2="${C02_G2:-?}"
g3="${C02_G3:-?}"
g4="${C02_G4:-?}"

if [[ -n "${RESOLUTION_R07_PCI:-}" ]]; then
	g2=fail
	[[ "${RESOLUTION_R07_PCI}" == "ok" ]] && g2=pass
	g3=fail
	[[ "${RESOLUTION_R07_DIFF_CAPTURED:-0}" == "1" ]] && g3=pass
	g4=fail
	[[ "${RESOLUTION_R07_DIFF_RELEVANT_UNCHANGED:-0}" == "1" ]] && g4=pass
fi

echo "=== C02 kill closure (4 gates) ==="
echo "G1 S2 certified (W2+):     ${g1}"
echo "G2 R07 complete:            ${g2}"
echo "G3 snapshot valid:          ${g3}"
echo "G4 relevant diff unchanged: ${g4}"
echo ""

if [[ "$g1" == pass && "$g2" == pass && "$g3" == pass && "$g4" == pass ]]; then
	echo "VERDICT: C02 KILLED — all gates pass"
	echo "PCI unbind/bind does not modify relevant failure state."
	exit 0
fi

echo "VERDICT: C02 not closable yet"
[[ "$g3" != pass ]] && echo "  → fix snapshot capture (G3)"
[[ "$g4" != pass && "$g3" == pass ]] && echo "  → relevant field changed: record F014+ before kill"
exit 1

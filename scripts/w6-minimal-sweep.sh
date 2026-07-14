#!/usr/bin/env bash
# W6 minimal sweep — 0 ms (control), 1500 ms, 3000 ms only.
#
# Run AFTER W5 reproducibility is confirmed (see w5-reproducibility-test.sh).
#
# Usage:
#   sudo ./scripts/w6-minimal-sweep.sh
#   sudo ./scripts/w6-minimal-sweep.sh --skip-0   # if delay=0 already recorded
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKIP0=0

while [[ $# -gt 0 ]]; do
	case "$1" in
	--skip-0) SKIP0=1; shift ;;
	-h|--help)
		sed -n '3,12p' "$0"
		exit 0
		;;
	*) echo "Unknown: $1" >&2; exit 1 ;;
	esac
done

DELAYS=()
[[ "$SKIP0" -eq 0 ]] && DELAYS+=(0)
DELAYS+=(1500 3000)

echo "=== W6 minimal sweep: ${DELAYS[*]} ms ==="
echo "One S2 cycle per delay. Confirm audio by ear after each run."
echo

for ms in "${DELAYS[@]}"; do
	echo "--- delay=${ms}ms ---"
	if [[ "$ms" -eq 0 ]]; then
		echo "(control: W2 only, no 2nd reinit — expect FAIL/silence)"
	fi
	"$SCRIPT_DIR/w6-deferred-reinit-sweep.sh" --delay "$ms"
	if [[ -t 0 ]]; then
		read -r -p "delay=${ms}ms audio PASS? [y/N] " ans || ans=n
		latest="$(ls -td "${SCRIPT_DIR}/../validation/w6-delay-${ms}ms-"* 2>/dev/null | head -1 || true)"
		if [[ -n "$latest" && -f "${latest}/meta.txt" ]]; then
			case "${ans,,}" in
			y|yes) echo "audio=PASS" >>"${latest}/meta.txt" ;;
			*) echo "audio=FAIL" >>"${latest}/meta.txt" ;;
			esac
		fi
	fi
	echo
done

cat <<'EOF'
Interpretation:
  0 FAIL, 1500+ PASS  → timing hypothesis (scenario A)
  all FAIL            → W6 context differs from W5 manual (scenario B) — use W7 timeline

See: research/experiments/w6-deferred-reinit-protocol.md
EOF

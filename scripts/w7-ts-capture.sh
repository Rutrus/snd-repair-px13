#!/usr/bin/env bash
# Extract W7 timeline for the most recent S2 resume only.
set -euo pipefail
export LC_ALL=C

BOOT=0
while [[ $# -gt 0 ]]; do
	case "$1" in
	--boot) BOOT="${2:-0}"; shift 2 ;;
	-h|--help) sed -n '3,8p' "$0"; exit 0 ;;
	*) echo "Unknown: $1" >&2; exit 1 ;;
	esac
done

raw="$(journalctl -k -b "$BOOT" --no-pager | grep 'W7 ctx=ts' || true)"
[[ -n "$raw" ]] || { echo "No W7 ctx=ts in boot $BOOT"; exit 1; }

last_anchor="$(grep 'event=s2_resume_anchor' <<<"$raw" | tail -1 || true)"
[[ -n "$last_anchor" ]] || { echo "$raw"; exit 0; }

anchor_ts="${last_anchor%% *} ${last_anchor#* }"
anchor_ts="${anchor_ts%% Colosal*}"

echo "# W7 timeline — last S2 only (boot $BOOT)"
echo "# anchor: $last_anchor"
echo

# Print from last anchor line to EOF in full journal order
journalctl -k -b "$BOOT" --no-pager | awk '
	/W7 ctx=ts.*event=s2_resume_anchor/ { buf=""; collecting=0 }
	/W7 ctx=ts/ {
		if (/event=s2_resume_anchor/) collecting=1
		if (collecting) print
	}
' | tail -30

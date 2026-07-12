#!/usr/bin/env bash
# Compare SoundWire codec PM/stream callbacks — tas2783 vs rt721 (read-only).
#
# Usage:
#   ./scripts/compare-codec-pm-ops.sh
#   KDIR=/usr/src/linux-source-7.0.0 ./scripts/compare-codec-pm-ops.sh
set -euo pipefail

K="${KDIR:-/usr/src/linux-source-7.0.0}"
TAS="$K/sound/soc/codecs/tas2783-sdw.c"
RT721="$K/sound/soc/codecs/rt721-sdca.c"
SDW="$K/drivers/soundwire/stream.c"
UTIL="$K/sound/soc/sdw_utils/soc_sdw_utils.c"

for f in "$TAS" "$RT721" "$SDW"; do
	[[ -f "$f" ]] || { echo "Missing $f — set KDIR" >&2; exit 1; }
done

echo "=== SDW stream states (sdw.h) ==="
rg -A 8 'enum sdw_stream_state' "$K/include/linux/soundwire/sdw.h" 2>/dev/null || true
echo

show() {
	local label="$1" file="$2"
	echo "=== $label ($file) ==="
	rg -n 'sdw_slave_driver|\.set_stream|\.port_prep|\.update_status|SYSTEM_SLEEP|RUNTIME_PM|dev_pm_ops|\.prepare|\.hw_params|\.trigger' "$file" 2>/dev/null || true
	echo
}

show "tas2783-sdw" "$TAS"
show "rt721-sdca" "$RT721"

echo "=== sdw_prepare_stream allowed states ==="
sed -n '1545,1557p' "$SDW"
echo

echo "=== asoc_sdw_prepare → sdw_prepare_stream ==="
sed -n '1105,1125p' "$UTIL"
echo

echo "=== sdw_prepare_stream inconsistent state sites ==="
rg -n 'inconsistent state' "$SDW"

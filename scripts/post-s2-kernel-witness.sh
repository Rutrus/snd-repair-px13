#!/usr/bin/env bash
# KPI-K — post-S2 kernel / direct-ALSA witness (upstream contract).
#
# Stops PipeWire for exclusive hw: access. Not a user-facing PASS/FAIL for the laptop.
#
# Usage:
#   ./scripts/post-s2-kernel-witness.sh
#   ./scripts/post-s2-kernel-witness.sh --keep-pipewire   # expect EBUSY on busy PCMs
#
# Env:
#   KPI_K_RECORD_SEC=3
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${SND_REPAIR_REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"
OUT_DIR=""
KEEP_PW=0
RECORD_SEC="${KPI_K_RECORD_SEC:-3}"
UID_SELF="$(id -u)"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID_SELF}"

while [[ $# -gt 0 ]]; do
	case "$1" in
	--out-dir) OUT_DIR="$2"; shift 2 ;;
	--keep-pipewire) KEEP_PW=1; shift ;;
	-h|--help)
		sed -n '3,14p' "$0"
		exit 0
		;;
	*) echo "Unknown: $1" >&2; exit 1 ;;
	esac
done

TS="$(date -Iseconds)"
TS_FILE="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="${OUT_DIR:-${REPO}/validation/post-s2-kernel-witness/${TS_FILE}}"
mkdir -p "$OUT_DIR"

exec > >(tee "${OUT_DIR}/witness.log") 2>&1

echo "=== KPI-K POST-S2 KERNEL WITNESS ==="
echo "time=$TS"
echo "output_dir=$OUT_DIR"
echo "NOTE: KPI-K FAIL does not mean KPI-U FAIL. See research/experiments/kpi-u-vs-kpi-k-20260712.md"
echo

if [[ "$KEEP_PW" -eq 0 ]]; then
	echo "--- stopping PipeWire (exclusive ALSA) ---"
	systemctl --user stop wireplumber pipewire pipewire-pulse 2>/dev/null || true
	sleep 2
else
	echo "--- keeping PipeWire (--keep-pipewire) ---"
fi

echo "--- /proc/asound/pcm ---"
cp -f /proc/asound/pcm "${OUT_DIR}/proc-asound-pcm.txt" 2>/dev/null || true
cat /proc/asound/pcm 2>/dev/null || true
echo

probe_playback() {
	local rc=0
	echo "--- speaker-test hw:1,2 ---"
	if speaker-test -D hw:1,2 -c 2 -r 48000 -t sine -l 1 \
		>"${OUT_DIR}/speaker-test-hw12.log" 2>&1; then
		echo "RESULT playback_hw12=PASS"
	else
		rc=1
		echo "RESULT playback_hw12=FAIL"
		tail -5 "${OUT_DIR}/speaker-test-hw12.log" || true
	fi
	return "$rc"
}

probe_capture() {
	local dev="$1" fmt="$2" label="$3" pcm_proc="$4"
	shift 4
	local wav="${OUT_DIR}/${label}.wav"
	local log="${OUT_DIR}/arecord-${label}.log"
	local rc=0 extra=("$@")
	echo "--- arecord $dev ($label) ${extra[*]:-} ---"
	if arecord -D "$dev" -f "$fmt" -r 48000 -c 2 -d "$RECORD_SEC" \
		"${extra[@]}" "$wav" >"$log" 2>&1; then
		echo "RESULT ${label}=PASS size=$(stat -c%s "$wav" 2>/dev/null || echo 0)"
	else
		rc=1
		echo "RESULT ${label}=FAIL"
		tail -5 "$log" || true
	fi
	if [[ -r "$pcm_proc" ]]; then
		echo "--- $pcm_proc ---"
		cat "$pcm_proc" 2>/dev/null || true
	fi
	echo
	return "$rc"
}

pb_rc=0
probe_playback || pb_rc=$?

rt721_rc=0
probe_capture hw:1,1 S16_LE rt721-hw11 /proc/asound/card1/pcm1c/sub0/status || rt721_rc=$?

rt721_mmap_rc=0
probe_capture hw:1,1 S16_LE rt721-hw11-mmap /proc/asound/card1/pcm1c/sub0/status \
	-M --period-size=1024 --buffer-size=4096 || rt721_mmap_rc=$?

dmic_rc=0
probe_capture hw:1,4 S32_LE dmic-hw14 /proc/asound/card1/pcm4c/sub0/status || dmic_rc=$?

dmic_mmap_rc=0
probe_capture hw:1,4 S32_LE dmic-hw14-mmap /proc/asound/card1/pcm4c/sub0/status \
	-M --period-size=1024 --buffer-size=4096 || dmic_mmap_rc=$?

echo "--- SDWCAP (boot, tail) ---"
journalctl -k -b 0 --no-pager 2>/dev/null \
	| grep SDWCAP | grep -E 'dir=capture|dir=playback' | tail -30 \
	| tee "${OUT_DIR}/sdwcap-tail.log" || true
echo

echo "--- kernel errors (last 2 min) ---"
journalctl -k --since "2 minutes ago" --no-pager 2>/dev/null \
	| grep -iE 'ASoC error|inconsistent state|sdw_prepare|EIO|capture' \
	| tee "${OUT_DIR}/kernel-errors.log" | tail -25 || true
echo

# Legacy KPI-K (all RW) — expected FAIL post-S2; see capture-access-matrix doc.
kpi_k_rw=FAIL
[[ "$pb_rc" -eq 0 && "$rt721_rc" -eq 0 && "$dmic_rc" -eq 0 ]] && kpi_k_rw=PASS

kpi_k_mmap=FAIL
[[ "$pb_rc" -eq 0 && "$rt721_mmap_rc" -eq 0 && "$dmic_mmap_rc" -eq 0 ]] && kpi_k_mmap=PASS

cat > "${OUT_DIR}/kpi-k.txt" <<EOF
kpi_k_rw=$kpi_k_rw
kpi_k_mmap=$kpi_k_mmap
time=$TS
pipewire_stopped=$([[ "$KEEP_PW" -eq 0 ]] && echo 1 || echo 0)
playback_hw12=$([[ "$pb_rc" -eq 0 ]] && echo 1 || echo 0)
capture_rt721_hw11_rw=$([[ "$rt721_rc" -eq 0 ]] && echo 1 || echo 0)
capture_rt721_hw11_mmap=$([[ "$rt721_mmap_rc" -eq 0 ]] && echo 1 || echo 0)
capture_dmic_hw14_rw=$([[ "$dmic_rc" -eq 0 ]] && echo 1 || echo 0)
capture_dmic_hw14_mmap=$([[ "$dmic_mmap_rc" -eq 0 ]] && echo 1 || echo 0)
note=RW_vs_MMAP see research/experiments/capture-access-matrix-20260712.md
EOF
cat "${OUT_DIR}/kpi-k.txt"
echo
echo "=> KPI-K RW:   $kpi_k_rw (upstream anomaly — RW capture post-S2)"
echo "=> KPI-K MMAP: $kpi_k_mmap"
echo "witness complete: $OUT_DIR"

if [[ "$KEEP_PW" -eq 0 ]]; then
	systemctl --user start pipewire pipewire-pulse wireplumber 2>/dev/null || true
fi

exit 0

#!/usr/bin/env bash
# Phase 7 sweep — AFTER reboot/login (one suspend per boot).
#
# Usage:
#   ./scripts/phase7-sweep-post.sh --verify-only   # check param only
#   ./scripts/phase7-sweep-post.sh                 # arm + instructions
#   ./scripts/phase7-sweep-post.sh --after-suspend # post-suspend capture
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_DIR="${REPO}/validation/.state"
STATE_MS="${STATE_DIR}/phase7-sweep-ms"
STATE_SV="${STATE_DIR}/phase7-installed-srcversion"
KVER="$(uname -r)"
INSTALLED_KO="/lib/modules/${KVER}/kernel/drivers/soundwire/soundwire-amd.ko.zst"
PARAM="/sys/module/soundwire_amd/parameters/phase7_delay_ms"
MODPROBE_D="/etc/modprobe.d/snd-repair-phase7.conf"

read_expected_ms() {
	if [[ ! -f "$STATE_MS" ]]; then
		echo "ERROR: missing ${STATE_MS} — run phase7-sweep-pre.sh MS first" >&2
		exit 1
	fi
	cat "$STATE_MS"
}

read_actual_ms() {
	if [[ -f "$PARAM" ]]; then
		cat "$PARAM"
		return
	fi
	echo "MISSING"
}

installed_srcversion() {
	if [[ -f "$STATE_SV" ]]; then
		cat "$STATE_SV"
		return
	fi
	if [[ -f "$INSTALLED_KO" ]]; then
		modinfo -F srcversion "$INSTALLED_KO"
		return
	fi
	echo "MISSING"
}

loaded_srcversion() {
	if [[ -r /sys/module/soundwire_amd/srcversion ]]; then
		cat /sys/module/soundwire_amd/srcversion
		return
	fi
	echo "MISSING"
}

phase7_installed_on_disk() {
	[[ -f "$INSTALLED_KO" ]] || return 1
	modinfo -F parm "$INSTALLED_KO" 2>/dev/null | grep -q 'phase7_delay_ms'
}

modprobe_ms() {
	if [[ ! -f "$MODPROBE_D" ]]; then
		echo "MISSING"
		return
	fi
	local line
	line="$(grep -E '^[[:space:]]*options[[:space:]]+soundwire_amd[[:space:]]+phase7_delay_ms=' "$MODPROBE_D" | tail -1 || true)"
	if [[ -z "$line" ]]; then
		echo "MISSING"
		return
	fi
	echo "${line##*=}" | tr -d '[:space:]'
}

verify_param() {
	local expected actual modprobe expected_sv loaded_sv
	expected="$(read_expected_ms)"
	actual="$(read_actual_ms)"
	modprobe="$(modprobe_ms)"
	expected_sv="$(installed_srcversion)"
	loaded_sv="$(loaded_srcversion)"

	echo "=== Phase 7 param check ==="
	echo "  expected (state):     ${expected}"
	echo "  modprobe.d:           ${modprobe}"
	echo "  actual (sysfs):       ${actual}"
	echo "  installed srcversion: ${expected_sv}"
	echo "  running srcversion:   ${loaded_sv}"

	if ! phase7_installed_on_disk; then
		echo ""
		echo "ERROR: Phase 7 module not installed on disk (no phase7_delay_ms in ${INSTALLED_KO})." >&2
		echo "  Run: ./scripts/build-phase7.sh --experiment delay-after-d0 && sudo reboot" >&2
		exit 1
	fi

	if [[ "$expected_sv" == "MISSING" ]]; then
		echo ""
		echo "ERROR: missing ${STATE_SV} — rebuild Phase 7 to record srcversion." >&2
		exit 1
	fi

	if [[ "$loaded_sv" == "MISSING" ]]; then
		echo ""
		echo "ERROR: soundwire_amd is not loaded." >&2
		exit 1
	fi

	if [[ "$loaded_sv" != "$expected_sv" ]]; then
		echo ""
		echo "ERROR: running soundwire_amd (${loaded_sv}) != installed Phase 7 (${expected_sv})." >&2
		echo "  The .ko on disk has phase7_delay_ms but the old module is still in memory." >&2
		echo "  Run: sudo reboot   (after build-phase7.sh, before phase7-sweep-pre.sh)" >&2
		exit 1
	fi

	if [[ "$modprobe" == "MISSING" ]]; then
		echo ""
		echo "ERROR: ${MODPROBE_D} missing phase7_delay_ms option." >&2
		echo "  Run: ./scripts/phase7-sweep-pre.sh ${expected}" >&2
		exit 1
	fi

	if [[ "$modprobe" != "$expected" ]]; then
		echo ""
		echo "ERROR: modprobe.d has phase7_delay_ms=${modprobe}, expected ${expected}." >&2
		echo "  Re-run: ./scripts/phase7-sweep-pre.sh ${expected}" >&2
		exit 1
	fi

	if [[ "$actual" != "MISSING" && "$actual" != "$expected" ]]; then
		echo ""
		echo "ERROR: sysfs phase7_delay_ms=${actual}, expected ${expected}." >&2
		echo "  modprobe.d looks correct — check ${MODPROBE_D} and reboot again." >&2
		exit 1
	fi

	if [[ "$actual" == "MISSING" ]]; then
		echo "  note: sysfs param absent (ok if srcversion matches — value set at module load via modprobe.d)"
	fi

	echo "  OK: Phase 7 module loaded; modprobe.d matches — safe to run experiment"
}

cmd="${1:-}"

case "$cmd" in
--verify-only)
	verify_param
	;;
--after-suspend)
	verify_param
	MS="$(read_expected_ms)"
	echo "p7-0005-d${MS}" >"${STATE_DIR}/phase6-hunt-notes"
	echo ""
	"${SCRIPT_DIR}/phase6-hunt.sh" post-suspend --save-window
	echo ""
	echo "Recorded p7-0005-d${MS} — next delay: ${SCRIPT_DIR}/phase7-sweep-pre.sh <MS>"
	;;
""|-h|--help)
	verify_param
	MS="$(read_expected_ms)"
	echo ""
	"${SCRIPT_DIR}/phase6-hunt.sh" post-reboot --notes "p7-0005-d${MS}"
	echo ""
	echo "=== Next (manual) ==="
	echo "  systemctl suspend"
	echo "  # after wake:"
	echo "  ${SCRIPT_DIR}/phase7-sweep-post.sh --after-suspend"
	;;
*)
	echo "Usage: $0 [--verify-only|--after-suspend]" >&2
	exit 1
	;;
esac

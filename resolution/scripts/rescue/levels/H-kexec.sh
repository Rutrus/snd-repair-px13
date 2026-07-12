#!/usr/bin/env bash
# H — kexec warm boot (last resort before full reboot). Requires kexec-tools.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"
LID="H"
rescue_log "level ${LID}: kexec (requires RESCUE_ALLOW_KEXEC=1)"

if [[ "${RESCUE_ALLOW_KEXEC:-0}" != "1" ]]; then
	rescue_log "SKIP: set RESCUE_ALLOW_KEXEC=1 to enable"
	echo "RESULT=SKIP LEVEL=${LID} REASON=kexec_not_enabled"
	exit 0
fi

if ! command -v kexec >/dev/null 2>&1; then
	rescue_log "kexec not installed"
	bf_report_fail "$LID"
	exit 1
fi

kernel="$(readlink -f /boot/vmlinuz-$(uname -r) 2>/dev/null || true)"
[[ -n "$kernel" ]] || kernel="/boot/vmlinuz-$(uname -r)"
rescue_log "kexec -l ${kernel}"
kexec -l "$kernel" --reuse-cmdline
rescue_log "kexec -e in 3s..."
sleep 3
kexec -e

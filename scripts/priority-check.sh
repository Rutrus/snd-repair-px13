#!/usr/bin/env bash
# Priority error report — PX13 (no root required for most checks).
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
RED=$'\033[31m'
GRN=$'\033[32m'
YLW=$'\033[33m'
RST=$'\033[0m'

ok()   { printf '%s[OK]%s %s\n' "$GRN" "$RST" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "$YLW" "$RST" "$*"; }
fail() { printf '%s[FAIL]%s %s\n' "$RED" "$RST" "$*"; }

section() { echo; echo "=== $* ==="; }

section "P0 Track A — FW :8 / Speaker"
if wpctl status 2>/dev/null | grep -q 'Audio Coprocessor Speaker'; then
	ok "PipeWire Speaker sink present"
elif wpctl status 2>/dev/null | grep -q 'Dummy Output'; then
	fail "Dummy Output only — reboot or px13-audio-fix (may need reboot)"
else
	warn "PipeWire not reachable"
fi

fw_err="$(journalctl -k -b --no-pager 2>/dev/null | grep -c 'playback without fw.*uid=0x8' || true)"
pm110="$(journalctl -k -b --no-pager 2>/dev/null | grep -c 'failed to resume: error -110' || true)"
[[ "$fw_err" -eq 0 ]] && ok "No :8 playback-without-fw this boot" || fail ":8 FW warnings this boot: $fw_err"
[[ "$pm110" -eq 0 ]] && ok "No PM resume -110 this boot" || warn "PM resume -110 count: $pm110"

section "P1 Track D — px13 / validation"
if [[ -x /usr/local/sbin/px13-audio-fix.sh ]] \
	&& grep -q 'snd_repair hardened fork' /usr/local/sbin/px13-audio-fix.sh 2>/dev/null; then
	ok "Hardened px13-audio-fix installed"
else
	warn "Brainchillz or missing px13-audio-fix — run: sudo ${REPO}/scripts/install-px13-audio-fix.sh"
fi

if [[ -f /etc/systemd/system/px13-audio-resume.service.d/snd-repair-fw-validation.conf ]]; then
	if grep -q 'PX13_AFTER_SUSPEND=1' /etc/systemd/system/px13-audio-resume.service.d/snd-repair-fw-validation.conf 2>/dev/null; then
		ok "Resume drop-in has PX13_AFTER_SUSPEND"
	else
		warn "Stale drop-in — reinstall: sudo ${REPO}/scripts/install-fw-validation-service.sh --suspend-only"
	fi
else
	warn "Missing suspend drop-in"
fi

if journalctl -b --no-pager 2>/dev/null | grep -q 'ordering cycle.*snd-repair-fw-validation'; then
	warn "systemd ordering cycle for boot validation (fixed in repo unit — reinstall user unit)"
else
	ok "No ordering cycle logged this boot"
fi

section "P2 Track B — SDW1-PIN4 capture -22"
pin4="$(journalctl -k -b --no-pager 2>/dev/null | grep -c 'SDW1-PIN4-CAPTURE.*prepare ret=-22' || true)"
[[ "$pin4" -eq 0 ]] && ok "No PIN4 prepare -22" || warn "PIN4 prepare -22 count: $pin4 (known, non-blocking)"

section "P3 Track C — webcam media0"
if groups | grep -q '\bvideo\b'; then
	ok "User in group video"
else
	warn "User NOT in group video — sudo usermod -aG video,render \$USER"
fi
if groups | grep -q '\brender\b'; then
	ok "User in group render"
else
	warn "User NOT in group render"
fi
if journalctl -b --no-pager 2>/dev/null | grep -q 'media0.*Permiso denegado\|media0.*Permission denied'; then
	warn "media0 permission error this boot"
else
	ok "No media0 permission error in journal"
fi

section "Validation matrix (last 3 rows)"
tail -3 "${REPO}/validation/fw-matrix.csv" 2>/dev/null || warn "No fw-matrix.csv"

section "Next manual test (after sudo reinstall)"
cat <<EOF
  1. systemctl suspend   # lid close or manual
  2. Wait ~90s after wake
  3. wpctl status | grep Speaker
  4. ${REPO}/scripts/fw-validation-run.sh suspend --notes "priority-check"
  5. ${REPO}/scripts/priority-check.sh
EOF

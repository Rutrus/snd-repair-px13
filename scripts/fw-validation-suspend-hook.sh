#!/usr/bin/env bash
# Programa validación FW tras resume sin morir con el cgroup de px13-audio-resume.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${SND_REPAIR_REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"
COLLECT="${REPO}/scripts/fw-validation-collect.sh"
STATE_DIR="${REPO}/validation/.state"
LOG="${STATE_DIR}/suspend-hook.log"
DELAY="${SND_REPAIR_SUSPEND_DELAY:-60}"
_repo_owner="$(stat -c '%U' "$REPO" 2>/dev/null || true)"
RUN_USER="${SUDO_USER:-${PX13_RUN_USER:-${_repo_owner:-${USER}}}}"
RUN_UID="$(id -u "$RUN_USER" 2>/dev/null || echo 1000)"

mkdir -p "$STATE_DIR"
echo "=== $(date -Is) schedule suspend collect delay=${DELAY}s ===" >>"$LOG"

if [[ ! -x "$COLLECT" ]]; then
	echo "collect missing: $COLLECT" >>"$LOG"
	exit 0
fi

# Transient unit: sobrevive al fin de px13-audio-resume.service
systemd-run \
	--uid="$RUN_UID" \
	--gid="$RUN_UID" \
	--working-directory="$REPO" \
	--property=Nice=19 \
	--property=IOSchedulingClass=idle \
	--unit="snd-repair-fw-collect-suspend-$(date +%s)" \
	--description="snd_repair FW validation after suspend" \
	/bin/bash -c "sleep ${DELAY}; exec '${COLLECT}' --suspend --notes 'auto@suspend'" \
	>>"$LOG" 2>&1 || {
	echo "systemd-run failed, fallback nohup" >>"$LOG"
	nohup nice -n 19 bash -c "sleep ${DELAY}; '${COLLECT}' --suspend --notes 'auto@suspend'" >>"$LOG" 2>&1 &
}

exit 0

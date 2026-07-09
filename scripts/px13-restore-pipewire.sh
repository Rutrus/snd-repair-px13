#!/usr/bin/env bash
# Restaura PipeWire/WirePlumber tras px13-audio-fix fallido (FW roto, sesión sin audio).
set -euo pipefail

for uid in $(loginctl list-users --no-legend 2>/dev/null | awk '{print $1}'); do
	user_name="$(id -nu "$uid" 2>/dev/null)" || continue
	runtime_dir="/run/user/$uid"
	[[ -d "$runtime_dir" ]] || continue
	echo "px13-restore-pipewire: uid $uid ($user_name)"
	sudo -u "$user_name" XDG_RUNTIME_DIR="$runtime_dir" \
		systemctl --user unmask --runtime pipewire.socket pipewire-pulse.socket 2>/dev/null || true
	sudo -u "$user_name" XDG_RUNTIME_DIR="$runtime_dir" \
		systemctl --user daemon-reload 2>/dev/null || true
	sudo -u "$user_name" XDG_RUNTIME_DIR="$runtime_dir" \
		systemctl --user reset-failed pipewire wireplumber pipewire-pulse 2>/dev/null || true
	sudo -u "$user_name" XDG_RUNTIME_DIR="$runtime_dir" \
		systemctl --user start pipewire.socket pipewire-pulse.socket 2>/dev/null || true
	sudo -u "$user_name" XDG_RUNTIME_DIR="$runtime_dir" \
		systemctl --user start pipewire wireplumber pipewire-pulse 2>/dev/null \
		|| echo "px13-restore-pipewire: start failed for uid $uid" >&2
done

echo "px13-restore-pipewire: done (altavoces internos pueden seguir rotos hasta reboot)"

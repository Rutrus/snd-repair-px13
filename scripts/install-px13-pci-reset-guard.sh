#!/usr/bin/env bash
# Install a hard refuse of live PCI unbind/bind when snd_repair overlay is present.
# Incident 2026-07-19: PX13_AFTER_SUSPEND=1 + pci_reset froze the machine.
set -euo pipefail

TARGET="${1:-/usr/local/sbin/px13-audio-fix.sh}"
MARKER="snd_repair: refuse PCI reset when overlay present"

if [[ ! -f "$TARGET" ]]; then
	echo "Missing $TARGET" >&2
	exit 1
fi

if grep -Fq "$MARKER" "$TARGET"; then
	echo "Guard already present in $TARGET"
	exit 0
fi

if [[ ! -w "$TARGET" ]]; then
	echo "Root required. Run:" >&2
	echo "  sudo $0 $TARGET" >&2
	exit 1
fi

cp -a "$TARGET" "$TARGET.bak.$(date +%Y%m%d%H%M%S)"

python3 - "$TARGET" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
needle = "pci_reset() {\n\tlocal unbind_ok=1\n"
guard = """pci_reset() {
\t# snd_repair: refuse PCI reset when overlay present (freeze risk 2026-07-19)
\tlocal kver overlay
\tkver="$(uname -r)"
\toverlay="/lib/modules/${kver}/updates/snd_repair"
\tif [[ -d "$overlay" && "${PX13_ALLOW_PCI_RESET:-0}" != "1" ]]; then
\t\tlog "REFUSING PCI reset: $overlay present (hard freeze risk)"
\t\tlog "Safe recover: cold power cycle. Override only with PX13_ALLOW_PCI_RESET=1"
\t\treturn 1
\tfi
\tlocal unbind_ok=1
"""
if needle not in text:
    sys.stderr.write("Could not find pci_reset() anchor in script\n")
    sys.exit(1)
path.write_text(text.replace(needle, guard, 1))
print(f"Patched {path}")
PY

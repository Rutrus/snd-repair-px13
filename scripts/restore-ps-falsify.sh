#!/usr/bin/env bash
# Strip Phase 9 falsification hunks from ps-common.c / pci-ps.c (keep Phase 7/8 observation).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SRC="$KERNEL_SRC"
PS="$SRC/sound/soc/amd/ps"

python3 - "$PS/ps-common.c" "$PS/pci-ps.c" <<'PY'
import re, sys
from pathlib import Path

def clean_ps_common(text):
    # Remove entire Phase 9 patch A or B block up to ENB=1 writel
    text = re.sub(
        r'\n\t/\* Phase 9 / patch [AB]:.*?(?=\n\twritel\(1, acp_base \+ ACP_EXTERNAL_INTR_ENB\);)',
        '\n', text, flags=re.DOTALL)
    # Orphan patch A lines if partial strip
    text = re.sub(
        r'\n\twritel\(ACP_SDW1_STAT, acp_base \+ ACP_EXTERNAL_INTR_STAT1\);\n'
        r'\treadl\(acp_base \+ ACP_EXTERNAL_INTR_STAT1\);\n'
        r'\tpr_info\("PHASE9 ctx=acp fn=falsify patch=A[^"]*"\,\n'
        r'\t\treadl\(acp_base \+ ACP_EXTERNAL_INTR_STAT1\)\);\n\t?\n?',
        '\n', text)
    text = re.sub(r'(\tu32 sdw0_wake_en, sdw1_wake_en;\n)\n+', r'\1\n', text)
    text = re.sub(r'\n\t+\twritel\(1, acp_base \+ ACP_EXTERNAL_INTR_ENB\);',
                  '\n\twritel(1, acp_base + ACP_EXTERNAL_INTR_ENB);', text)
    return text

def clean_pci_ps(text):
    text = re.sub(r'\tpci_set_master\(pci\);\n\tpr_info\("PHASE9 ctx=acp fn=falsify patch=D\\n"\);\n', '', text)
    text = re.sub(
        r'\tenable_irq\(pci->irq\);\n\tpr_info\("PHASE9 ctx=acp fn=falsify patch=E irq=%d\\n", pci->irq\);\n',
        '', text)
    return text

for path in sys.argv[1:]:
    p = Path(path)
    if not p.is_file():
        continue
    t = p.read_text()
    n = clean_ps_common(t) if 'ps-common' in path else clean_pci_ps(t)
    if n != t:
        p.write_text(n)
        print(f"restored: {path}")
    else:
        print(f"unchanged: {path}")
PY

echo "OK: ps sources ready for next falsification patch"

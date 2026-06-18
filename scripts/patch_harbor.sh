#!/bin/bash
# Patch Harbor's claude-code agent to:
# 1. Install Node.js + npm on apt-get systems (not just curl)
# 2. Use npm to install CC CLI (avoid claude.ai region block)
# 3. Use npmmirror.com registry for China accessibility
#
# Usage: bash scripts/patch_harbor.sh [venv_path]
#   Default venv: .venv_harbor/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VENV="${1:-$PROJECT_DIR/.venv_harbor}"

CLAUDE_CODE_PY="$VENV/lib/python3.13/site-packages/harbor/agents/installed/claude_code.py"

if [ ! -f "$CLAUDE_CODE_PY" ]; then
    # Try other Python versions
    CLAUDE_CODE_PY=$(find "$VENV/lib" -name "claude_code.py" -path "*/harbor/agents/installed/*" 2>/dev/null | head -1)
fi

if [ ! -f "$CLAUDE_CODE_PY" ]; then
    echo "Error: Harbor claude_code.py not found in $VENV"
    echo "Make sure Harbor is installed: pip install harbor"
    exit 1
fi

echo "Patching: $CLAUDE_CODE_PY"

# Check if already patched
if grep -q "npm config set registry" "$CLAUDE_CODE_PY" 2>/dev/null; then
    echo "  Already patched, skipping."
    exit 0
fi

# Apply patch: modify install() method
python3 << 'PYEOF'
import sys, re

target = sys.argv[1] if len(sys.argv) > 1 else None
if not target:
    print("No target file")
    sys.exit(1)

with open(target) as f:
    content = f.read()

# Patch 1: apt-get install also nodejs + npm, and set npm mirror
old_apt = 'apt-get update && apt-get install -y curl;'
new_apt = 'apt-get update && apt-get install -y curl nodejs npm && npm config set registry https://registry.npmmirror.com;'
if old_apt in content:
    content = content.replace(old_apt, new_apt)
    print("  ✓ apt-get now installs nodejs + npm with mirror")
else:
    print("  ⚠ apt-get line not found (may already be patched)")

# Patch 2: Always use npm install, never curl claude.ai
old_install = '''set -euo pipefail; if command -v apk &> /dev/null; then  npm install -g @anthropic-ai/claude-code; else  curl -fsSL https://claude.ai/install.sh | bash -s --; fi &&'''
new_install = '''set -euo pipefail; npm install -g @anthropic-ai/claude-code;'''
if old_install in content:
    content = content.replace(old_install, new_install)
    print("  ✓ npm install replaces curl claude.ai")
else:
    print("  ⚠ install line not found (may already be patched)")

with open(target, 'w') as f:
    f.write(content)

print("  Patch applied successfully.")
PYEOF "$CLAUDE_CODE_PY"

#!/bin/bash
# Configure Upskill hooks in the current project's .claude/settings.local.json
set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
SETTINGS_FILE="$PROJECT_DIR/.claude/settings.local.json"
HOOKS_DIR="$HOME/.claude/hooks"
CLAUDE_MD="$HOME/.claude/upskill-store/CLAUDE.md"

log() { echo "  $*"; }

echo ""
echo "== Configuring Upskill hooks for project =="
echo "  Project: $PROJECT_DIR"

PYTHON="${PYTHON:-python3}"
"$PYTHON" - "$SETTINGS_FILE" "$HOOKS_DIR" "$CLAUDE_MD" <<'PY'
import json
import shlex
import sys
from pathlib import Path

settings_path = Path(sys.argv[1])
hooks_dir = Path(sys.argv[2])
claude_md = sys.argv[3]

if settings_path.exists():
    try:
        existing = json.loads(settings_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise SystemExit(f"ERROR: cannot read existing settings as JSON: {exc}")
    if not isinstance(existing, dict):
        raise SystemExit("ERROR: existing settings must be a JSON object")
else:
    existing = {}

hooks = existing.setdefault("hooks", {})
if not isinstance(hooks, dict):
    raise SystemExit("ERROR: existing 'hooks' setting must be a JSON object")

for hook_type, script_name in (
    ("UserPromptSubmit", "capture-prompt.sh"),
    ("SessionStart", "before-session.sh"),
    ("SessionEnd", "after-session.sh"),
):
    entries = hooks.setdefault(hook_type, [])
    if not isinstance(entries, list):
        raise SystemExit(f"ERROR: existing hooks.{hook_type} setting must be a JSON array")

    script_path = hooks_dir / script_name
    entry = {
        "matcher": "",
        "hooks": [
            {
                "type": "command",
                "command": f"bash {shlex.quote(str(script_path))}",
            }
        ],
    }
    if entry not in entries:
        entries.append(entry)

# Respect an existing project-specific CLAUDE.md setting.
existing.setdefault("claudeMd", claude_md)

settings_path.parent.mkdir(parents=True, exist_ok=True)
settings_path.write_text(json.dumps(existing, indent=2) + "\n", encoding="utf-8")
PY

log "Merged Upskill hooks into $SETTINGS_FILE"
log "Done. Hooks will run when Claude Code starts in this project."
echo ""

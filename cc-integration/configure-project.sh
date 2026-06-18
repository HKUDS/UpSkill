#!/bin/bash
# Configure Upskill hooks in the current project's .claude/settings.local.json
set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
SETTINGS_FILE="$PROJECT_DIR/.claude/settings.local.json"
HOOKS_DIR="$HOME/.claude/hooks"

log() { echo "  $*"; }

echo ""
echo "== Configuring Upskill hooks for project =="
echo "  Project: $PROJECT_DIR"

mkdir -p "$PROJECT_DIR/.claude"

PATCH=$(cat << EOF
{
  "claudeMd": "$HOME/.claude/upskill-store/CLAUDE.md",
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash $HOOKS_DIR/capture-prompt.sh"
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash $HOOKS_DIR/before-session.sh"
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash $HOOKS_DIR/after-session.sh"
          }
        ]
      }
    ]
  }
}
EOF
)

if [ -f "$SETTINGS_FILE" ]; then
    log "Merging into existing .claude/settings.local.json..."
    echo "$PATCH" | python3 -c "
import json, sys
patch = json.load(sys.stdin)
try:
    existing = json.load(open('$SETTINGS_FILE'))
except:
    existing = {}
for section in ['hooks']:
    if section in patch:
        for hook_type, entries in patch[section].items():
            # Replace entire hook type array to avoid stale duplicates from older versions
            existing.setdefault(section, {})[hook_type] = entries
if 'claudeMd' in patch and 'claudeMd' not in existing:
    existing['claudeMd'] = patch['claudeMd']
with open('$SETTINGS_FILE', 'w') as f:
    json.dump(existing, f, indent=2)
    f.write('\n')
"
    log "Merged hooks into $SETTINGS_FILE"
else
    echo "$PATCH" > "$SETTINGS_FILE"
    log "Created $SETTINGS_FILE"
fi

log "Done. Hooks will run when Claude Code starts in this project."
echo ""

# /upskill-uninstall

Completely remove Upskill CC Integration and restore to pre-install state.

## Usage
`/upskill-uninstall`

## What it removes
1. `~/.claude/upskill-store/` — all skills and building data
2. `~/.claude/skills/upskill-*` — all slash commands
3. `~/.claude/hooks/{after-session,before-session,inject-skill,upskill-build,upskill-store,configure-project,capture-prompt}.sh` + `parse-skill.py`
4. `~/.claude/upskill.conf` — model config

## What it does NOT remove
- `~/.claude/settings.json` entries — shown for manual cleanup
- Project `.claude/settings.local.json` entries — shown for manual cleanup

## Implementation

### Step 1: Show what will be removed
```bash
echo "=== Upskill files to be removed ==="
echo ""
echo "Upskill Store:"
ls -la ~/.claude/upskill-store/ 2>/dev/null || echo "  (empty)"
echo ""
echo "Skills:"
ls -d ~/.claude/skills/upskill-* 2>/dev/null || echo "  (none)"
echo ""
echo "Hooks:"
ls ~/.claude/hooks/{after-session,before-session,inject-skill,upskill-build,upskill-store,configure-project,capture-prompt}.sh ~/.claude/hooks/parse-skill.py 2>/dev/null || echo "  (none)"
echo ""
echo "Config:"
ls ~/.claude/upskill.conf 2>/dev/null || echo "  (none)"
```

### Step 2: Ask for confirmation
"Remove ALL Upskill files listed above? This cannot be undone. [y/N]"

### Step 3: Remove
```bash
rm -rf ~/.claude/upskill-store
rm -rf ~/.claude/skills/upskill-*
rm -f ~/.claude/hooks/after-session.sh ~/.claude/hooks/before-session.sh
rm -f ~/.claude/hooks/inject-skill.sh ~/.claude/hooks/upskill-build.sh
rm -f ~/.claude/hooks/upskill-store.sh ~/.claude/hooks/parse-skill.py
rm -f ~/.claude/hooks/configure-project.sh ~/.claude/hooks/capture-prompt.sh
rm -f ~/.claude/upskill.conf
```

### Step 4: Show manual cleanup
```
Upskill files removed.

Manual cleanup (if desired):
- Remove 'claudeMd' and 'hooks' entries from ~/.claude/settings.json
- Remove project .claude/settings.local.json if only used for Upskill
```

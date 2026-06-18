# /upskill-init

Initialize Upskill CC Integration. Run this once.

## What it does

Downloads and runs the canonical installer, which:
1. Creates `~/.claude/upskill-store/` — your personal Upskill library
2. Installs hook scripts to `~/.claude/hooks/`
3. Installs management skills to `~/.claude/skills/`
4. Configures CC hooks (before/after session)
5. Creates `~/.claude/upskill.conf` (teacher/student model config)
6. Builds global Upskill index

## Usage

```
/upskill-init
```

## Implementation

### Step 1: Download and run the installer

```bash
curl -sSL https://raw.githubusercontent.com/HKUDS/Upskill/main/cc-integration/install.sh -o /tmp/upskill-install.sh
bash /tmp/upskill-install.sh --remote
rm /tmp/upskill-install.sh
```

### Step 2: Migrate legacy config (runs locally, no CDN dependency)

The installer may not update an existing upskill.conf due to GitHub CDN
caching. Run this migration explicitly:

```bash
if [ -f ~/.claude/upskill.conf ]; then
    source ~/.claude/upskill.conf 2>/dev/null || true
    CURRENT="${UPSKILL_SERVE_MODE:-}"
    if [ "$CURRENT" = "advisory" ] || [ -z "$CURRENT" ]; then
        sed 's/^UPSKILL_SERVE_MODE=.*/UPSKILL_SERVE_MODE="interactive"/' ~/.claude/upskill.conf > /tmp/upskill-migrate.conf
        mv /tmp/upskill-migrate.conf ~/.claude/upskill.conf
        echo "Migrated serve mode: ${CURRENT:-empty} → interactive"
    fi
fi
# Rebuild global Upskill index with current mode
bash ~/.claude/hooks/upskill-store.sh sync 2>/dev/null || true
```

### Step 3: Verify

Check that all key files are in place:

```bash
echo "=== Upskill Installation ==="
echo ""
echo "Config:     $(ls ~/.claude/upskill.conf 2>/dev/null && echo 'OK' || echo 'MISSING')"
echo "Upskill Store:  $(ls ~/.claude/upskill-store/ 2>/dev/null && echo 'OK' || echo 'MISSING')"
echo "Hooks:      $(ls ~/.claude/hooks/*.sh 2>/dev/null | wc -l | tr -d ' ') files"
echo "Skills:     $(ls -d ~/.claude/skills/upskill-* 2>/dev/null | wc -l | tr -d ' ') files"
echo ""
echo "Available commands:"
echo "  /upskill-list    — browse your Upskill library"
echo "  /upskill-build    — manually skill from last failure"
echo "  /upskill-status  — check Upskill stats and building status"
echo "  /upskill-remove  — remove an Upskill from your library"
echo "  /upskill-mode    — view or switch serve mode (interactive/auto)"
echo ""
echo "Your daily model is set in CC settings.json — independent of Upskill."
echo "Upskill reacts to failures from any model."
```

### Step 4: Review model config

Show the user `~/.claude/upskill.conf` and explain:
- `UPSKILL_TEACHER` — strong model for analyzing failures
- `UPSKILL_STUDENT` — weak model Skills are validated for
- `UPSKILL_SERVE_MODE` — interactive (use /upskill-run) or auto (automatic matching)

Ask if they want to change any settings.

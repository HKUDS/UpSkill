#!/bin/bash
# Upskill CC Integration — Canonical Installer
#
# This is the SINGLE installer for Upskill. It works both locally
# (from a cloned repo) and remotely (downloading from GitHub).
#
# Usage:
#   bash install.sh                     # Local install from repo
#   bash install.sh --remote            # Download + install from GitHub
#   bash install.sh --help              # Show help
#   bash install.sh --uninstall         # Remove Upskill
#   bash install.sh --dry-run           # Show what would be installed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
HOOKS_DIR="$CLAUDE_DIR/hooks"
SKILLS_DIR="$CLAUDE_DIR/skills"
export UPSKILL_STORE="$CLAUDE_DIR/upskill-store"

REMOTE=false
DRY_RUN=false
UNINSTALL=false
SHOW_HELP=false

REPO_URL="https://raw.githubusercontent.com/HKUDS/Upskill/main/cc-integration"

# ---- File inventory (single source of truth) ----
HOOK_FILES="after-session.sh before-session.sh inject-skill.sh upskill-build.sh upskill-store.sh parse-skill.py capture-prompt.sh configure-project.sh save-session.sh"
SKILL_FILES="upskill-list.md upskill-build.md upskill-status.md upskill-remove.md upskill-mode.md upskill-model.md upskill-configure.md upskill-uninstall.md upskill-init.md upskill-run.md"
TEMPLATE_FILES="upskill.conf manifest.yaml"

for arg in "$@"; do
    case "$arg" in
        --remote) REMOTE=true ;;
        --dry-run) DRY_RUN=true ;;
        --uninstall) UNINSTALL=true ;;
        --help|-h) SHOW_HELP=true ;;
    esac
done

log() { echo "  $*"; }
header() { echo ""; echo "== $* =="; }
run() {
    if $DRY_RUN; then echo "  [dry-run] $*"; else "$@"; fi
}

# ---- Help ----
if $SHOW_HELP; then
    cat << 'HELP'
Upskill CC Integration Installer
==================================

Install Upskill into Claude Code for automatic skill building and serving.

Usage:
  bash install.sh                 Install from local repo
  bash install.sh --remote        Download + install from GitHub
  bash install.sh --uninstall     Remove Upskill
  bash install.sh --dry-run       Preview what would be installed
  bash install.sh --help          Show this help

What gets installed:
  ~/.claude/hooks/         Building, injection, and configuration scripts
  ~/.claude/skills/        Slash commands (/upskill-list, /upskill-build, ...)
  ~/.claude/upskill-store/     Your personal skill library
  ~/.claude/upskill.conf Model configuration

After install, run in each project you want building enabled:
  bash ~/.claude/hooks/configure-project.sh

Quick start:
  curl -sSL https://raw.githubusercontent.com/HKUDS/Upskill/main/cc-integration/install.sh | bash -s -- --remote
HELP
    exit 0
fi

# ---- Uninstall ----
if $UNINSTALL; then
    header "Uninstalling Upskill CC Integration"
    run rm -rf "$UPSKILL_STORE"
    for f in $HOOK_FILES; do run rm -f "$HOOKS_DIR/$f"; done
    for f in $SKILL_FILES; do skill_name="${f%.md}"; run rm -rf "$SKILLS_DIR/$skill_name"; done
    header "Uninstall complete."
    echo "Note: Hook entries in ~/.claude/settings.local.json were NOT removed."
    echo "Remove upskill-related entries manually if desired."
    exit 0
fi

# ---- Install ----
echo ""
echo "=============================================="
echo "  Upskill CC Integration Installer"
echo "=============================================="
[ "$REMOTE" = true ] && echo "  Mode: remote (downloading from GitHub)"
echo ""

# Clean up stale flat .md skill files from old bootstrap installs
header "Cleaning up legacy files"
for old_flat in "$SKILLS_DIR"/*.md; do
    [ -f "$old_flat" ] || continue
    name=$(basename "$old_flat" .md)
    case "$name" in
        upskill-*) run rm -f "$old_flat" && log "  removed stale flat file: $name.md" ;;
    esac
done
for old_hook in "$HOOKS_DIR"/parse-acp.py "$HOOKS_DIR"/inject-acp.sh; do
    [ -f "$old_hook" ] && run rm -f "$old_hook" && log "  removed stale hook: $(basename "$old_hook")"
done

# Check requirements
header "Checking requirements"
for cmd in git python3 bash curl; do
    if command -v "$cmd" &>/dev/null; then
        log "$cmd: found"
    else
        [ "$cmd" = "curl" ] && [ "$REMOTE" = false ] && continue
        log "ERROR: $cmd is required but not found."
        exit 1
    fi
done

# Create directories
header "Creating directories"
run mkdir -p "$HOOKS_DIR" "$SKILLS_DIR" "$UPSKILL_STORE/.building/sessions"
log "~/.claude/{hooks,skills,upskill-store/}"

# ---- Install files (local or remote) ----
install_file() {
    local src="$1" dest="$2"
    if $REMOTE; then
        local url="$REPO_URL/$src"
        log "  downloading $url"
        $DRY_RUN || curl -sSL "$url" -o "$dest" || { log "  FAILED: $url"; return 1; }
    else
        [ -f "$src" ] || { log "  WARNING: $src not found (use --remote to download)"; return 1; }
        run cp "$src" "$dest"
    fi
}

header "Installing hook scripts"
for f in $HOOK_FILES; do
    case "$f" in
        after-session.sh|before-session.sh) src="hooks/$f" ;;
        *) src="$f" ;;
    esac
    if install_file "$src" "$HOOKS_DIR/$f"; then
        run chmod +x "$HOOKS_DIR/$f"
        log "  $f installed"
    fi
done

header "Installing slash commands"
for f in $SKILL_FILES; do
    skill_name="${f%.md}"
    skill_dir="$SKILLS_DIR/$skill_name"
    run mkdir -p "$skill_dir"
    install_file "skills/$f" "$skill_dir/SKILL.md" && log "  /${skill_name} installed"
done

# Initialize upskill-store
header "Initializing skill store"
if [ ! -f "$UPSKILL_STORE/manifest.yaml" ]; then
    install_file "templates/manifest.yaml" "$UPSKILL_STORE/manifest.yaml" 2>/dev/null || {
        run echo "# Upskill Skill Manifest" > "$UPSKILL_STORE/manifest.yaml"
    }
    log "manifest.yaml created"
else
    log "manifest.yaml already exists, preserved"
fi

# Create model config
header "Creating model config"
UPSKILL_CONF="$CLAUDE_DIR/upskill.conf"
if [ ! -f "$UPSKILL_CONF" ]; then
    if install_file "templates/upskill.conf" "$UPSKILL_CONF" 2>/dev/null; then
        log "upskill.conf created"
    else
        # Fallback: create minimal config
        run cat > "$UPSKILL_CONF" << 'EOF'
UPSKILL_TEACHER="deepseek-v4-pro[1m]"
UPSKILL_STUDENT="deepseek-v4-flash"
UPSKILL_SERVE_MODE="interactive"
EOF
        log "upskill.conf created (default)"
    fi
else
    log "upskill.conf already exists, checking for upgrades..."
    # Migrate legacy serve modes
    source "$UPSKILL_CONF" 2>/dev/null || true
    CURRENT_MODE="${UPSKILL_SERVE_MODE:-}"
    if [ "$CURRENT_MODE" = "advisory" ] || [ -z "$CURRENT_MODE" ]; then
        log "  migrating serve mode: $CURRENT_MODE → interactive"
        sed 's/^UPSKILL_SERVE_MODE=.*/UPSKILL_SERVE_MODE="interactive"/' "$UPSKILL_CONF" > /tmp/skill-migrate.conf
        mv /tmp/skill-migrate.conf "$UPSKILL_CONF"
    else
        log "  serve mode is $CURRENT_MODE — up to date"
    fi
fi

# Build global skill index
header "Building global skill index"
run bash "$HOOKS_DIR/upskill-store.sh" sync 2>/dev/null || true

# Done
echo ""
echo "=============================================="
echo "  Upskill CC Integration Ready"
echo "=============================================="
echo ""
echo "What was installed:"
echo "  Hooks:    ~/.claude/hooks/{$(echo $HOOK_FILES | tr ' ' ',')}"
echo "  Skills:   ~/.claude/skills/{$(echo $SKILL_FILES | sed 's/\.md//g' | tr ' ' ',')}/SKILL.md"
echo "  Config:   ~/.claude/upskill.conf"
echo "  Store:    ~/.claude/upskill-store/"
echo ""
echo "Commands:  /upskill-list  /upskill-build  /upskill-status  /upskill-remove  /upskill-mode  /upskill-model  /upskill-configure  /upskill-uninstall"
echo "Serve mode: interactive (edit ~/.claude/upskill.conf to change)"
echo ""
echo "To enable building per project, run in each project directory:"
echo "  bash ~/.claude/hooks/configure-project.sh"
echo ""

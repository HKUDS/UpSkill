#!/bin/bash
# Deploy an ACP (AgentBrew Configuration Package) non-invasively.
#
# Usage:
#   bash scripts/deploy_acp.sh <acp_dir> <target_project_dir>
#   bash scripts/deploy_acp.sh --revert <acp_dir> <target_project_dir>
#
# Principles:
#   - CLAUDE.md: append if exists, with separator and source tag
#   - skills: copy as-is, never overwrite existing
#   - memory: merge by name (update existing, add new)
set -euo pipefail

REVERT=false
if [ "${1:-}" = "--revert" ]; then
    REVERT=true
    shift
fi

ACP_DIR="${1:?Usage: $0 [--revert] <acp_dir> <target_dir>}"
TARGET_DIR="${2:?Usage: $0 [--revert] <acp_dir> <target_dir>}"

if [ ! -d "$ACP_DIR" ]; then
    echo "Error: ACP dir not found: $ACP_DIR"
    exit 1
fi

MANIFEST="$ACP_DIR/manifest.yaml"
ACP_NAME=$(basename "$ACP_DIR")

log() { echo "[deploy] $*"; }

# ---- Revert mode ----
if $REVERT; then
    log "Reverting $ACP_NAME from $TARGET_DIR"
    if [ ! -f "$MANIFEST" ]; then
        echo "Error: no manifest.yaml found, cannot revert"
        exit 1
    fi
    # Remove deployed files listed in manifest
    while IFS= read -r line; do
        f=$(echo "$line" | sed 's/^  - //')
        [ -z "$f" ] && continue
        target="$TARGET_DIR/$f"
        if [ -f "$target" ] && grep -q "## ACP: $ACP_NAME" "$target" 2>/dev/null; then
            rm "$target"
            log "  removed $f"
        fi
    done < <(grep '^  - ' "$MANIFEST")
    log "Revert complete."
    exit 0
fi

# ---- Deploy mode ----
log "Deploying $ACP_NAME → $TARGET_DIR"
mkdir -p "$TARGET_DIR/.claude/skills"
MEM_SLUG=$(echo -n "$TARGET_DIR" | sed 's|/|-|g')
MEM_DIR="$HOME/.claude/projects/${MEM_SLUG}/memory"
mkdir -p "$MEM_DIR"

# 1. CLAUDE.md — append if exists
if [ -f "$ACP_DIR/CLAUDE.md" ]; then
    ACP_TAG="\n\n---\n## ACP: $ACP_NAME (deployed $(date +%Y-%m-%d))\n"
    if [ -f "$TARGET_DIR/CLAUDE.md" ]; then
        printf "$ACP_TAG" >> "$TARGET_DIR/CLAUDE.md"
        cat "$ACP_DIR/CLAUDE.md" >> "$TARGET_DIR/CLAUDE.md"
        log "  CLAUDE.md: appended to existing"
    else
        cp "$ACP_DIR/CLAUDE.md" "$TARGET_DIR/CLAUDE.md"
        log "  CLAUDE.md: created new"
    fi
fi

# 2. Skills — prefix with acp_ to avoid conflicts
if [ -d "$ACP_DIR/.claude/skills" ]; then
    for skill_file in "$ACP_DIR/.claude/skills/"*.md; do
        [ -f "$skill_file" ] || continue
        skill_name=$(basename "$skill_file" .md)
        dest="$TARGET_DIR/.claude/skills/${skill_name}.md"
        if [ -f "$dest" ]; then
            log "  skill/${skill_name}.md: already exists, skipped"
        else
            cp "$skill_file" "$dest"
            log "  skill/${skill_name}.md: deployed"
        fi
    done
fi

# 3. Memory — merge by name field in frontmatter
if [ -d "$ACP_DIR/memory" ]; then
    for mem_file in "$ACP_DIR/memory/"*.md; do
        [ -f "$mem_file" ] || continue
        mem_name=$(grep '^name:' "$mem_file" 2>/dev/null | head -1 | sed 's/name: *//' || true)
        if [ -z "$mem_name" ]; then
            mem_name=$(basename "$mem_file" .md)
        fi
        dest="$MEM_DIR/${mem_name}.md"
        if [ -f "$dest" ]; then
            log "  memory/${mem_name}.md: updated (overwrite)"
        else
            log "  memory/${mem_name}.md: deployed (new)"
        fi
        cp "$mem_file" "$dest"
    done
    # Update MEMORY.md index
    INDEX="$MEM_DIR/MEMORY.md"
    if [ ! -f "$INDEX" ]; then
        echo "# Memory Index" > "$INDEX"
        echo "" >> "$INDEX"
    fi
    for mem_file in "$ACP_DIR/memory/"*.md; do
        [ -f "$mem_file" ] || continue
        mem_name=$(grep '^name:' "$mem_file" 2>/dev/null | head -1 | sed 's/name: *//' || true)
        mem_desc=$(grep '^description:' "$mem_file" 2>/dev/null | head -1 | sed 's/description: *//' || echo "")
        [ -z "$mem_name" ] && mem_name=$(basename "$mem_file" .md)
        if ! grep -q "$mem_name" "$INDEX" 2>/dev/null; then
            echo "- [$mem_name](${mem_name}.md) — $mem_desc" >> "$INDEX"
            log "  MEMORY.md: indexed $mem_name"
        fi
    done
fi

log "Deploy complete: $ACP_NAME"

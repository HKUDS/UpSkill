#!/bin/bash
# before-session hook — notify if building is pending.
#
# Skill content (including feedback/lessons) is loaded on-demand via
# /upskill-run, so no per-project memory sync is needed.
set -euo pipefail

UPSKILL_STORE="$HOME/.claude/upskill-store"
PENDING_FLAG="$UPSKILL_STORE/.building/pending_build"
FIRST_PROMPT="$UPSKILL_STORE/.building/first_prompt.txt"

log() { echo "[upskill] $(date +%H:%M:%S) $*"; }

# Ensure directory exists (first install may not have it yet)
mkdir -p "$(dirname "$FIRST_PROMPT")"

# Clear first-prompt and transcript-path flags for the new session
rm -f "$FIRST_PROMPT" "$UPSKILL_STORE/.building/transcript_path.txt"

# Check for pending skill
if [ -f "$PENDING_FLAG" ]; then
    META_FILE="$UPSKILL_STORE/.building/sessions/latest/metadata.txt"
    PROMPT_PREVIEW=""
    if [ -f "$META_FILE" ]; then
        PROMPT_PREVIEW=$(grep '^summary=' "$META_FILE" | cut -d= -f2- | cut -c1-100)
    fi

    echo ""
    echo "  Upskill: Your last session may have failed."
    if [ -n "$PROMPT_PREVIEW" ]; then
        echo "  Task: $PROMPT_PREVIEW..."
    fi
    echo "  Run /upskill-build to analyze the failure and generate a skill."
    echo ""
fi

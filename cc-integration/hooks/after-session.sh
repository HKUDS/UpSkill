#!/bin/bash
# SessionEnd hook — save session context for potential building.
#
# If /upskill-build already saved this session mid-flight (detected via
# .last_save marker), we update the existing entry instead of creating a
# duplicate.  Otherwise calls save-session.sh.
set -euo pipefail

UPSKILL_STORE="$HOME/.claude/upskill-store"
PENDING_FLAG="$UPSKILL_STORE/.building/pending_build"
FIRST_PROMPT_FILE="$UPSKILL_STORE/.building/first_prompt.txt"
LAST_SAVE_MARKER="$UPSKILL_STORE/.building/.last_save"
HOOKS_DIR="$(cd "$(dirname "$0")" && pwd)"

log() { echo "[upskill] $(date +%H:%M:%S) $*"; }

EXIT_CODE="${CC_HOOK_EXIT_CODE:-0}"
SESSION_LOG="${CC_HOOK_SESSION_LOG:-}"

# ---- Save the session ----
# Check if /upskill-build already saved this session mid-flight.
# If the marker is fresh (< 5 min old), update that entry instead of
# creating a duplicate.
SAVED_DIR=""
if [ -f "$LAST_SAVE_MARKER" ]; then
    CANDIDATE=$(cat "$LAST_SAVE_MARKER" 2>/dev/null || echo "")
    MARKER_AGE=$(python3 -c "import os,time; print(int(time.time()-os.path.getmtime('$LAST_SAVE_MARKER')))" 2>/dev/null || echo "999")
    if [ -n "$CANDIDATE" ] && [ -d "$CANDIDATE" ] && [ "$MARKER_AGE" -lt 300 ]; then
        # Re-use the mid-session save — just update exit_code and status
        if [ "$EXIT_CODE" != "0" ]; then
            SESS_STATUS="FAIL (exit $EXIT_CODE)"
        else
            SESS_STATUS="PASS"
        fi
        META_TMP="${CANDIDATE}/.tmp_update_metadata"
        # Re-read metadata, update status/exit_code, write back
        {
            grep -v '^exit_code=\|^status=' "$CANDIDATE/metadata.txt" 2>/dev/null || true
            echo "exit_code=$EXIT_CODE"
            echo "status=$SESS_STATUS"
        } > "$META_TMP"
        mv "$META_TMP" "$CANDIDATE/metadata.txt"
        SAVED_DIR="$CANDIDATE"
        log "Updated mid-session save: $(basename "$SAVED_DIR")"
    fi
    rm -f "$LAST_SAVE_MARKER"
fi

if [ -z "$SAVED_DIR" ]; then
    SAVED_DIR=$("$HOOKS_DIR/save-session.sh" 2>/dev/null || echo "")
fi

if [ -z "$SAVED_DIR" ] || [ ! -d "$SAVED_DIR" ]; then
    log "ERROR: save-session.sh failed, session not saved"
    exit 1
fi

# Clear first_prompt.txt so the next session gets a fresh capture.
rm -f "$FIRST_PROMPT_FILE"

# ---- Detect failure ----
FAILED=false
REASON=""

if [ "$EXIT_CODE" != "0" ]; then
    FAILED=true
    REASON="exit code $EXIT_CODE"
fi

if [ -n "$SESSION_LOG" ] && [ -f "$SESSION_LOG" ]; then
    if grep -qi 'BUILD_RESULT: FAIL\|I cannot complete this task\|I am unable to complete' "$SESSION_LOG" 2>/dev/null; then
        FAILED=true
        REASON="self-reported failure"
    fi
fi

# ---- Notify ----
if $FAILED; then
    log "Suspected failure ($REASON). Session saved."
    touch "$PENDING_FLAG"
    echo ""
    echo "  ⚠ Upskill: this session may have failed ($REASON)."
    echo "  Run /upskill-build to analyze and learn from it."
    echo ""
else
    log "Session ended (exit=$EXIT_CODE). Saved."
    rm -f "$PENDING_FLAG"
    echo ""
    echo "  ✓ Upskill: session saved (exit=$EXIT_CODE)."
    echo "  Run /upskill-build anytime to capture this workflow as a skill."
    echo ""
fi

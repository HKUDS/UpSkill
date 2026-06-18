#!/bin/bash
# save-session.sh — save current session to the sessions directory.
#
# Called by:
#   - after-session.sh  (SessionEnd hook, has CC_HOOK_* env vars)
#   - /upskill-build    (mid-session, uses files from capture-prompt.sh)
#
# When run mid-session (no CC_HOOK_* vars), it reads first_prompt.txt
# and converts the current transcript to session.log on the fly.
#
# Outputs the session directory path on stdout.
set -euo pipefail

UPSKILL_STORE="${UPSKILL_STORE:-$HOME/.claude/upskill-store}"
SESSIONS_DIR="$UPSKILL_STORE/.building/sessions"
TS=$(date +%s)
SESSION_ID="session_${TS}"
FIRST_PROMPT_FILE="$UPSKILL_STORE/.building/first_prompt.txt"

log() { echo "[upskill] $(date +%H:%M:%S) $*" >&2; }

EXIT_CODE="${CC_HOOK_EXIT_CODE:-0}"
SESSION_LOG="${CC_HOOK_SESSION_LOG:-}"
PROMPT="${CC_HOOK_PROMPT:-}"

# ---- Capture prompt ----
# Priority: first_prompt.txt (first task prompt) > CC_HOOK_PROMPT > session log
if [ -z "$PROMPT" ] && [ -f "$FIRST_PROMPT_FILE" ]; then
    PROMPT=$(head -1 "$FIRST_PROMPT_FILE" | tr '\n' ' ' | cut -c1-500)
fi
if [ -z "$PROMPT" ] && [ -n "$SESSION_LOG" ] && [ -f "$SESSION_LOG" ]; then
    PROMPT=$(head -100 "$SESSION_LOG" 2>/dev/null | grep -v '^\[' | grep -v '^$' | head -5 | tr '\n' ' ' || echo "")
fi

# ---- Detect Upskill self-commands ----
IS_UPSKILL=false
if printf "%s" "$PROMPT" | grep -qE '^/(upskill)'; then
    IS_UPSKILL=true
elif printf "%s" "$PROMPT" | grep -q '^{"'; then
    INNER=$(printf "%s" "$PROMPT" | python3 -c "import sys,json; m=json.loads(sys.stdin.read()); print(m.get('prompt','') or '')" 2>/dev/null || echo "")
    if printf "%s" "$INNER" | grep -qE '^/(upskill)'; then
        IS_UPSKILL=true
    fi
fi

# ---- Generate a human-readable summary ----
SUMMARY=""
if [ -n "$PROMPT" ] && [ "$PROMPT" != "(prompt not captured"* ]; then
    RAW="$PROMPT"
    if printf "%s" "$RAW" | grep -q '^{"'; then
        RAW=$(printf "%s" "$RAW" | python3 -c "import sys,json; m=json.loads(sys.stdin.read()); print(m.get('prompt','') or m.get('message','') or '')" 2>/dev/null || echo "$RAW")
    fi
    TITLE=$(printf "%s" "$RAW" | python3 -c "
import sys, re
text = sys.stdin.read()
m = re.search(r'##\s*任务[：:]\s*(.{4,80})', text)
if not m: m = re.search(r'##\s*Task[：:]\s*(.{4,80})', text)
if m: print(m.group(1).strip())
" 2>/dev/null)
    if [ -n "$TITLE" ]; then
        SUMMARY="$TITLE"
    else
        SUMMARY=$(printf "%s" "$RAW" | grep -v '^#' | grep -v '^$' | grep -v '全部完成' | grep -v 'BUILD_RESULT' | grep -v '^```' | head -1 | sed 's/^[ \t\/-]*//' | cut -c1-80)
    fi
fi
[ -z "$SUMMARY" ] && SUMMARY="(no description)"

# ---- Determine status label ----
if [ "$EXIT_CODE" != "0" ]; then
    SESS_STATUS="FAIL (exit $EXIT_CODE)"
else
    SESS_STATUS="PASS"
fi

# ---- Save metadata ----
SESSION_DIR="$SESSIONS_DIR/$SESSION_ID"
rm -f "$SESSIONS_DIR"/.tmp_*.txt "$SESSIONS_DIR"/.tmp_*.log 2>/dev/null || true
mkdir -p "$SESSION_DIR"

META_TMP="$SESSIONS_DIR/.tmp_${SESSION_ID}_metadata"
{
    echo "timestamp=$TS"
    echo "exit_code=$EXIT_CODE"
    echo "status=$SESS_STATUS"
    echo "summary=$SUMMARY"
    echo "upskill=$IS_UPSKILL"
    echo "prompt=$PROMPT"
} > "$META_TMP"
mv "$META_TMP" "$SESSION_DIR/metadata.txt"

# ---- Save session log ----
if [ -z "$SESSION_LOG" ] || [ ! -f "$SESSION_LOG" ]; then
    TRANSCRIPT_PATH_FILE="$UPSKILL_STORE/.building/transcript_path.txt"
    if [ -f "$TRANSCRIPT_PATH_FILE" ]; then
        CANDIDATE=$(cat "$TRANSCRIPT_PATH_FILE" 2>/dev/null || echo "")
        if [ -n "$CANDIDATE" ] && [ -f "$CANDIDATE" ]; then
            SESSION_LOG="$CANDIDATE"
        fi
    fi
fi

if [ -n "$SESSION_LOG" ] && [ -f "$SESSION_LOG" ]; then
    LOG_TMP="$SESSIONS_DIR/.tmp_${SESSION_ID}_log"
    python3 -c "
import json, sys
with open('$SESSION_LOG') as f:
    lines = f.readlines()
out = []
for line in lines[-500:]:
    try:
        d = json.loads(line)
    except:
        continue
    t = d.get('type','')
    if t == 'user':
        msg = d.get('message',{})
        if isinstance(msg, dict):
            content = msg.get('content','')
        elif isinstance(msg, str):
            content = msg
        else:
            content = ''
        if isinstance(content, list):
            texts = [b.get('text','') for b in content if isinstance(b, dict) and b.get('type')=='text']
            content = '\n'.join(texts)
        if content:
            out.append(f'[USER] {str(content)[:3000]}')
    elif t == 'assistant':
        msg = d.get('message',{})
        if isinstance(msg, dict):
            content = msg.get('content','')
        elif isinstance(msg, str):
            content = msg
        else:
            content = ''
        if isinstance(content, list):
            texts = [b.get('text','') for b in content if isinstance(b, dict) and b.get('type')=='text']
            content = '\n'.join(texts)
        if content:
            out.append(f'[ASSISTANT] {str(content)[:3000]}')
with open('$LOG_TMP', 'w') as f:
    f.write('\n\n'.join(out))
" 2>/dev/null || cp "$SESSION_LOG" "$LOG_TMP" 2>/dev/null || true
    mv "$LOG_TMP" "$SESSION_DIR/session.log" 2>/dev/null || true
    log "Session log saved ($(wc -c < "$SESSION_DIR/session.log") bytes)"
else
    echo "session_ts=$TS" > "$SESSION_DIR/session.log"
    log "No session log available, saved timestamp only"
fi

# ---- Symlink "latest" ----
ln -sfn "$SESSION_DIR" "$SESSIONS_DIR/latest"

# ---- Write marker for duplicate detection ----
# after-session.sh checks this to avoid re-saving the same session.
echo "$SESSION_DIR" > "$UPSKILL_STORE/.building/.last_save"

# ---- Clean old sessions ----
ls -1d "$SESSIONS_DIR"/session_* 2>/dev/null | sort -r | tail -n +11 | while read -r old; do
    rm -rf "$old"
    log "Cleaned old session: $(basename "$old")"
done

echo "$SESSION_DIR"

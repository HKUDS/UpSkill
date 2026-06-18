# /upskill-build

Trigger Upskill to analyze a session and generate a skill. Works with both failed and successful sessions.

## Usage
`/upskill-build [--category <name>] [--session <id>]`

If no session is specified, uses the most recent session.
If no category is specified, auto-detect from the task prompt.

## When to use
- **After a failure** — analyze what went wrong and generate guidance to prevent it
- **After a success** — capture a working workflow as a reusable skill for similar tasks
- **Anytime** — skill from any recent session (keeps last 10)

## What it does
1. Lists recent sessions from `~/.claude/upskill-store/.building/sessions/` with auto-extracted task titles
2. User picks a session (or uses latest)
3. Reads the full session content and generates an AI summary of what happened
4. **Task selection**: extracts distinct tasks from the session and lets user pick which one(s) to skill
5. Runs the worktree-based building pipeline for each selected task:
   - Teacher model solves the task
   - Analyzes the session trajectory
   - Generates skill (SKILL.md with domain knowledge + steps + feedback)
   - Ralph validates with student model in git worktree
6. If validated: stores the skill globally, clears any pending notification
7. Reports the result

## Implementation

### Step 0: Save current session (if active)
Before listing past sessions, save the current session so it appears in the list. This lets the user build a skill from the session they are currently in without needing to exit CC first.

```bash
# Check if there is an active session with data worth saving
TRANSCRIPT_FILE="$HOME/.claude/upskill-store/.building/transcript_path.txt"
FIRST_PROMPT_FILE="$HOME/.claude/upskill-store/.building/first_prompt.txt"
HAS_CURRENT=false

if [ -f "$TRANSCRIPT_FILE" ]; then
    TP=$(cat "$TRANSCRIPT_FILE" 2>/dev/null || echo "")
    if [ -n "$TP" ] && [ -f "$TP" ]; then
        HAS_CURRENT=true
    fi
fi
# Also check if first_prompt.txt has content (session did useful work)
if [ -f "$FIRST_PROMPT_FILE" ] && [ -s "$FIRST_PROMPT_FILE" ]; then
    HAS_CURRENT=true
fi

if $HAS_CURRENT; then
    bash ~/.claude/hooks/save-session.sh 2>/dev/null
fi
```

### Step 1: List recent sessions (skip Upskill self-commands)
Save the session directories to a temp file so step 2 can look up the correct one by index. This avoids `ls -1dt | head -1` picking an empty/incomplete session directory.

```bash
SESS_LIST="/tmp/upskill_sessions_$$.txt"
rm -f "$SESS_LIST"
i=1
for d in $(ls -1dt ~/.claude/upskill-store/.building/sessions/session_*/ 2>/dev/null); do
    [ -f "$d/metadata.txt" ] || continue
    # Skip Upskill self-command sessions
    grep -q '^upskill=true$' "$d/metadata.txt" 2>/dev/null && continue
    ts=$(grep '^timestamp=' "$d/metadata.txt" | cut -d= -f2)
    sess_status=$(grep '^status=' "$d/metadata.txt" | cut -d= -f2)
    summary=$(grep '^summary=' "$d/metadata.txt" | cut -d= -f2)
    when=$(date -r "$ts" "+%m-%d %H:%M" 2>/dev/null || echo "?")
    echo "$i. [$sess_status] $when — $summary"
    # Save: index|dir_path
    echo "$i|$d" >> "$SESS_LIST"
    i=$((i+1))
done
if [ "$i" -eq 1 ]; then
    echo "(no non-Upskill sessions found)"
    rm -f "$SESS_LIST"
fi
```

Display as a numbered list the user can pick from. User enters the number or presses Enter for the first one.

### Step 2: Select session
Look up the session directory from the saved list by index. If `--session` was passed, use that session ID directly.

```bash
# User chose NUMBER (or 1 for default)
CHOSEN_INDEX="${USER_CHOICE:-1}"
SESS_DIR=$(grep "^${CHOSEN_INDEX}|" "$SESS_LIST" | cut -d'|' -f2)
# Fallback: if list file doesn't exist, use the latest symlink (always points to a valid session)
if [ -z "$SESS_DIR" ]; then
    SESS_DIR=$(cd ~/.claude/upskill-store/.building/sessions/latest 2>/dev/null && pwd -P || echo "")
fi
rm -f "$SESS_LIST"
```

If SESS_DIR is still empty or the session doesn't have required files, report the error and let the user pick a different session.

### Step 2b: Generate AI summary of the session
Read the selected session's content. Verify the files exist first:
```bash
if [ ! -f "$SESS_DIR/metadata.txt" ]; then
    echo "Error: session directory exists but metadata.txt is missing. The session may have been corrupted."
    echo "Try another session number."
fi
cat "$SESS_DIR/metadata.txt"
cat "$SESS_DIR/session.log"
```

Then, based on what you read, generate a concise summary (2-3 sentences) describing:
- What task was being done
- What approach was taken (key decisions, tools used)
- Whether it succeeded or failed, and why

Example: "This session implemented a mini grep tool (mgrep.py) with regex search, recursive directory traversal, and case-insensitive mode. All 5 tests passed. The implementation used Python's `re` module with compiled patterns and argparse for CLI handling."

### Step 3: Extract and select task
A session may contain multiple distinct tasks. Extract all substantial user prompts
from the session log, present them to the user, and let them pick which one to build.

First, extract candidate tasks from the session log:
```bash
python3 -c "
import re, sys

with open('$SESS_DIR/session.log') as f:
    content = f.read()

# Extract all [USER] messages
user_msgs = re.findall(r'\[USER\]\s*(.+?)(?=\[|$)', content, re.DOTALL)
candidates = []
for msg in user_msgs:
    msg = msg.strip()
    # Skip trivial responses: short, confirmations, follow-ups to agent output
    if len(msg) < 30:
        continue
    # Skip pure confirmations / continuations
    if re.match(r'^(yes|no|ok|okay|continue|go on|next|proceed|thanks|done|y|n)$', msg, re.IGNORECASE):
        continue
    # Skip pure slash commands
    if re.match(r'^/(upskill|clear|compact|config|help|doctor|init|memory)', msg):
        continue
    # Skip JSON-only messages (Claude tool use wrappers)
    if msg.startswith('{'):
        continue
    # Truncate for display
    preview = msg[:120] + ('...' if len(msg) > 120 else '')
    candidates.append(preview)

# Deduplicate while preserving order
seen = set()
unique = []
for c in candidates:
    if c not in seen:
        seen.add(c)
        unique.append(c)

for i, c in enumerate(unique, 1):
    print(f'{i}. {c}')
print(f'  Total: {len(unique)} candidate task(s)')
" 2>/dev/null
```

Display the extracted tasks as a numbered list. Also show the overall session summary
(from metadata.txt) for context. Then ask:

```
This session contains multiple interactions. Which task would you like to build?
Enter a number (1-<N>), or press Enter to build the first task, or "all" to build everything as one.
```

If the user picks a specific number, extract the full text of that user message
from the session log as the TASK_PROMPT. Use it (not the session's raw first prompt)
as the building target:

```bash
TASK_PROMPT=$(python3 -c "
import re
with open('$SESS_DIR/session.log') as f:
    content = f.read()
msgs = re.findall(r'\[USER\]\s*(.+?)(?=\[|$)', content, re.DOTALL)
# Same filtering as above to get the correct index
# (simplified: the chosen index maps to the same filtered list)
i = 0
target_idx = $CHOSEN_TASK_INDEX
for msg in msgs:
    msg = msg.strip()
    if len(msg) < 30:
        continue
    if re.match(r'^(yes|no|ok|okay|continue|go on|next|proceed|thanks|done|y|n)$', msg, re.IGNORECASE):
        continue
    if re.match(r'^/(upskill|clear|compact|config|help|doctor|init|memory)', msg):
        continue
    if msg.startswith('{'):
        continue
    i += 1
    if i == target_idx:
        print(msg.strip())
        break
" 2>/dev/null)
```

If "all", use the session's first prompt from metadata (same as Step 4 below).

If there's only one candidate task, skip the selection prompt and proceed directly.

### Step 4: Run building
```bash
CATEGORY="<detected-or-user-specified>"
bash ~/.claude/hooks/upskill-build.sh "$TASK_PROMPT" \
    "$SESS_DIR/session.log" \
    "$CATEGORY"
```

### Step 5: Clear pending flag
```bash
rm -f ~/.claude/upskill-store/.building/pending_build
```

### Step 6: Report result
Check `~/.claude/upskill-store/.building/<skill_id>/final_result.txt`.
- PASS → "Skill validated and installed. Will be suggested for similar tasks."
- FAIL → "Building could not produce a valid skill after 3 attempts."

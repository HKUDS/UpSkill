#!/bin/bash
# capture-prompt.sh — UserPromptSubmit hook: save the FIRST substantial prompt per session.
set -euo pipefail

UPSKILL_STORE="${UPSKILL_STORE:-$HOME/.claude/upskill-store}"
DEBUG_DIR="$UPSKILL_STORE/.building"
FIRST_PROMPT="$DEBUG_DIR/first_prompt.txt"
DEBUG_RAW="$DEBUG_DIR/last_raw_stdin.txt"
TRANSCRIPT_PATH_FILE="$DEBUG_DIR/transcript_path.txt"

# Save raw stdin to debug file (always, so we can see what the hook receives)
mkdir -p "$DEBUG_DIR"
cat > "$DEBUG_RAW"

# Always save transcript_path from hook event (needed by after-session.sh)
python3 -c "
import sys, json
d = open('$DEBUG_RAW').read()
m = json.loads(d) if d.startswith('{') else {}
tp = m.get('transcript_path','')
if tp:
    open('$TRANSCRIPT_PATH_FILE','w').write(tp)
" 2>/dev/null

# Already captured a first prompt this session — skip
[ -f "$FIRST_PROMPT" ] && exit 0

# Parse JSON from saved stdin, extract prompt text (strip leading/trailing whitespace)
PROMPT=$(python3 -c "
import sys, json
d = open('$DEBUG_RAW').read()
m = json.loads(d) if d.startswith('{') else {}
p = m.get('prompt','') or m.get('message','') or m.get('text','') or d
print(p.strip()[:2000])
" 2>/dev/null)

# Skip Upskill commands, slash commands, and trivial inputs
TRIMMED=$(printf "%s" "$PROMPT" | sed 's/^[[:space:]]*//')
case "$TRIMMED" in
    /upskill*)     exit 0 ;;
    /exit*)    exit 0 ;;
    /clear*)   exit 0 ;;
    /compact*) exit 0 ;;
    /help*)    exit 0 ;;
    /doctor*)  exit 0 ;;
    /config*)  exit 0 ;;
    /init*)    exit 0 ;;
    /memory*)  exit 0 ;;
    "")        exit 0 ;;
esac

[ ${#PROMPT} -lt 10 ] && exit 0

mkdir -p "$(dirname "$FIRST_PROMPT")"
printf "%s" "$PROMPT" > "$FIRST_PROMPT"

# ---- Skill Trigger Matching ----
# Check if this prompt matches any installed skill's trigger keywords.
# Behavior depends on UPSKILL_SERVE_MODE:
#   interactive — match silently (results used by /upskill-run), no CC notification
#   auto        — match + output directive to CC context
MATCH_FILE="$DEBUG_DIR/skill_match.txt"
rm -f "$MATCH_FILE"

# Read serve mode from upskill.conf
SERVE_MODE="interactive"
if [ -f "$HOME/.claude/upskill.conf" ]; then
    source "$HOME/.claude/upskill.conf" 2>/dev/null || true
    SERVE_MODE="${UPSKILL_SERVE_MODE:-interactive}"
fi
export UPSKILL_SERVE_MODE="$SERVE_MODE"

python3 -c "
import json, os, re, glob

prompt = open('$FIRST_PROMPT').read()
prompt_lower = prompt.lower()

store = os.path.expanduser('$UPSKILL_STORE')
matches = []

for manifest_path in sorted(glob.glob(os.path.join(store, '*/manifest.yaml'))):
    cat_dir = os.path.dirname(manifest_path)
    cat_name = os.path.basename(cat_dir)
    if cat_name.startswith('.'):
        continue
    with open(manifest_path) as f:
        text = f.read()

    # Parse manifest into entry blocks (split on '- id:')
    entry_blocks = re.split(r'\n  - id:', text)
    for block in entry_blocks[1:]:  # skip preamble before first entry
        block = '  - id:' + block

        skill_id_m = re.search(r'^  - id:\s+(\S+)', block, re.MULTILINE)
        trigger_m = re.search(r'trigger_keywords:\s*\[([^\]]+)\]', block)
        desc_m = re.search(r'description:\s*\"([^\"]*)\"', block)
        base_model_m = re.search(r'base_model:\s+(\S+)', block)

        if not trigger_m or not skill_id_m:
            continue

        keywords = [k.strip() for k in trigger_m.group(1).split(',')]

        # Find which keywords matched
        matched = []
        for kw in keywords:
            if len(kw) < 2:
                continue
            if re.search(r'[一-鿿]', kw):
                if kw.lower() in prompt_lower:
                    matched.append(kw)
            else:
                if re.search(r'\b' + re.escape(kw.lower()) + r'\b', prompt_lower):
                    matched.append(kw)

        if matched:
            skill_id = skill_id_m.group(1)
            base_model = base_model_m.group(1) if base_model_m else 'unknown'
            description = desc_m.group(1) if desc_m else ''

            matches.append({
                'category': cat_name,
                'skill_id': skill_id,
                'base_model': base_model,
                'description': description,
                'matched_keywords': matched,
            })

if matches:
    open('$MATCH_FILE', 'w').write(json.dumps(matches))

    # Notify file always saved (for /upskill-run in interactive mode)
    notify_path = os.path.expanduser('$DEBUG_DIR/skill_notify.txt')
    notify_lines = ['SKILL MATCH — Read BEFORE implementing:']
    for m in matches:
        kws = ', '.join(m['matched_keywords'])
        skill_path = os.path.join(store, m['category'], m['skill_id'])
        skill_md = os.path.join(skill_path, 'SKILL.md')
        notify_lines.append(f'')
        notify_lines.append(f'- {m[\"category\"]}/{m[\"skill_id\"]} (matched: {kws})')
        notify_lines.append(f'  Description: {m.get(\"description\", \"\")}')
        notify_lines.append(f'  Base model: {m.get(\"base_model\", \"unknown\")}')
        if os.path.isfile(skill_md):
            notify_lines.append(f'  SKILL.md: {skill_md}')
    open(notify_path, 'w').write(chr(10).join(notify_lines))

    # Only notify CC in auto mode (interactive mode uses /upskill-run)
    serve_mode = os.environ.get('UPSKILL_SERVE_MODE', 'interactive')
    if serve_mode == 'auto':
        out = []
        out.append('SKILL MATCH — Read these files BEFORE implementing the task:')
        for m in matches:
            kws = ', '.join(m['matched_keywords'])
            desc = m.get('description', '')
            base_model = m.get('base_model', 'unknown')
            skill_path = os.path.join(store, m['category'], m['skill_id'])
            skill_md = os.path.join(skill_path, 'SKILL.md')

            out.append('')
            out.append(f'Build: {m[\"category\"]}/{m[\"skill_id\"]}')
            if desc:
                out.append(f'Why: {desc}')
            out.append(f'Keywords matched: {kws}')
            out.append(f'Validated on: {base_model}')
            if os.path.isfile(skill_md):
                out.append(f'Read: {skill_md}')
        out.append('')
        out.append('ACTION:')
        out.append('1. Tell user about the matched skill(s) above and ask "Apply? [Y/n]"')
        out.append('2. If confirmed and the skill was validated on a different model:')
        out.append('   ask "Switch to <base_model>? [Y/n]"')
        out.append('   If yes: tell user "Run /model and select <base_model>,')
        out.append('   then reply done." DO NOT try to run /model — it is a TUI')
        out.append('   command that Claude cannot invoke. Wait for user to reply.')
        out.append('3. Read the referenced SKILL.md and execute.')
        print(chr(10).join(out), flush=True)
" 2>/dev/null || true

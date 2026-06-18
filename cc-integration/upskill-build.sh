#!/bin/bash
# Upskill worktree-based building pipeline for CC integration.
#
# Flow:
#   Phase 0: Capture task + create git worktree
#   Phase 1: Weak baseline (read from user's failed session)
#   Phase 2: Teacher CC solves task in worktree
#   Phase 3: Teacher CC analyzes failure + generates skill
#   Phase 4: Parse skill from CC output
#   Phase 5: Ralph Loop — student CC re-attempts with skill in worktree
#
# Model config is read from ~/.claude/upskill.conf:
#   UPSKILL_TEACHER — strong model for analysis/skill generation
#   UPSKILL_STUDENT — weak model for Ralph validation (skills target this)
#
# The user's daily model is independent — set in CC settings.json.
# Upskill triggers on any failure regardless of which model was used.
#
# Usage:
#   upskill-build.sh <task-prompt> <failure-log> <category> [--background]

set -euo pipefail

UPSKILL_STORE="${UPSKILL_STORE:-$HOME/.claude/upskill-store}"
RALPH_MAX="${RALPH_MAX:-3}"
CC_TIMEOUT="${CC_TIMEOUT:-600}"

log() { echo "[upskill] $(date +%H:%M:%S) $*" >&2; }

# Load model config
UPSKILL_CONF="$HOME/.claude/upskill.conf"
if [ -f "$UPSKILL_CONF" ]; then
    source "$UPSKILL_CONF"
fi
TEACHER="${UPSKILL_TEACHER:-}"
STUDENT="${UPSKILL_STUDENT:-}"

if [ -z "$TEACHER" ] || [ -z "$STUDENT" ]; then
    log "WARNING: UPSKILL_TEACHER or UPSKILL_STUDENT not set in ~/.claude/upskill.conf"
    log "Building will use CC's current model for all phases — results may be inconsistent."
fi

# Safely build a prompt by substituting user content into a template.
# Uses python3 to avoid bash interpreting backticks, $(), or quotes in user data.
# Template placeholders: __TASK_PROMPT__  __TRAJECTORY__  __STUDENT_NAME__
_build_prompt() {
    local template="$1" task_prompt="$2" trajectory="$3" student_name="$4" out_file="$5"
    python3 -c "
import sys
tpl = sys.argv[1]; task = sys.argv[2]; traj = sys.argv[3]; student = sys.argv[4]
result = tpl.replace('__TASK_PROMPT__', task)
result = result.replace('__TRAJECTORY__', traj)
result = result.replace('__STUDENT_NAME__', student)
with open(sys.argv[5], 'w') as f:
    f.write(result)
" "$template" "$task_prompt" "$trajectory" "$student_name" "$out_file"
}

# Run CC with a specific model.
# Uses python3 subprocess to invoke claude, so user content (backticks, $(), etc.)
# in the prompt is never interpreted by bash.
run_cc() {
    local label="$1" model="$2" prompt="$3" workdir="$4" out_file="$5"
    log "$label: running with $model (timeout=${CC_TIMEOUT}s)..."

    # Write prompt to temp file so python3 can read it without bash interpolation
    local prompt_file
    prompt_file=$(mktemp /tmp/upskill-prompt-XXXXXX)
    printf '%s' "$prompt" > "$prompt_file"

    python3 -c "
import subprocess, os, sys
os.chdir('$workdir')
env = os.environ.copy()
if '$model':
    env['ANTHROPIC_MODEL'] = '$model'
with open('$prompt_file') as f:
    prompt_text = f.read()
result = subprocess.run(
    ['claude', '--permission-mode', 'bypassPermissions', '-p', prompt_text],
    env=env,
    capture_output=True, text=True,
    timeout=int(os.environ.get('CC_TIMEOUT', '600'))
)
sys.stdout.write(result.stdout)
sys.stderr.write(result.stderr)
sys.exit(result.returncode)
" 2>&1 | tee "$out_file" || true
    rm -f "$prompt_file"
    log "$label: output -> $out_file ($(wc -c < "$out_file") bytes)"
}

# ---- args ----
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    cat << 'HELP'
Usage: upskill-build.sh <task-prompt> <failure-log> <category> [--background]

Run the Upskill pipeline to analyze a failure and generate a skill.

Arguments:
  task-prompt    The original task description
  failure-log    Path to the failed session transcript
  category       skill category (e.g. data-analysis, software-engineering)

Options:
  --background   Run in background mode (suppress some output)

Config:
  Reads ~/.claude/upskill.conf for UPSKILL_TEACHER and UPSKILL_STUDENT.

Phases:
  0. Setup: create git worktree
  1. Load failure trajectory from log
  2. Teacher model solves the task
  3. Teacher analyzes failure + generates skill
  4. Parse skill from CC output
  5. Ralph validation: student model retries with skill (up to 3 attempts)
HELP
    exit 0
fi

TASK_PROMPT="${1:?Usage: $0 <task-prompt> <failure-log> <category> [--background]}"
FAILURE_LOG="${2:?}"
CATEGORY="${3:?}"
BACKGROUND="${4:-}"

SKILL_ID="skill_$(date +%Y%m%d_%H%M%S)"
BUILD_DIR="$UPSKILL_STORE/.building/$SKILL_ID"
WORKTREE_DIR=""
ORIG_DIR=$(pwd)

cleanup() {
    if [ -n "${WORKTREE_DIR:-}" ] && [ -d "$WORKTREE_DIR" ]; then
        log "Cleaning up worktree: $WORKTREE_DIR"
        cd "$ORIG_DIR" 2>/dev/null || true
        git worktree remove --force "$WORKTREE_DIR" 2>/dev/null || true
        rm -rf "$WORKTREE_DIR" 2>/dev/null || true
    fi
    # Keep BUILD_DIR — contains phase logs for debugging.
    # Old skill dirs are cleaned by upskill-store.sh status or manual GC.
}
trap cleanup EXIT

# ---- Phase 0: Setup ----
log "== Phase 0: Setup (skill_id=$SKILL_ID) =="
log "Teacher: ${TEACHER:-default CC model}"
log "Student: ${STUDENT:-default CC model}"
mkdir -p "$BUILD_DIR" "$UPSKILL_STORE"

# Create worktree
WORKTREE_DIR=$(mktemp -d /tmp/upskill-worktree-XXXXXX)
log "Creating worktree at $WORKTREE_DIR"
if git rev-parse --git-dir >/dev/null 2>&1; then
    git worktree add --detach "$WORKTREE_DIR" HEAD 2>&1 | sed 's/^/  [git] /'
    # Copy modified tracked files (not in HEAD but needed to reproduce the failure)
    git diff --name-only HEAD 2>/dev/null | while IFS= read -r f; do
        [ -z "$f" ] && continue
        [ -f "$f" ] || continue
        dir=$(dirname "$WORKTREE_DIR/$f")
        mkdir -p "$dir"
        cp "$f" "$WORKTREE_DIR/$f" 2>/dev/null || true
    done
    # Copy untracked files
    git ls-files --others --exclude-standard -z 2>/dev/null | while IFS= read -r -d '' f; do
        dir=$(dirname "$WORKTREE_DIR/$f")
        mkdir -p "$dir"
        cp "$f" "$WORKTREE_DIR/$f" 2>/dev/null || true
    done
else
    # Non-git: copy with exclusions for large dirs
    rsync -a --exclude='node_modules' --exclude='.venv' --exclude='venv' \
        --exclude='.git' --exclude='build' --exclude='dist' --exclude='__pycache__' \
        --exclude='*.pyc' . "$WORKTREE_DIR/" 2>/dev/null || cp -r . "$WORKTREE_DIR"
fi
mkdir -p "$WORKTREE_DIR/.claude"

# ---- Phase 1: Weak baseline (from failure log) ----
log "== Phase 1: Weak baseline =="
if [ ! -f "$FAILURE_LOG" ]; then
    log "ERROR: failure log not found: $FAILURE_LOG"
    exit 1
fi
WEAK_TRAJECTORY=$(tail -n 500 "$FAILURE_LOG" 2>/dev/null || echo "(no trajectory)")
log "Loaded weak trajectory (${#WEAK_TRAJECTORY} chars)"

# ---- Phase 2: Teacher solves task ----
log "== Phase 2: Teacher solve =="
run_cc "phase2-teacher" "$TEACHER" "$TASK_PROMPT" \
    "$WORKTREE_DIR" "$BUILD_DIR/phase2_teacher_solve.log"

# ---- Phase 3: Generate skill ----
log "== Phase 3: skill generation =="

STUDENT_NAME="${STUDENT:-the weaker model}"

GENERATE_PROMPT="CRITICAL: You are running in non-interactive mode (-p). You CANNOT ask for approval.
	You MUST output the COMPLETE file contents inline using the markers below.
	DO NOT summarize. DO NOT ask permission. DO NOT describe what you would write.
	OUTPUT THE ACTUAL FILE NOW.

	You are acting as a TEACHER agent in the Upskill framework.
Your student is __STUDENT_NAME__.

## Task Description
__TASK_PROMPT__

## Student Failure Trajectory
__TRAJECTORY__

## Your Job
Analyze WHY the student failed, then output a COMPLETE skill as a single SKILL.md file
that will help the student succeed on this exact same task.

### Student-Aware Synthesis
The student is __STUDENT_NAME__. ALL instructions must:
- Use short, concrete sentences with explicit command examples
- Break complex reasoning into numbered checklists
- NEVER assume the student can infer missing steps
- Use imperative form: \"Run X\", \"Check Y\", \"Verify Z\"
- Avoid abstractions — give copy-paste-ready commands

### SKILL.md Structure

Output ONE file with YAML frontmatter and three markdown sections:

**Frontmatter** (between --- delimiters):
- name: <skill_id>
- description: One paragraph describing what this skill teaches and when to apply
- metadata.category: <category>
- metadata.base_model: <model name>
- metadata.created: <ISO timestamp>
- metadata.trigger_keywords: [kw1, kw2, ...] — keywords for task matching

**# Domain Knowledge section** (replaces CLAUDE.md):
- Common Pitfalls with specific mistakes to avoid
- Correct Approach with step-by-step workflow
- Key command patterns with correct syntax
- Verification checklist

**# Step-by-Step section** (replaces solve-task skill):
- Ordered checklist of concrete actions
- Warning about the specific error from the failure trajectory
- The correct approach in imperative form

**# Feedback / Lessons section** (replaces persisted memory):
Format each rule as:
Rule: <the rule>
Why: <why it matters>
How to apply: <how to follow it>

### Output Format (MANDATORY — no text allowed before first marker or after last marker)

===BEGIN_FILE: SKILL.md===
---
name: <skill_id>
description: ...
metadata:
  category: ...
  base_model: ...
  created: ...
  trigger_keywords: [...]
---

# Domain Knowledge
...
# Step-by-Step
...
# Feedback / Lessons
Rule: ...
Why: ...
How to apply: ...
===END_FILE: SKILL.md===

===SKILL_DESCRIPTION===
(One-paragraph description of what this skill teaches and when to apply it.
Include: what kind of task, what patterns/anti-patterns, what language/domain.
Example: \"For Python CLI data-processing tools: CSV/TSV parsing with argparse,
filter/sort by column, and str-vs-float comparison bugs. Apply to any task that
reads structured text files and filters/sorts rows by column values.\")
===SKILL_DESCRIPTION===

After the file, output: ===BUILD_RESULT: CONFIGS_GENERATED==="

_build_prompt "$GENERATE_PROMPT" "$TASK_PROMPT" "$WEAK_TRAJECTORY" "$STUDENT_NAME" "$BUILD_DIR/generate_prompt.txt"
run_cc "phase3-generate" "$TEACHER" "$(cat "$BUILD_DIR/generate_prompt.txt")" \
    "$BUILD_DIR" "$BUILD_DIR/phase3_generated_configs.log"

# ---- Phase 4: Parse skill ----
log "== Phase 4: Parse skill =="
SKILL_OUT="$BUILD_DIR/skill_output"
mkdir -p "$SKILL_OUT"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Retry loop: if teacher model summarized instead of outputting markers,
# regenerate with an increasingly direct prompt (up to 2 retries).
PARSE_RETRY=0
PARSE_MAX_RETRIES=2
while true; do
    python3 "$SCRIPT_DIR/parse-skill.py" \
        "$BUILD_DIR/phase3_generated_configs.log" \
        "$SKILL_OUT" \
        --task-name "$SKILL_ID"

    # Verify at least SKILL.md was extracted
    if [ -f "$SKILL_OUT/SKILL.md" ]; then
        log "skill SKILL.md parsed successfully ($(find "$SKILL_OUT" -type f | wc -l | tr -d ' ') files)"
        break
    fi

    PARSE_RETRY=$((PARSE_RETRY + 1))
    if [ "$PARSE_RETRY" -gt "$PARSE_MAX_RETRIES" ]; then
        log "FATAL: parse-skill.py found no marked files after $PARSE_MAX_RETRIES retries."
        log "Teacher model did not output BEGIN_FILE/END_FILE markers."
        log "See: $BUILD_DIR/phase3_generated_configs.log"
        echo "FAIL (no skill markers)" > "$BUILD_DIR/final_result.txt"
        exit 2
    fi

    log "skill parse found no files — regenerating (retry $PARSE_RETRY/$PARSE_MAX_RETRIES)..."

    RETRY_PROMPT="YOU DID NOT OUTPUT THE REQUIRED MARKERS. READ THIS CAREFULLY.

You previously responded with a summary or description instead of the actual files.
That is WRONG. You are running in non-interactive mode. You MUST output the
COMPLETE file contents inline.

This is your LAST CHANCE. Output ONLY the markers and file contents — nothing else.

## Files to Output

===BEGIN_FILE: SKILL.md===
(write the complete SKILL.md content with YAML frontmatter and three sections)
===END_FILE: SKILL.md===

===SKILL_DESCRIPTION===
(One-paragraph description of what this skill teaches and when to apply it.)
===SKILL_DESCRIPTION===

After ALL three files, output: ===BUILD_RESULT: CONFIGS_GENERATED==="

    run_cc "phase3-retry-$PARSE_RETRY" "$TEACHER" "$RETRY_PROMPT" \
        "$BUILD_DIR" "$BUILD_DIR/phase3_generated_configs.log"
done

# ---- Phase 5: Ralph Loop ----
log "== Phase 5: Ralph Validation =="

for r in $(seq 1 $RALPH_MAX); do
    log "Ralph attempt $r / $RALPH_MAX"

    # Create fresh worktree
    RALPH_WT="/tmp/upskill-ralph-${SKILL_ID}-${r}"
    if git rev-parse --git-dir >/dev/null 2>&1; then
        git worktree add --detach "$RALPH_WT" HEAD 2>&1 | sed 's/^/  [git] /'
        git diff --name-only HEAD 2>/dev/null | while IFS= read -r f; do
            [ -z "$f" ] && continue
            [ -f "$f" ] || continue
            dir=$(dirname "$RALPH_WT/$f")
            mkdir -p "$dir"
            cp "$f" "$RALPH_WT/$f" 2>/dev/null || true
        done
        git ls-files --others --exclude-standard -z 2>/dev/null | while IFS= read -r -d '' f; do
            dir=$(dirname "$RALPH_WT/$f")
            mkdir -p "$dir"
            cp "$f" "$RALPH_WT/$f" 2>/dev/null || true
        done
    else
        rsync -a --exclude='node_modules' --exclude='.venv' --exclude='venv' \
            --exclude='.git' --exclude='build' --exclude='dist' --exclude='__pycache__' \
            --exclude='*.pyc' . "$RALPH_WT/" 2>/dev/null || cp -r . "$RALPH_WT"
    fi
    mkdir -p "$RALPH_WT/.claude/skills"

    # Deploy skill: extract sections from SKILL.md to appropriate locations
    if [ -f "$SKILL_OUT/SKILL.md" ]; then
        # Extract Domain Knowledge section -> append to worktree CLAUDE.md
        printf "\n---\n## Upskill Skill (%s)\n" "$SKILL_ID" >> "$RALPH_WT/CLAUDE.md"
        python3 -c "
import sys, re
with open('$SKILL_OUT/SKILL.md') as f:
    c = f.read()
m = re.search(r'# Domain Knowledge\n(.*?)(?=\n# Step-by-Step)', c, re.DOTALL)
if m and m.group(1).strip():
    sys.stdout.write(m.group(1).strip() + '\n')
else:
    import sys
    print('[upskill] WARNING: no Domain Knowledge content in SKILL.md', file=sys.stderr)
" >> "$RALPH_WT/CLAUDE.md"

        # Extract Step-by-Step section -> save as skill
        mkdir -p "$RALPH_WT/.claude/skills/solve-task"
        python3 -c "
import sys, re, os
with open('$SKILL_OUT/SKILL.md') as f:
    c = f.read()
m = re.search(r'# Step-by-Step\n(.*?)(?=\n# Feedback / Lessons|\Z)', c, re.DOTALL)
if m and m.group(1).strip():
    body = '# solve-task\n\n' + m.group(1).strip() + '\n'
    with open('$RALPH_WT/.claude/skills/solve-task/SKILL.md', 'w') as f:
        f.write(body)
else:
    import sys
    print('[upskill] WARNING: no Step-by-Step content in SKILL.md — solve-task skill will be empty', file=sys.stderr)
"

        # Extract Feedback / Lessons section -> save as memory
        PROJECT_SLUG=$(echo -n "$RALPH_WT" | sed 's|/|-|g')
        MEM_DIR="$HOME/.claude/projects/${PROJECT_SLUG}/memory"
        mkdir -p "$MEM_DIR"
        python3 -c "
import sys, re
with open('$SKILL_OUT/SKILL.md') as f:
    c = f.read()
m = re.search(r'# Feedback / Lessons\n(.*?)(\Z)', c, re.DOTALL)
if m and m.group(1).strip():
    mem = m.group(1).strip()
    full = '---\nname: feedback-lessons\ndescription: Feedback lessons\nmetadata:\n  type: feedback\n---\n\n' + mem + '\n'
    with open('$MEM_DIR/feedback_lessons.md', 'w') as f:
        f.write(full)
"
    fi

    # Run student CC with skill
    RALPH_PROMPT="__TASK_PROMPT__

---

Before you start, read CLAUDE.md for pitfalls and patterns,
then run /solve-task for step-by-step guidance.

IMPORTANT: At the end of your response, output a verification line:
===BUILD_RESULT: PASS=== if you successfully completed the task.
===BUILD_RESULT: FAIL=== if you could not complete the task."

    _build_prompt "$RALPH_PROMPT" "$TASK_PROMPT" "" "$STUDENT_NAME" "$RALPH_WT/.ralph_build_prompt.md"
    run_cc "phase5-ralph-$r" "$STUDENT" "$(cat "$RALPH_WT/.ralph_build_prompt.md")" \
        "$RALPH_WT" "$BUILD_DIR/phase5_ralph_${r}.log"

    # Check result
    if grep -q "BUILD_RESULT: PASS" "$BUILD_DIR/phase5_ralph_${r}.log" 2>/dev/null; then
        log "=== RALPH VALIDATED (attempt $r) ==="

        # Store skill as single SKILL.md
        STORE_DIR="$UPSKILL_STORE/$CATEGORY/$SKILL_ID"
        mkdir -p "$STORE_DIR"

        # Patch SKILL.md frontmatter with actual metadata before storing
        BASE_MODEL="${STUDENT:-unknown}"
        python3 -c "
import re, sys
ts = '$(date +%Y-%m-%dT%H:%M:%S)'
cat = '$CATEGORY'
model = '$BASE_MODEL'
skill_id = '$SKILL_ID'

with open('$SKILL_OUT/SKILL.md') as f:
    content = f.read()

# Patch base_model in frontmatter block
content = re.sub(r'base_model:\s*.*', f'base_model: {model}', content)
# Patch category
content = re.sub(r'category:\s*.*', f'category: {cat}', content)
# Patch created timestamp
content = re.sub(r'created:\s*.*', f'created: {ts}', content)
# Ensure name matches skill_id
content = re.sub(r'^name:\s*.*', f'name: {skill_id}', content, flags=re.MULTILINE)

with open('$SKILL_OUT/SKILL.md', 'w') as f:
    f.write(content)
print(f'  [store] patched SKILL.md: base_model={model}, category={cat}')
"

        cp "$SKILL_OUT/SKILL.md" "$STORE_DIR/" 2>/dev/null || true
        cp "$SKILL_OUT/description.txt" "$STORE_DIR/" 2>/dev/null || true

        # Update manifest
        bash "$SCRIPT_DIR/upskill-store.sh" add \
            --category "$CATEGORY" \
            --skill-id "$SKILL_ID" \
            --prompt "$TASK_PROMPT" \
            --base-model "$BASE_MODEL" \
            --store "$UPSKILL_STORE" \
            --skill-dir "$SKILL_OUT"

        # Sync to global ~/.claude/
        bash "$SCRIPT_DIR/upskill-store.sh" sync

        # Cleanup
        cd "$ORIG_DIR" 2>/dev/null || true
        git worktree remove --force "$RALPH_WT" 2>/dev/null || true
        rm -rf "$RALPH_WT" 2>/dev/null || true

        echo "PASS" > "$BUILD_DIR/final_result.txt"
        log "skill stored in $STORE_DIR"
        exit 0
    fi

    log "Ralph attempt $r: FAIL"

    # Revise skill
    log "Revising skill with teacher..."
    LATEST_FAILURE=$(tail -n 300 "$BUILD_DIR/phase5_ralph_${r}.log" 2>/dev/null || echo "(no trajectory)")

    REVISE_PROMPT="The student (__STUDENT_NAME__) STILL FAILED despite your previous config package.
Latest failure trajectory:

__TRAJECTORY__

Analyze what went wrong and REVISE the SKILL.md file. Make instructions MORE explicit:
1. Did the student follow instructions? If not, make them more explicit.
2. Was any step still too abstract? Break it down further.
3. Was there a NEW error? Add a rule for it.

Output complete revised SKILL.md using the same marker:
===BEGIN_FILE: SKILL.md===
...
===END_FILE: SKILL.md===

At the end, output: ===BUILD_RESULT: CONFIGS_GENERATED==="

    REVISE_FILE="$BUILD_DIR/phase5_revise_prompt_${r}.txt"
    _build_prompt "$REVISE_PROMPT" "$TASK_PROMPT" "$LATEST_FAILURE" "$STUDENT_NAME" "$REVISE_FILE"
    run_cc "phase5-revise-$r" "$TEACHER" "$(cat "$REVISE_FILE")" \
        "$BUILD_DIR" "$BUILD_DIR/phase5_revised_${r}.log"

    python3 "$SCRIPT_DIR/parse-skill.py" \
        "$BUILD_DIR/phase5_revised_${r}.log" \
        "$SKILL_OUT" \
        --task-name "${SKILL_ID}_r${r}"

    cd "$ORIG_DIR" 2>/dev/null || true
    git worktree remove --force "$RALPH_WT" 2>/dev/null || true
    rm -rf "$RALPH_WT" 2>/dev/null || true
done

log "=== Ralph Loop exhausted ($RALPH_MAX attempts). skill not certified. ==="
echo "FAIL" > "$BUILD_DIR/final_result.txt"
exit 1

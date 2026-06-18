# /upskill-run

Interactive Upskill workflow. Available only when `UPSKILL_SERVE_MODE=interactive`.

## Usage
`/upskill-run`

## Flow

### Step 1: Collect the task
If the user already included a task description after `/upskill-run`, use it.
Otherwise ask: "What task would you like to work on?"

### Step 2: Scan skills and match
Run both commands in parallel:

```bash
# List all installed skills
bash ~/.claude/hooks/upskill-store.sh list

# Find keyword matches from the hook (if any)
cat ~/.claude/upskill-store/.building/skill_match.txt 2>/dev/null || echo "[]"
```

If `skill_match.txt` exists and contains matches, those skills get ★ marks.

If no match file exists, do the matching yourself: compare the task against
each Upskill's description and trigger keywords.

### Step 3: Present skills
Format as a numbered list. Check each Upskill's base_model against the current
model (`echo $ANTHROPIC_MODEL` or check what model you are running on).

```
Here are the available skills:

  ★ 1. software-engineering/skill_xxx  [推荐]
     Python CLI data-processing tools — filter/sort/select
     Validated on: deepseek-v4-flash  (current: deepseek-v4-pro ✗)

    2. system-administration/skill_yyy
     cron debugging and network troubleshooting
     Validated on: deepseek-v4-flash  (current: deepseek-v4-flash ✓)

★ = matched your task. (✓ = model matches, ✗ = model differs)
Enter number(s) to apply (comma-separated), or "none" to skip.
```

### Step 4: Get selection and handle model switch
Wait for user input. Parse comma-separated numbers.
- "none" or empty → skip all skills, execute task directly
- "1" or "1,3" → apply selected skills

For each selected Upskill where the validated model differs from the current model:

```
Upskill "skill_xxx" was validated on deepseek-v4-flash.
You are currently on deepseek-v4-pro.
Switch to deepseek-v4-flash for this task? [Y/n]
```

If user confirms: **do NOT try to run /model yourself** (it's a TUI command
that Claude cannot invoke). Instead, pause and tell the user:

```
Please run /model and select deepseek-v4-flash, then reply "done" to continue.
```

Wait for the user to reply before proceeding to Step 5.
If the current model already matches the Upskill, skip the question.

### Step 5: Load and execute
For each selected Upskill, read the single SKILL.md file which contains
Domain Knowledge, a Step-by-Step checklist, and Feedback/Lessons:

```bash
cat ~/.claude/upskill-store/<category>/<skill_id>/SKILL.md
```

If SKILL.md does not exist (old format), fall back to:
```bash
cat ~/.claude/upskill-store/<category>/<skill_id>/CLAUDE.md
cat ~/.claude/upskill-store/<category>/<skill_id>/.claude/skills/solve-task/SKILL.md 2>/dev/null
```

Then execute the original task with the Upskill guidance applied.

## Notes
- `skill_match.txt` is written by the `UserPromptSubmit` hook. It may not exist
  if `/upskill-run` is the first thing typed this session — do matching yourself.
- `upskill-store.sh list` outputs the full Upskill catalog with descriptions and models.
- `/model` is a TUI command only the user can run. Claude cannot invoke it.
  Always pause and wait for the user to switch models before continuing.

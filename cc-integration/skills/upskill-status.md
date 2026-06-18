# /upskill-status

Check the status of Upskill — active building jobs and Upskill library stats.

## Usage
`/upskill-status`

## What it does
1. Shows counts of skills per category
2. Shows any active/recent building jobs and their progress
3. Shows the latest skill result (PASS/FAIL) if available

## Implementation
Run `bash ~/.claude/hooks/upskill-store.sh status`.

Global Skills: `~/.claude/upskill-store/CLAUDE.md` (loaded by CC in all projects).
Global skills: `~/.claude/skills/upskill-*/SKILL.md`.
Skill content (including feedback/lessons) is loaded via `/upskill-run`.

If a skill is currently running:
- Show the PID and how long it's been running
- Show the last few lines of the skill log: `tail -5 ~/.claude/upskill-store/.building/<skill_id>/phase5_ralph_1.log`
- If skill completed, show the final result: `cat ~/.claude/upskill-store/.building/<skill_id>/final_result.txt`

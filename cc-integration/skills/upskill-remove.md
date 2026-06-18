# /upskill-remove

Remove an Upskill from your Upskill library.

## Usage
`/upskill-remove [--category <name>] [--skill-id <id>]`

If run without arguments, lists all skills and asks which to remove.

## What it does
1. If no arguments: shows all skills via `upskill-store.sh list`, asks user to select
2. Removes the specified Upskill from `~/.claude/upskill-store/<category>/`
3. Cleans up global skills (`~/.claude/skills/upskill-*.md`)
4. Rebuilds the global Upskill index (`~/.claude/upskill-store/CLAUDE.md`)

## Implementation

### If called with arguments:
```bash
bash ~/.claude/hooks/upskill-store.sh remove --category <category> --skill-id <id>
```
Then confirm the result by checking the exit code.

### If called without arguments:
1. Run `bash ~/.claude/hooks/upskill-store.sh list` and display the output
2. Ask: "Which Upskill do you want to remove? Specify category and skill-id."
3. Once the user specifies, run:
```bash
bash ~/.claude/hooks/upskill-store.sh remove --category <category> --skill-id <id>
```
4. Confirm: "Upskill <id> removed from [<category>]. Global index rebuilt."

### To remove an entire category:
```bash
bash ~/.claude/hooks/upskill-store.sh remove --category <category>
```
This removes ALL Skills in that category. Ask for confirmation first.

# /upskill-list

List all Skills in the user's personal Upskill library.

## Usage
`/upskill-list [category]`

## What it does
1. Reads `~/.claude/upskill-store/<category>/manifest.yaml` for each category
2. Displays each Upskill with its category, base model, trigger keywords, and file list
3. If a category is specified, shows only that category

## Implementation
Run `bash ~/.claude/hooks/upskill-store.sh list` and display the results.
Optionally filter: `bash ~/.claude/hooks/upskill-store.sh list | grep <category>`.

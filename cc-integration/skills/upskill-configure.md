# /upskill-configure

Enable Upskill hooks and Upskill serving in the current project.

## Usage
`/upskill-configure`

## What it does
Configures the current project's `.claude/settings.local.json` with:
- `claudeMd` → loads the global Upskill index in this project
- `before_session` hook → checks for pending skill notifications
- `after_session` hook → detects failures and saves session context

After running, restart Claude Code in this project for hooks to take effect.

## Implementation
```bash
bash ~/.claude/hooks/configure-project.sh
```

# /upskill-mode

View or switch the Upskill serve mode.

## Usage
`/upskill-mode`                  → show current mode
`/upskill-mode interactive`      → switch to interactive mode (default)
`/upskill-mode auto`             → switch to auto mode

## What it does

### Show current mode
Read `~/.claude/upskill.conf` and display the current `UPSKILL_SERVE_MODE`.

- **interactive** (default): Use `/upskill-run` to start. Shows ALL skills with
  matched ones starred as recommendations. You pick which to apply.
  If validated model differs, prompts you to manually `/model` switch first.
- **auto**: Automatic keyword matching on every prompt. Matched Skills are
  suggested before execution. You confirm whether to apply.
  If validated model differs, prompts you to manually `/model` switch first.

### Switch mode
Update `UPSKILL_SERVE_MODE` in `~/.claude/upskill.conf` and rebuild the
global Upskill index so all Upskill entries reflect the new mode.

## Implementation

### If called with `interactive` or `auto`:
```bash
sed 's/^UPSKILL_SERVE_MODE=.*/UPSKILL_SERVE_MODE="<mode>"/' ~/.claude/upskill.conf > /tmp/upskill-mode-tmp.conf
mv /tmp/upskill-mode-tmp.conf ~/.claude/upskill.conf
bash ~/.claude/hooks/upskill-store.sh sync
```
Then print: "Serve mode switched to <mode>. Global Upskill index rebuilt."

### If called without arguments:
```bash
grep '^UPSKILL_SERVE_MODE=' ~/.claude/upskill.conf
```
Then explain what the current mode means.

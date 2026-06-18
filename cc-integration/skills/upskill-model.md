# /upskill-model

View current model presets or get the command to switch models.

## Usage
`/upskill-model`                  → show current teacher/student presets
`/upskill-model teacher`          → print export command for teacher model
`/upskill-model student`          → print export command for student model

## What it does

### Show current presets (no arguments)
Read `~/.claude/upskill.conf` and display:
- Teacher model (strong, for Upskill generation)
- Student model (weak, for validation + Upskill target)
- Current session model (`$ANTHROPIC_MODEL`)

### Switch model
Print the export command to switch. The user must restart Claude Code for the change to take effect.

For example:
```
To switch to teacher model, run:
  export ANTHROPIC_MODEL=deepseek-v4-pro[1m]
  claude
```

## Implementation

### Show presets
```bash
echo "=== Upskill Model Presets ==="
echo ""
grep 'TEACHER\|STUDENT' ~/.claude/upskill.conf
echo ""
echo "Current session model: $ANTHROPIC_MODEL"
```

### Switch command
Read the model name from `~/.claude/upskill.conf` and print:
```
export ANTHROPIC_MODEL=<model>
claude
```

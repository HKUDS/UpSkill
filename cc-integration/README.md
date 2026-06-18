# Upskill — Agent Harness Integration

Upskill is a knowledge distillation system for AI agent harnesses. When your agent fails a task, Upskill automatically captures the failure context. A stronger **Teacher** model analyzes the failure, generates a **skill**, and validates it against a weaker **Student** model in a closed loop. Validated skills are stored in your private library and automatically loaded in future sessions — making your preferred model better over time.

This directory (`cc-integration/`) contains the **Claude Code implementation** — the reference integration of Upskill for Anthropic's Claude Code. The same methodology works with any agent harness that supports session hooks and skill files.

[中文文档](README_CN.md)

---

## Table of Contents

- [Core Concepts](#core-concepts)
- [Architecture Overview](#architecture-overview)
- [Quick Start](#quick-start)
- [Daily Usage Flow](#daily-usage-flow)
- [The Building Pipeline](#the-building-pipeline)
- [Skill Serving](#skill-serving)
- [Management Commands](#management-commands)
- [Configuration](#configuration)
- [Serve Mode](#serve-mode)
- [File Structure](#file-structure)

---

## Core Concepts

### The Three Roles

| Role | Config Location | Purpose |
|------|----------------|---------|
| **Daily model** | CC `settings.json` | Whatever you use day-to-day. Completely independent. |
| **Teacher** | `upskill.conf` | Strong model — analyzes failures and generates skills. |
| **Student** | `upskill.conf` | Weak model — the validation target. Skills are optimized *for it*. |

### What is a Skill?

A building run produces a skill package with three delivery channels:

| Channel | Load Timing | Content |
|---------|------------|---------|
| **CLAUDE.md** | Auto-loaded on agent startup (global) | Short summary + skill pointer (~5 lines per skill) |
| **Skill file** | Loaded on-demand when agent invokes it | Full failure analysis + step-by-step guidance |
| **Memory** | Synced every session, auto-loaded | Concise feedback rule (1–2 lines each) |

### Design Rationale

- **CLAUDE.md is lightweight and always present**: Every skill summary stays in context, but each takes ~5 lines. 20 skills ≈ 600 tokens — won't bloat the context window.
- **Skill files are on-demand**: Full content only consumes context when the agent explicitly invokes the skill.
- **Memory is automatic**: Experience rules are injected automatically — no manual trigger needed.

---

## Architecture Overview

```
~/.claude/
├── upskill.conf              # Teacher/Student models + Serve Mode
├── upskill-store/            # Persistent skill storage
│   ├── CLAUDE.md               # Global skill index (claudeMd points here)
│   ├── <category>/
│   │   ├── manifest.yaml       # Entry index (trigger_keywords, base_model)
│   │   ├── CLAUDE.md           # Full skill content for this category
│   │   ├── .claude/skills/
│   │   └── memory/
│   └── .building/               # In-progress build temp files
├── hooks/                      # Hook scripts
│   ├── before-session.sh       # Runs at session start
│   ├── after-session.sh        # Runs at session end
│   ├── save-session.sh         # On-demand session save (/upskill-build)
│   ├── upskill-build.sh        # Building pipeline (core)
│   ├── inject-skill.sh         # Memory sync
│   ├── upskill-store.sh        # Skill library management CLI
│   └── parse-skill.py          # Parse agent output to extract skill files
├── skills/                     # Management commands (Slash Commands)
│   ├── upskill-init.md         # /upskill-init
│   ├── upskill-list.md         # /upskill-list
│   ├── upskill-build.md        # /upskill-build
│   ├── upskill-status.md       # /upskill-status
│   ├── upskill-remove.md       # /upskill-remove
│   ├── upskill-mode.md         # /upskill-mode
│   ├── upskill-model.md        # /upskill-model
│   ├── upskill-run.md          # /upskill-run
│   ├── upskill-configure.md    # /upskill-configure
│   └── upskill-uninstall.md    # /upskill-uninstall
├── settings.local.json         # Agent harness config (hooks + claudeMd)
└── projects/<slug>/memory/     # Project memory (skill memories injected here)
```

### Data Flow

```
Session fails
    │
    ▼
after-session hook → saves prompt + session log → sets pending flag
    │
    ▼
User runs /upskill-build (or sees notification and confirms)
    │
    ▼
upskill-build.sh
    ├─ Phase 0: Create git worktree (isolated environment)
    ├─ Phase 1: Load failure trajectory
    ├─ Phase 2: Teacher solves the task
    ├─ Phase 3: Teacher analyzes failure → generates skill
    ├─ Phase 4: Parse skill files
    └─ Phase 5: Ralph validation (Student + skill retry, up to 3 rounds)
         │
         ├─ PASS → stored in upskill-store/<category>/
         │         → upskill-store.sh sync → update global index + skills
         │
         └─ FAIL → discarded
```

---

## Quick Start

### Remote Install (one command)

```bash
curl -sSL https://raw.githubusercontent.com/HKUDS/Upskill/main/cc-integration/install.sh | bash -s -- --remote
```

The installer sets up everything automatically. To update Upskill to the latest version later, run `/upskill-init`.

### Local Install

```bash
cd cc-integration && bash install.sh
```

### Enable Building for a Project

In each project where you want building enabled, run:

```bash
/upskill-configure
```

This configures the project's hooks (claudeMd, before_session, after_session) so Upskill can capture failures and inject skills automatically.

### Uninstall

Run `/upskill-uninstall` or from the source directory:

```bash
cd cc-integration && bash install.sh --uninstall
```

---

## Daily Usage Flow

### Normal Use (Completely Transparent)

Use your agent as normal, with any model. Each session:

```
Session starts
    │
    ▼
before-session hook
    ├─ Sync global skill index to current project
    └─ Check pending flag → notify user if /upskill-build is available
    │
    ▼
Agent loads context:
    ├─ Project CLAUDE.md
    ├─ ~/.claude/upskill-store/CLAUDE.md (global skill index, always loaded)
    ├─ ~/.claude/skills/ (global skills, loaded on demand)
    └─ ~/.claude/projects/<slug>/memory/ (skill memories)
    │
    ▼
Agent executes tasks normally ...
    │
    ▼
Session ends
    │
    ▼
after-session hook (always runs)
    ├─ Detects failure (exit code ≠ 0 or agent self-reports failure)
    ├─ Saves prompt.txt + session.log
    ├─ Failure → sets pending flag + prints hint
    └─ Success → saves context only (available for manual /upskill-build)
```

### How the Agent Uses Skills

The agent sees the global CLAUDE.md in its context, containing all skill summaries:

```markdown
## Skill: data-analysis (3 skills)
**Base model:** deepseek-v4-flash
**Trigger:** csv, encoding, json, database, query
**Model:** Validated on `deepseek-v4-flash`. For best results, use this model.

  - `skill_20260605_001` — For Python CSV data-processing tools with filter/sort
    → Read `~/.claude/upskill-store/data-analysis/skill_20260605_001/SKILL.md`
  - `skill_20260605_002` — Database query optimization with proper index usage
    → Read `~/.claude/upskill-store/data-analysis/skill_20260605_002/SKILL.md`
```

- **interactive mode (default)**: Use `/upskill-run` to trigger matching — the agent displays all skills for selection.
- **auto mode**: The agent scans for keyword-matched skills on every prompt and proactively suggests them.

---

## The Building Pipeline

### Trigger Conditions

| Method | Trigger |
|--------|---------|
| **Auto-prompt** | Session ends with non-zero exit code → agent prompts `/upskill-build` next session |
| **Manual** | Run `/upskill-build` at any time |

### When Building Triggers vs. When It Doesn't

| Scenario | Triggers? | Notes |
|----------|:--:|--------|
| `verify.sh` exists at project root, agent command fails | Yes | Task-oriented scenarios |
| No `verify.sh` at project root | No | Non-task scenario, stays out of the way |
| Same task already skilled | No | Deduplication via skill tags |
| Daily limit exceeded | No | Cost control |
| Normal conversation / code review | No | No verify.sh, no trigger |

**Key**: When building does not trigger, the user experience is identical to before installation — zero added latency.

### The Five Phases

```
Phase 0: Setup
  ├─ Create git worktree (isolated environment)
  ├─ Copy HEAD + modified tracked files + untracked files
  └─ Non-git projects: rsync excluding large dirs (node_modules, .venv, etc.)

Phase 1: Load failure trajectory
  └─ Read last 500 lines of session.log

Phase 2: Teacher solves the task
  └─ Teacher model completes the task independently in the worktree

Phase 3: Skill generation
  └─ Teacher analyzes Student's failure trajectory
     Generates three files (using ===BEGIN_FILE=== / ===END_FILE=== markers):
       • CLAUDE.md            — Common pitfalls + correct approach + verification checklist
       • solve-task.md        — Step-by-step skill
       • feedback_lessons.md  — Persistent memory

Phase 4: Parse
  └─ parse-skill.py extracts marked files → writes to skill output directory

Phase 5: Ralph validation (up to 3 rounds)
  ├─ Create fresh worktree
  ├─ Deploy skill (CLAUDE.md + skills + memory)
  ├─ Student model retries the task
  ├─ Check for ===BUILD_RESULT: PASS=== marker
  ├─ PASS → store in upskill-store → sync global index → done ✓
  └─ FAIL → Teacher revises skill → retry (max 3 rounds) → discard if still failing
```

### Validation Criteria

Ralph validation passes when: after the Student model completes the task in the worktree, the output contains `===BUILD_RESULT: PASS===`.

---

## Skill Serving

### Two Tiers

| Tier | Install Location | Load Timing | Scope |
|------|-----------------|-------------|-------|
| **Global** | `~/.claude/upskill-store/CLAUDE.md` | Auto on agent startup | All projects |
| **Global** | `~/.claude/skills/upskill-*.md` | When agent invokes | All projects |
| **Project** | `~/.claude/projects/<slug>/memory/` | Synced per session | Current project |

### Model Compatibility

Each skill records the Student model it was validated against (`base_model`). During serving:

- **Global CLAUDE.md / skills**: Always visible, annotated with base model and compatibility hints.
- **No model-based filtering**: General experience (e.g. "check CSV encoding first") applies across models.
- Users can switch prompting style via `/upskill-mode`.

---

## Management Commands

All invoked via `/upskill-*` slash commands.

| Command | Function |
|---------|----------|
| `/upskill-list` | List all installed skills (grouped by category) |
| `/upskill-build` | Analyze a session and generate a skill |
| `/upskill-run` | Interactive build workflow: scan → match → load → execute |
| `/upskill-status` | View skill count and status |
| `/upskill-remove` | Delete a specific skill or an entire category |
| `/upskill-mode` | Switch or view serve mode |
| `/upskill-model` | Configure Teacher / Student models |
| `/upskill-configure` | Enable Upskill hooks in the current project |
| `/upskill-uninstall` | Uninstall Upskill |
| `/upskill-init` | Initialize Upskill |

---

### /upskill-init

Update Upskill to the latest version. Re-runs the installer to refresh hooks, skills, and config. Also migrates legacy settings if present.

```bash
/upskill-init
```

---

### /upskill-list

List all skills across categories.

```bash
/upskill-list
/upskill-list software-engineering     # show only a specific category
```

Backend: `bash ~/.claude/hooks/upskill-store.sh list`

---

### /upskill-status

View total skill count and active build status.

```bash
/upskill-status
```

---

### /upskill-remove

Delete a skill or an entire category.

```bash
/upskill-remove
/upskill-remove --category data-analysis --skill-id skill_20260605_001
/upskill-remove --category data-analysis     # delete entire category (confirmation required)
```

---

### /upskill-build

Analyze the most recent session and generate a skill. Works for both failed and successful sessions.

```bash
/upskill-build                          # auto-detect category
/upskill-build --category software-engineering
/upskill-build --session <session_id>
```

---

### /upskill-run

Interactive build workflow.

```bash
/upskill-run
```

Flow:
1. Collect task description
2. Scan installed skills and match
3. Display matches (★ = recommended)
4. User selects skill (or "none" to skip)
5. Prompt model switch if model mismatch detected
6. Load SKILL.md and execute task

---

### /upskill-mode

Switch serve mode.

```bash
/upskill-mode              # view current mode
/upskill-mode auto         # switch to auto
/upskill-mode interactive  # switch to interactive
```

---

### /upskill-model

View or switch model configuration.

```bash
/upskill-model          # view current preset
/upskill-model teacher  # show how to switch to Teacher model
/upskill-model student  # show how to switch to Student model
```

---

### /upskill-configure

Enable Upskill hooks in the current project. Configures `.claude/settings.local.json` with claudeMd, before_session, and after_session hooks.

```bash
/upskill-configure
```

---

### /upskill-uninstall

Uninstall Upskill — removes hooks, skills, and config files.

```bash
/upskill-uninstall
```

---

## Configuration

### `~/.claude/upskill.conf`

```bash
UPSKILL_TEACHER="deepseek-v4-pro[1m]"   # Strong model (analyze failures, generate skills)
UPSKILL_STUDENT="deepseek-v4-flash"     # Weak model (skill validation target)
UPSKILL_SERVE_MODE="interactive"         # Serving mode
```

- **TEACHER**: Use a strong model (e.g. `claude-opus`, `deepseek-v4-pro`).
- **STUDENT**: Use the weak model you want to improve (e.g. `claude-haiku`, `deepseek-v4-flash`).
- **Daily model**: Independently set in agent harness settings — unrelated to Teacher/Student.

After modifying config, run `bash ~/.claude/hooks/upskill-store.sh sync` or `/upskill-mode` to apply.

---

## Serve Mode

| Mode | Behavior |
|------|----------|
| **interactive** (default) | Use `/upskill-run` to browse and select skills. |
| **auto** | Auto-match skills by keyword on every prompt. Agent suggests before applying. |

Switching:

```
/upskill-mode              # view current mode
/upskill-mode auto         # switch to auto
/upskill-mode interactive  # switch to interactive
```

### CLAUDE.md entry in interactive mode

```markdown
<!-- UPSKILL:data-analysis -->
## Skill: data-analysis (3 skills)
**Base model:** deepseek-v4-flash
**Trigger:** csv, encoding, json, database, query
**Model:** Validated on `deepseek-v4-flash`. For best results, use this model.

Use `/upskill-run` to browse skills, get recommendations, and apply guidance.
```

### CLAUDE.md entry in auto mode

```markdown
<!-- UPSKILL:data-analysis -->
## Skill: data-analysis (3 skills)
**Base model:** deepseek-v4-flash
**Trigger:** csv, encoding, json, database, query
**Model:** Validated on `deepseek-v4-flash`. For best results, use this model.

Skills are auto-matched on every prompt. Confirm before applying.
```

---

## File Structure

### Source Repository

```
cc-integration/
├── bootstrap.sh                # curl | bash entry point
├── install.sh                  # Installer (supports --remote)
├── upskill-build.sh            # Building pipeline
├── inject-skill.sh             # Memory sync
├── upskill-store.sh            # Skill library management CLI
├── parse-skill.py              # Skill file parser
├── hooks/
│   ├── before-session.sh       # Agent harness before_session hook
│   ├── after-session.sh        # Agent harness after_session hook
│   └── save-session.sh         # On-demand session saver
├── skills/
│   ├── upskill-init.md         # /upskill-init
│   ├── upskill-list.md         # /upskill-list
│   ├── upskill-build.md        # /upskill-build
│   ├── upskill-status.md       # /upskill-status
│   ├── upskill-remove.md       # /upskill-remove
│   ├── upskill-mode.md         # /upskill-mode
│   ├── upskill-model.md        # /upskill-model
│   ├── upskill-run.md          # /upskill-run
│   ├── upskill-configure.md    # /upskill-configure
│   └── upskill-uninstall.md    # /upskill-uninstall
└── templates/
    ├── upskill.conf            # Model config template
    ├── settings-patch.json     # Agent harness hooks + claudeMd config
    └── manifest.yaml           # Skill store manifest template
```

### After Installation (`~/.claude/`)

```
~/.claude/
├── upskill.conf
├── upskill-store/
│   ├── CLAUDE.md               # Global skill index (auto-loaded by agent)
│   ├── manifest.yaml
│   ├── <category>/
│   │   ├── manifest.yaml       # Contains base_model, trigger_keywords
│   │   ├── CLAUDE.md           # Full content
│   │   ├── .claude/skills/
│   │   └── memory/
│   └── .building/               # Temp files (session context + build logs)
├── hooks/
│   ├── before-session.sh
│   ├── after-session.sh
│   ├── upskill-build.sh
│   ├── inject-skill.sh
│   ├── upskill-store.sh
│   └── parse-skill.py
├── skills/
│   ├── upskill-init.md
│   ├── upskill-list.md
│   ├── upskill-build.md
│   ├── upskill-status.md
│   ├── upskill-remove.md
│   ├── upskill-mode.md
│   ├── upskill-model.md
│   ├── upskill-run.md
│   ├── upskill-configure.md
│   ├── upskill-uninstall.md
│   └── upskill-<category>.md  # Category skills (generated by sync)
├── settings.local.json
└── projects/<slug>/memory/      # Skill memory injection target
```

---

## Compatibility with Existing Config

Upskill's `~/.claude/` paths do not conflict with the agent harness's own files:

| Upskill Writes | Used by Agent? | Compatibility |
|---------------|:--:|---------|
| `settings.local.json` | ✓ Native | **Merged**, not overwritten — preserves existing config |
| `skills/upskill-*.md` | ✓ Read by agent | Different filenames, coexists with user skills |
| `projects/<slug>/memory/` | ✓ Read by agent | Appends skill memory, never deletes user memory |
| `hooks/` | ✗ Not used | Upskill-specific directory |
| `upskill-store/` | ✗ Not used | Upskill-specific directory |
| `upskill.conf` | ✗ Not used | Upskill-specific config file |

---

## Porting to Other Agent Harnesses

Upskill's methodology is harness-agnostic. To port it to another agent harness (Codex, OpenClaw, Cursor, etc.), you need:

1. **Session hooks** — equivalents of `before-session` and `after-session` to capture failure context
2. **Skill loading** — a mechanism for the agent to load external files into its context (CLAUDE.md equivalent)
3. **Slash commands** — user-invocable commands to trigger building and manage skills
4. **Isolated execution** — a worktree or sandbox mechanism for safe Teacher/Student runs

The core pipeline (`upskill-build.sh`, Ralph Loop, skill store management) is harness-agnostic. Only the hook integration layer and context loading mechanism need adaptation.

This directory provides the complete reference implementation for Claude Code. Contributions for other harnesses are welcome.

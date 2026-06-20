<div align="center">

<p align="center">
<img src="figures/logo.png" alt="Upskill Logo" width="160" />
</p>

## ✨ Upskill Your Model — Not Your Bill ✨

Turn your Flash model into a Pro. No model upgrade needed.

[![Agents](https://img.shields.io/badge/Agents-Claude_Code-99C9BF.svg)](https://docs.anthropic.com/en/docs/claude-code)
[![Python](https://img.shields.io/badge/Python-3.12+-FCE7D6.svg)](https://www.python.org/)
[![License](https://img.shields.io/badge/License-MIT-C1E5F5.svg)](https://opensource.org/licenses/MIT/)
[![Feishu](https://img.shields.io/badge/Feishu-Group-E9DBFC?style=flat&logo=larksuite&logoColor=white)](./COMMUNICATION.md)
[![WeChat](https://img.shields.io/badge/WeChat-Group-C5EAB4?style=flat&logo=wechat&logoColor=white)](./COMMUNICATION.md)
[![中文文档](https://img.shields.io/badge/文档-中文版-F5C6C6?style=flat)](./README_CN.md)

**UpSkill your Claude Code — with a Single Command**

<p align="center">
<img src="figures/demo-typing.svg" alt="Demo: /upskill-run <task instruction>" />
</p>

</div>

---

## 📰 News

- **2026-06-18** — Initial release: Upskill v1.0 — captures agent failures, distills them into validated skills via the Ralph Loop, and injects them so Flash models outperform Pro models at lower cost. Full Claude Code integration included.

---

## 📋 Table of Contents

- [🤔 The Problem](#-the-problem-with-todays-agents)
- [🔬 Putting UpSkill to the Test](#-putting-upskill-to-the-test)
- [🚀 Quick Start](#-quick-start)
- [📚 Using Skills](#-using-skills)
- [🏗 How UpSkill Works](#-how-upskill-works)
- [📖 Repository Structure](#-repository-structure)
- [🔬 Reproducing the Experiments](#-reproducing-the-experiments)
- [📄 License](#-license)

---

## 🤔 The Problem with Today's Agents

<p align="center">
<img src="figures/motivation.png" alt="Upskill Motivation — Student (cheap but weak), Teacher (strong but expensive), Student + Upskill (strong + affordable)" width="90%" />
</p>

AI Agents (Claude Code, Codex, Cursor, OpenClaw, Hermes, nanobot) are powerful <br> — But one hard truth remains: **their performance is ultimately locked to the model you pay for**.

- ❌ **Pro Models Are Too Expensive** — Claude Opus, GPT-5.5, Gemini-Pro deliver great results, but cost 3–5× more per task. Running them all day is simply unsustainable.

- ❌ **Flash Models Are Too Unreliable** — Claude Haiku, GPT-5.5 mini, Gemini-Flash are affordable, but simply don't perform at the level of a Pro model. You end up spending more time fixing errors than saving costs.

That's why we built UpSkill — a lightweight framework that turns your Flash model into a Pro, by continuously **Evolving Skills** that empower weaker models to perform at the level of their stronger counterparts.

---

## 🔬 Putting UpSkill to the Test

- **Benchmark**: **Terminal-Bench 2.0** — 89 real-world terminal tasks across 16 categories, spanning software engineering, data science, system administration, security, and more.

- **Setup**: Stratified 25/64 train/test split — skills distilled from Base Model trajectories on 25 training tasks, then deployed on 64 held-out test tasks.

- **Results**: All metrics reported on the held-out test set.

| | 🟡 Flash Model<br>(deepseek-v4-flash) | 🔵 Pro Model<br>(deepseek-v4-pro[1m]) | 🟢 Flash Model + Upskill |
|---|:--:|:--:|:--:|
| **Test Pass Rate** | 45.3% | 50.0% | **51.6%** |
| **Test Cost** | $1.93 | $4.01 | **$2.36** |
| **Cost per task** | $0.03 | $0.06 | **$0.04** |

> 💡 A **$0.04/task Flash** Model, augmented with **UpSkill**, outperformed a **$0.06/task Pro** Model — delivering comparable results at **41% lower cost**.

### 📊 What This Means in Practice

- ✅ **5 tasks flipped FAIL → PASS** — count-dataset-tokens, headless-terminal, query-optimize, mailman, winning-avg-corewars
- ✅ **Strongest category gains** — model-training (+33%), data-science (+17%), system-administration (+17%), software-engineering (+11%)
- ✅ **UpSkill's one-time skill brewing cost**: ~$2 across all 64 tasks — minimal overhead to evolve skills that benefit every future task.

> Full results: [`tb_harbor_2.0/RESULTS.md`](tb_harbor_2.0/RESULTS.md)

---

## 🚀 Quick Start

### 1. Install

```bash
curl -sSL https://raw.githubusercontent.com/HKUDS/Upskill/main/cc-integration/install.sh | bash -s -- --remote
```

> [!TIP]
> The installer handles everything — hooks, skills, config, and store. To update Upskill to the latest version later, run `/upskill-init`.

### 2. Configure Models

`/upskill-init` creates `~/.claude/upskill.conf`. Edit it to set your Teacher and Student models. We recommend using DeepSeek models for the best cost-performance ratio:

```bash
# ~/.claude/upskill.conf
UPSKILL_TEACHER="deepseek-v4-pro[1m]"   # Strong model for analysis + skill generation
UPSKILL_STUDENT="deepseek-v4-flash"     # Weak model — skills are validated for this
```

Or use Anthropic models:

```bash
UPSKILL_TEACHER="claude-opus-4-7"       # Strong model
UPSKILL_STUDENT="claude-haiku-4-5"      # Weak model
```

> [!NOTE]
> Your daily model stays independent — use whatever you want day-to-day. Switch it anytime without affecting Upskill. Use `/upskill-model` to view your current presets.

### 3. Enable per-project

Run this command inside each project where you want building enabled:

```bash
/upskill-configure
```

This configures the project's hooks so Upskill can capture failures and inject skills automatically.

### 4. Use Your Agent — Skills Build Themselves

Use your agent normally. When a task fails, Upskill captures the full session context automatically. Next time you open the agent, you'll see:

```
[upskill] ⚠ 1 pending failure(s) ready for building. Run /upskill-build to generate skills.
```

Run `/upskill-build` and the Teacher model takes over — it analyzes what went wrong, generates a skill, and the Ralph Loop validates it against the Student model. Validated skills are stored and auto-injected into all future sessions. No config changes, no manual prompts.

You can also run `/upskill-build` proactively on any past session — successes included — to distill good patterns into reusable skills.

---

## 📚 Using Skills

### Commands at a Glance

| Command | What it does |
|---------|-------------|
| `/upskill-build` | Analyze a past session (failure or success) and generate a skill |
| `/upskill-run` | Interactive workflow: scan skills → match → apply |
| `/upskill-list` | Browse all installed skills by category |
| `/upskill-status` | View skill count and active builds |
| `/upskill-configure` | Enable Upskill hooks in the current project |
| `/upskill-model` | View or switch Teacher / Student models |
| `/upskill-mode` | Toggle between interactive and auto serve modes |
| `/upskill-remove` | Delete a skill or category |
| `/upskill-uninstall` | Remove Upskill completely |

### /upskill-run in Action

`/upskill-run` is the interactive skill application workflow. Instead of injecting skills silently, it lets you browse, compare, and choose the right skill for the task at hand.

**Example — working on a CSV filtering task:**

```
> /upskill-run filter a CSV by column value

Here are the available skills:

  ★ 1. data-analysis/skill_20260605_001  [recommended]
     Python CSV data-processing tools — filter/sort/select
     Validated on: deepseek-v4-flash  (current: deepseek-v4-flash ✓)

    2. software-engineering/skill_20260606_005
     Python CLI tools with argparse patterns
     Validated on: deepseek-v4-flash  (current: deepseek-v4-flash ✓)

★ = matched your task. Enter number(s) to apply, or "none" to skip.
```

You pick `1` — the agent loads the SKILL.md, reads the step-by-step checklist and common pitfalls, then executes your CSV task with the distilled knowledge. If the skill was validated on a different model than your current one, `/upskill-run` prompts you to switch first.

### How Skills Appear in Your Agent

Once skills are built, your agent sees them automatically in its context. For example, after a few builds in the `data-analysis` category:

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

Each skill is a single `SKILL.md` file with YAML frontmatter and three sections, validated by the Ralph Loop:

```
~/.claude/upskill-store/<category>/<skill_id>/
├── SKILL.md           # Complete skill
└── description.txt    # One-paragraph summary
```

`SKILL.md` structure:

```markdown
---
name: skill_20260605_001
description: For Python CSV data-processing tools...
metadata:
  category: data-analysis
  base_model: deepseek-v4-flash
  created: 2026-06-05T12:34:56
  trigger_keywords: [csv, encoding, json, database, query]
---

# Domain Knowledge
Common pitfalls, correct approach, and verification checklist.
(At serve time: injected into the agent's CLAUDE.md)

# Step-by-Step
Ordered checklist with concrete commands and code snippets.
(At serve time: loaded as a solve-task skill on demand)

# Feedback / Lessons
Rule: <concise rule>
Why: <why it matters>
How to apply: <how to follow it>
(At serve time: loaded together with the full SKILL.md)
```

All three sections are delivered through two channels: the CLAUDE.md index (always in context) and the full SKILL.md loaded on demand — one validated file, two delivery paths.

### Serve Modes

| Mode | Behavior |
|---|---|
| **interactive** (default) | Use `/upskill-run` to browse skills and choose which to apply. |
| **auto** | Skills are keyword-matched on every prompt. The agent proactively suggests relevant ones. |

```bash
/upskill-mode              # view current mode
/upskill-mode auto         # switch to auto
/upskill-mode interactive  # switch to interactive
```

> Full documentation: [`cc-integration/README.md`](cc-integration/README.md)

---

## 🏗 How UpSkill Works
UpSkill integrates into your agent harness as lightweight session hooks — no infrastructure changes required. The system operates across three roles:

🟡 **Daily Model** — your model of choice, handling everyday tasks<br>
🔵 **Pro Model** — a strong model responsible for failure analysis and skill generation<br>
🟢 **Flash Model** — the weak model that all skills must be validated against before deployment

When a session ends, the hooks capture the outcome. On failure, the full context is preserved and passed to the Pro Model for analysis.

### The Skill Building Pipeline
Once stored, skills are automatically delivered to future sessions through two channels:
- **CLAUDE.md index** — always in context, ~5 lines per skill with summary and trigger keywords
- **SKILL.md on demand** — loaded via `/upskill-run` (interactive) or auto-matched by keyword; contains all three sections (Domain Knowledge, Step-by-Step, and Feedback/Lessons)

<p align="center">
<img src="figures/pipeline.png" alt="Upskill Building Pipeline — 6 phases from failure capture to skill storage" width="90%" />
</p>

### The Ralph Loop — Why Validation Is the Hard Part

Most approaches stop too early: Pro Model writes advice, saves it, and hopes it helps. The problem? Strong model advice is not calibrated to weak model behavior — the Flash Model may not know how or when to apply it.

<p align="center">
<img src="figures/ralph_loop.png" alt="Ralph Loop — validation cycle: Student+skill fails, Teacher revises, retry up to 3 rounds" width="80%" />
</p>

**The Ralph Loop closes this gap:**
- **Round 1** — Flash Model fails. Pro Model analyzes the failure and generates an initial skill.
- **Round 2** — Flash Model retries with the skill. If it still fails, the Pro Model refines based on a richer signal: "what went wrong even with my guidance?" The loop continues until the skill demonstrably works.

**Why this matters:**
- ✅ **Calibrated to the Flash Model** — instructions the Flash Model has proven it can follow, not generic best practices
- ✅ **Each round yields stronger signal** — failure with guidance reveals precisely where the advice broke down
- ✅ **Quality over quantity** — skills that don't survive validation are discarded; every entry is battle-tested

This is why UpSkill can push a weak model past the strong model that trained it:
- 📚 Skills encode the Pro Model's knowledge
- 🔄 Refined by the Flash Model's actual behavior
- 🎯 The result: targeted, battle-tested guidance that a stronger model alone could never produce

---

## 📖 Repository Structure

<details>
<summary><b>Click to expand</b></summary>

```
Upskill/
│
├── cc-integration/           ← The Upskill plugin (what you install)
│   ├── install.sh             # One-line installer
│   ├── upskill-build.sh       # Building pipeline (the core)
│   ├── upskill-store.sh       # Skill library management
│   ├── hooks/                 # Session hooks (before/after session)
│   ├── skills/                # Slash commands (/upskill-*)
│   ├── templates/             # Config templates
│   └── README.md              # Full usage documentation
│
├── figures/                   ← Diagrams and illustrations
│   ├── logo.png               # Project logo
│   ├── motivation.png         # Student vs Teacher vs Upskill
│   ├── pipeline.png           # Building pipeline overview
│   ├── ralph_loop.png         # Ralph validation loop
│   └── demo-typing.svg        # Animated terminal demo
│
├── tb_harbor_2.0/            ← Terminal-Bench 2.0 experiment
│   ├── tasks/                 # 89 benchmark tasks (16 categories)
│   ├── train.txt / test.txt   # 25/64 stratified split
│   ├── RESULTS.md             # Experimental results
│   └── REPRODUCE.md           # Step-by-step reproduction guide
│
├── scripts/                   # Experiment pipeline scripts
│   ├── run_baseline.sh        # Student & Teacher baselines
│   ├── run_brew.py            # Per-task skill generation
│   ├── run_curator.py         # Category-level skill curation
│   ├── run_ralph.py           # Ralph validation loop
│   ├── run_serve.sh           # Deploy skills to test set
│   ├── run_analyze.py         # Results analysis
│   ├── build_catalog.py       # Skill catalog builder
│   ├── split_dataset.py       # Train/test split
│   ├── patch_harbor.sh        # Harbor framework patches
│   └── ...                    # Additional utilities
│
└── configs/                   # Model config templates
    ├── strong.env.template    # Teacher model config
    └── weak.env.template      # Student model config
```

</details>

---

## 🔬 Reproducing the Experiments

The TB 2.0 experiments follow a 6-step pipeline:

```
Baselines → Brew → Curate → Ralph → Serve → Analyze
```

Prerequisites: macOS (or Linux with Docker), Python 3.12+, Docker Desktop, Git LFS.

<details>
<summary><b>Quick setup</b></summary>

```bash
# 1. Install Harbor
python3.13 -m venv .venv_harbor && source .venv_harbor/bin/activate
pip install harbor && bash scripts/patch_harbor.sh

# 2. Configure API keys
cp configs/strong.env.template configs/strong.env
cp configs/weak.env.template configs/weak.env
# Edit both files with your DeepSeek API key

# 3. Run baselines → brew → curate → ralph → serve → analyze
```

</details>

See [`tb_harbor_2.0/REPRODUCE.md`](tb_harbor_2.0/REPRODUCE.md) for the complete guide with expected outputs and troubleshooting.

---

## 📄 License

MIT — see [LICENSE](LICENSE) for details.

---

<p align="center">
  <em> ❤️ Thanks for visiting ✨ Upskill!</em><br><br>
  <img src="https://visitor-badge.laobi.icu/badge?page_id=HKUDS.Upskill&style=for-the-badge&color=00d4ff"
  alt="Views">
</p>

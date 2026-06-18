# Reproducing TB 2.0 AgentBrew Experiments

This guide reproduces the full pipeline: Student baseline → Teacher baseline → Brewing → Curator → Ralph Validation → Serving.

## Prerequisites

- **macOS** (or Linux with Docker)
- **Docker Desktop** running
- **Python 3.12+** (for Harbor; tested on 3.13)
- **Git LFS** (for large file support)

## Step 1: Install Harbor

```bash
# Create virtual environment
python3.13 -m venv .venv_harbor
source .venv_harbor/bin/activate

# Install Harbor
pip install harbor

# Apply patch (fixes claude.ai region block for CC CLI installation)
bash scripts/patch_harbor.sh
```

## Step 2: Configure API Keys

```bash
# Copy from templates and fill in your DeepSeek API key
cp configs/strong.env.template configs/strong.env
cp configs/weak.env.template configs/weak.env
```

Edit `configs/weak.env`:
```bash
ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic
ANTHROPIC_AUTH_TOKEN=<your-deepseek-api-key>
ANTHROPIC_MODEL=deepseek-v4-flash
ANTHROPIC_DEFAULT_OPUS_MODEL=deepseek-v4-flash
ANTHROPIC_DEFAULT_SONNET_MODEL=deepseek-v4-flash
ANTHROPIC_DEFAULT_HAIKU_MODEL=deepseek-v4-flash
CLAUDE_CODE_SUBAGENT_MODEL=deepseek-v4-flash
CLAUDE_CODE_EFFORT_LEVEL=max
```

Edit `configs/strong.env`:
```bash
ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic
ANTHROPIC_AUTH_TOKEN=<your-deepseek-api-key>
ANTHROPIC_MODEL=deepseek-v4-pro[1m]
ANTHROPIC_DEFAULT_OPUS_MODEL=deepseek-v4-pro[1m]
ANTHROPIC_DEFAULT_SONNET_MODEL=deepseek-v4-pro[1m]
ANTHROPIC_DEFAULT_HAIKU_MODEL=deepseek-v4-flash
CLAUDE_CODE_SUBAGENT_MODEL=deepseek-v4-flash
CLAUDE_CODE_EFFORT_LEVEL=max
```

## Step 3: Run Baselines

```bash
# Student baseline (deepseek-v4-flash) on all 89 tasks
bash scripts/run_baseline.sh --model student --split all
# Output: tb_harbor_2.0/jobs_baseline_student_all/

# Teacher baseline (deepseek-v4-pro) on all 89 tasks
bash scripts/run_baseline.sh --model teacher --split all
# Output: tb_harbor_2.0/jobs_baseline_teacher_all/
```

> **Time estimate**: ~4-5 hours each with 4 concurrent. Set `--n-concurrent 8` for faster runs.

## Step 4: Brew (Generate ACP from Student Trajectories)

```bash
# Generate per-task ACP using teacher model
python3 scripts/run_brew.py \
    --student-job tb_harbor_2.0/jobs_baseline_student_all \
    --split train
# Output: tb_harbor_2.0/brew_acp/<category>/<task>_*.md
```

> **What it does**: For each training task, extracts the student trajectory, then asks the teacher to analyze it and generate CLAUDE.md + skill + feedback memory.

## Step 5: Curate (Merge ACP by Category)

```bash
# Merge per-task ACP into one curated ACP per category
python3 scripts/run_curator.py \
    --acp-dir tb_harbor_2.0/brew_acp
# Output: tb_harbor_2.0/curated_acp/<category>/
```

## Step 6: Ralph Validation (Validate ACP with Student)

```bash
# Validate ACP: student retries train tasks with ACP, teacher refines on failure
python3 scripts/run_ralph.py \
    --acp-dir tb_harbor_2.0/brew_acp \
    --student-job tb_harbor_2.0/jobs_baseline_student_all \
    --max-rounds 3
# Output: tb_harbor_2.0/jobs_ralph_r{1,2,3}/, ralph_status.json
```

> Ralph runs up to 3 rounds per task. Tasks that PASS in any round are marked validated. The rest are marked as failed.

## Step 7: Serve (Run Student + ACP on Test Set)

```bash
# Deploy curated ACP to test tasks and run student CC
bash scripts/run_serve.sh \
    --acp-dir tb_harbor_2.0/curated_acp
# Output: tb_harbor_2.0/jobs_serve/
```

## Step 8: Analyze Results

```bash
# Generate RESULTS.md with pass rates, GAIN/LOSS, cost breakdown
python3 scripts/run_analyze.py \
    --baseline-student tb_harbor_2.0/jobs_baseline_student_all \
    --baseline-teacher tb_harbor_2.0/jobs_baseline_teacher_all \
    --serve tb_harbor_2.0/jobs_serve \
    --split tb_harbor_2.0/split.json \
    --output tb_harbor_2.0/RESULTS.md
```

## Expected Results (from our run)

| | Student | Teacher | Serve+ACP |
|------|:--:|:--:|:--:|
| Test Pass Rate | 45.3% | 50.0% | **51.6%** |
| Test Cost (64 tasks) | $1.93 | $4.01 | $2.36 |

## Pipeline Quick Reference

```
run_baseline.sh ──→ run_brew.py ──→ run_curator.py ──→ run_ralph.py
                                                             │
                                                             ▼
                         RESULTS.md ◄── run_analyze.py ◄── run_serve.sh
```

## Directory Structure

```
tb_harbor_2.0/
  tasks/                    # 89 official TB 2.0 tasks
  train.txt / test.txt      # 25 train / 64 test split
  split.json                # Split with category annotations
  curated_acp/              # Final ACP (9 categories)
  RESULTS.md                # Analysis report
  REPRODUCE.md              # This file

  jobs_*/                   # Harbor experiment outputs (gitignored, generated)
  brew_acp/                 # Per-task ACP (intermediate, generated)
```

## Troubleshooting

- **"Docker daemon is not running"**: Start Docker Desktop.
- **"claude --version failed"**: Run `bash scripts/patch_harbor.sh` to fix CC CLI installation.
- **"API Error: supported model names are..."**: Ensure `--model` matches the API (e.g., `deepseek-v4-flash` not `deepseek/deepseek-v4-flash`).
- **"output token maximum" error**: Set `CLAUDE_CODE_MAX_OUTPUT_TOKENS=64000` in the env file.
- **QEMU tasks fail**: These need KVM support; they error gracefully on macOS.

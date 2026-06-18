# Terminal-Bench 2.0 (Harbor) — Official Dataset

**Source**: `harborframework/terminal-bench-2.0` (HuggingFace)
**Framework**: Harbor (`harbor run --dataset terminal-bench@2.0`)
**Date prepared**: 2026-06-10

## Overview

| Metric | Value |
|--------|-------|
| Total tasks | **89** |
| Categories | 16 |
| Difficulty | easy 4, medium 55, hard 30 |
| Dataset size | 43.8 MB |
| Total files | 857 (avg 9.6/task) |
| Avg instruction length | 970 chars |
| Avg solution length | 10,478 chars |

## Train/Test Split

Stratified 30/70 split within each category. Singleton categories (1 task) go entirely to test.

| | Count | % |
|------|:--:|:--:|
| **Train** | **25** | 28.1% |
| **Test** | **64** | 71.9% |

### By Category

| Category | Total | Train | Test |
|----------|:--:|:--:|:--:|
| software-engineering | 26 | 8 | 18 |
| system-administration | 9 | 3 | 6 |
| data-science | 8 | 2 | 6 |
| scientific-computing | 8 | 2 | 6 |
| security | 8 | 2 | 6 |
| debugging | 5 | 2 | 3 |
| file-operations | 5 | 2 | 3 |
| data-processing | 4 | 1 | 3 |
| mathematics | 4 | 1 | 3 |
| model-training | 4 | 1 | 3 |
| machine-learning | 3 | 1 | 2 |
| data-querying † | 1 | 0 | 1 |
| games † | 1 | 0 | 1 |
| optimization † | 1 | 0 | 1 |
| personal-assistant † | 1 | 0 | 1 |
| video-processing † | 1 | 0 | 1 |

† Singleton category — no train representation.

## File Structure

```
tb_harbor_2.0/
├── README.md           # This document
├── tasks/              # 89 task directories
│   └── <task-name>/
│       ├── instruction.md          # Task instruction
│       ├── task.toml               # Metadata (category, difficulty, tags)
│       ├── environment/
│       │   ├── Dockerfile          # Sandbox environment
│       │   └── protected.tar.gz.enc
│       ├── solution/
│       │   └── solve.sh            # Reference solution
│       └── tests/
│           ├── test.sh
│           └── test_outputs.py     # Verification script
├── train.txt           # 25 training task IDs
├── test.txt            # 64 testing task IDs
├── split.json          # Full split with category annotations
├── task_list.txt       # All 89 task IDs
└── task_metadata.json  # Per-task metadata (category, difficulty, sizes)
```

## Key Files

| File | Description |
|------|-------------|
| `train.txt` | 25 task IDs, one per line |
| `test.txt` | 64 task IDs, one per line |
| `split.json` | `{"train": {task: category, ...}, "test": {task: category, ...}}` |
| `task_metadata.json` | Array of `{task_id, category, difficulty, instruction_chars, solution_chars, files}` |

## Difficulty Distribution

| Difficulty | Count |
|------------|:--:|
| easy | 4 |
| medium | 55 |
| hard | 30 |

## Relation to Local Data

- Overlap with `tb_repo/original-tasks/` (241 tasks): 88/89
- Missing locally: `headless-terminal`
- Local extras (non-official): 153 tasks

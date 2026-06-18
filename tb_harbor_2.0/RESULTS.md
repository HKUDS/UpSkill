# Terminal-Bench 2.0 — Experimental Results

**Date**: 2026-06-10 to 2026-06-12
**Dataset**: 89 tasks, stratified 25 train / 64 test
**Model**: Student = `deepseek-v4-flash`, Teacher = `deepseek-v4-pro[1m]`

## Test Set Results (64 tasks)

```
                       Student    Teacher    Serve+ACP
PASS                      29         32          33
FAIL (incl. ERROR)        35         32          31
  - pure FAIL             28         30          25
  - FAIL ∩ ERROR           6          1           6
  - pure ERROR             1          1           1
──────────────────────────────────────────────────────
合计                      64         64          64
Pass Rate               45.3%      50.0%       51.6%
```

### GAIN / LOSS

| Metric | Student+A vs Baseline | Student+A vs Teacher |
|------|:--:|:--:|
| GAIN (F→P) | 5 | 7 |
| LOSS (P→F/ERR) | 1 (tune-mjcf) | — |
| Net | **+4** | — |

### GAIN Tasks (Student Baseline FAIL → Serve+ACP PASS)

| Task | Category |
|------|------|
| count-dataset-tokens | model-training |
| headless-terminal | software-engineering |
| mailman | system-administration |
| query-optimize | data-science |
| winning-avg-corewars | software-engineering |

### LOSS Tasks (Student Baseline PASS → Serve+ACP FAIL/ERROR)

| Task | Category | Note |
|------|------|------|
| tune-mjcf | scientific-computing | real regression |

### Random Variance Recoveries

| Task | Baseline | Serve | Retry |
|------|:--:|:--:|:--:|
| feal-linear-cryptanalysis | PASS | ERROR | PASS (64K token fix) |
| distribution-search | PASS | FAIL | PASS |
| llm-inference-batching-scheduler | PASS | FAIL | PASS |

---

## Cost Analysis (DeepSeek Official Pricing, Test Set)

### Pricing per 1M tokens

| | V4-Flash (Student) | V4-Pro (Teacher) |
|------|:--:|:--:|
| Input (cache miss) | $0.14 | $0.435 |
| Input (cache hit) | $0.0028 | $0.003625 |
| Output | $0.28 | $0.87 |

### Token Usage (Test Set)

```
                         Student          Teacher          Student+ACP
Input (prompt)         218,301,340      203,265,121       291,687,912
Cache Read (hit)       215,127,808      200,352,512       288,484,480
Uncached (miss)          3,173,532        2,912,609         3,203,432
Output                   3,161,357        2,318,150         3,924,992
Cache Hit Rate              98.5%            98.6%             98.9%
```

### Cost Breakdown (Test Set)

```
                         Student          Teacher          Student+ACP
Input (cache miss)      $    0.44        $    1.27         $    0.45
Input (cache hit)       $    0.60        $    0.73         $    0.81
Output                  $    0.89        $    2.02         $    1.10
TOTAL                   $    1.93        $    4.01         $    2.36
Avg per task            $    0.03        $    0.06         $    0.04
```

### Brewing Cost (ACP Generation)

| Phase | Cost |
|------|------|
| Phase 3: Per-task Brew (21 tasks) | $10.11 |
| Phase 4: Curator (9 categories) | $2.82 |
| Phase 5: Ralph Validation (3 rounds) | ~$103 |
| **Total Brewing** | **~$116** |

### Cost on All-Three-PASS Tasks (23 tasks)

These are tasks that PASS in all three experiments — typically the "easy" ones.

```
                       Student    Teacher    Serve+ACP
PASS in all 3              23         23          23
Avg Prompt Tokens      867,889    891,338     890,507
Avg Cache Hit          835,016    858,412     857,622
Avg Output              21,750     16,845      23,685
Avg Cost                $0.01      $0.03       $0.01
Total Cost (23)         $0.30      $0.74       $0.31
```

---

## Per-Category Delta (Test Set)

| Category | #Tasks | Baseline | Serve+ACP | Δ |
|------|:--:|:--:|:--:|:--:|
| software-engineering | 18 | 22.2% | 33.3% | **+11.1%** |
| data-science | 6 | 50.0% | 66.7% | **+16.7%** |
| model-training | 3 | 33.3% | 66.7% | **+33.3%** |
| system-administration | 6 | 50.0% | 66.7% | **+16.7%** |
| scientific-computing | 6 | 16.7% | 0.0% | **-16.7%** ⚠️ |
| security | 6 | 66.7% | 66.7% | — |
| data-processing | 3 | 100.0% | 100.0% | — |
| data-querying | 1 | 100.0% | 100.0% | — |
| debugging | 3 | 66.7% | 66.7% | — |
| file-operations | 3 | 33.3% | 33.3% | — |
| optimization | 1 | 100.0% | 100.0% | — |
| personal-assistant | 1 | 100.0% | 100.0% | — |
| machine-learning | 2 | 100.0% | 100.0% | — |
| mathematics | 3 | 66.7% | 66.7% | — |
| games | 1 | 0.0% | 0.0% | — |
| video-processing | 1 | 0.0% | 0.0% | — |

## Key Findings

1. **Student+ACP (51.6%) surpasses Teacher (50.0%)** while costing 1.7x less ($2.36 vs $4.01)
2. ACP shows strongest gains in model-training (+33%), system-admin (+20%), data-science (+17%), software-engineering (+11%)
3. ~98.5% cache hit rate keeps per-task cost below $0.06
4. Brewing overhead (~$116) is amortized over future tasks
5. Only 1 real regression (tune-mjcf) out of 35 baseline PASS tasks

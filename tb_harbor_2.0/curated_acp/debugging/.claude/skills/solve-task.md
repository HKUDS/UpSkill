---
name: git-bundle-merge-pattern
description: Winning approach for git bundle fetch + merge + algorithm derivation tasks
metadata:
  type: feedback
---

# Git Bundle Merge with Algorithm Resolution

**Rule:** When merging conflicting branches that each contain an algo.py, always inspect both branches AND the examples file BEFORE attempting the merge. Derive the algorithm from input→output patterns in examples.json, then use that derivation to resolve merge conflicts.

**Why:** Students who inspect both branches before merging, derive the algorithm by analyzing position-based patterns (e.g., `(i+j) % 3`) in the examples, and verify against all examples pass. Those who merge blindly and guess at conflict resolution fail because the algorithm generalizes to hidden test cases — a guess that works on visible examples won't survive hidden tests.

**How to apply:**
1. Before merging, `git checkout` each branch and read algo.py and examples.json
2. Derive the mapping algorithm by comparing input[i][j] to output[i][j] across all examples — common patterns involve `(i+j) % N`, position-based rotation, or mapping non-zero cells using repeating patterns
3. Only merge after you have a candidate formula that works on ALL visible examples
4. After merging and resolving, run a Python validation script asserting every example input maps to its expected output
5. If any assertion fails, revise — do not commit until all pass

See also: [[inspect-before-merge]], [[bundle-fetch-workflow]]

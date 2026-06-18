---
name: data-merge-priority-pattern
description: Winning pattern for merging heterogeneous data sources with conflict resolution by priority
metadata:
  type: feedback
---

# Data Merge: Priority-Based Concat Pattern

**Rule:** When merging data from multiple sources with different schemas where source priority
determines conflict resolution, use the "normalize-then-concat" pattern: normalize each source
to a common schema independently, then `pd.concat([highest_priority, ..., lowest_priority])`
followed by `drop_duplicates(subset='key', keep='first')`.

**Why:** The `keep='first'` behavior of `drop_duplicates` naturally implements source priority
without any custom conflict-resolution code in the merge step. This is simpler and less
error-prone than iterative merge/join logic. Separating normalization from merging keeps each
concern clean, testable, and independently debuggable.

**How to apply:**
1. Explore each source first — read it and print dtypes + head to understand schema
2. Write a per-source normalization function that renames columns and casts types
3. Concat DataFrames in priority order: source_a first, then source_b, then source_c
4. `drop_duplicates(subset='key', keep='first')` handles the merge with no custom logic
5. Detect conflicts separately by comparing normalized DataFrames (not the merged result)
6. Use `pd.isna()` for NaN-safe field comparison — two NaNs ≠ conflict

**Anti-patterns to avoid:**
- Iterative `pd.merge()` with custom conflict-resolution callbacks — fragile and hard to debug
- Detecting conflicts from the merged result — you lose which source each value came from
- Using `==` for field comparison without `pd.isna()` guards — NaN != NaN in Python

**When NOT to use this pattern:**
- When you need a full outer join (keep rows from all sources even without key overlap)
- When conflict resolution requires per-column business rules, not simple source priority
- When sources are too large to hold all normalized frames in memory simultaneously

Related: [[csv-whitespace-headers]] [[parquet-type-roundtrip]] [[date-normalization]]

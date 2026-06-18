---
name: file-operations-best-practices
description: Consolidated rules for gcode text extraction and Vim macro CSV transformations
metadata:
  type: feedback
---

## Rule 1: Gcode is plain text — extract from comments, not geometry

**Why:** A student attempted to reverse-engineer printed text by parsing G0/G1 toolpath coordinates and describing shapes. The embossed text was visible in a `; Embossed text: "..."` comment the entire time. This approach wasted effort and produced wrong output.

**How to apply:** Read the gcode file directly with `cat`/`head`/Read. Search comments with `grep -i 'emboss'` or `grep ';.*".*"'`. Write ONLY the raw text string to output — no geometry, dimensions, or narrative. See [[solve-task]] Type A.

## Rule 2: Vim macro CSV transformations — understand the diff first, one concern per macro, bare `:s/` only

**Why:** A successful student completed a 1M-row CSV transformation with 81 total keystrokes by following this pattern. The critical insights: (1) reading both files first avoids guesswork, (2) splitting work into 3 distinct macros (delimiter, case, reorder) keeps each simple, and (3) using bare `:s/` (not `:%s/`) avoids O(n²) — `:%normal!` already iterates every line.

**How to apply:** Start by diffing `input.csv` and `expected.csv`. Design macros `a` (delimiter+whitespace), `b` (casing), `c` (column reorder). Write `/app/apply_macros.vim` with only `call setreg()`, `:%normal!`, and `:wq`. Prefer single-quoted `setreg()` to avoid backslash escaping. Test with `vim -Nu NONE -n -Es` then `diff`. See [[solve-task]] Type B.

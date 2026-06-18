---
name: data-science-feedback
description: Consolidated feedback from data-science tasks — anti-patterns and correct approaches
metadata:
  type: feedback
---

## Anti-Pattern 1: Over-Planning Without Producing Code

Students on resharding tasks spent entire turns in plan mode (exploring data, designing
utility libraries, discussing architecture) and never wrote a single executable line.
The `/app` directory was left empty.

**Why:** Decompression can only be validated against actual compression output.
Building paired tools in parallel (or planning them together) wastes cycles.

**How to apply:** Spend ≤5 min exploring input data. Write and test the first script
(compress.py, model loader) immediately. Only then build the paired script.
See [[Claude.md]] for the full workflow.

## Anti-Pattern 2: Overlap Resolution at the Wrong Abstraction Level

Students on segmentation tasks resolved mask overlaps by eroding masks or by resolving
after polygon extraction. Both approaches are wrong:
- Erosion changes true mask boundaries and doesn't guarantee zero overlap.
- Polygon extraction is lossy; resolving after it creates fragile output.

**The fix:** Resolve overlaps at the raster/pixel level BEFORE polygon extraction.
Build a label map, assigning each pixel to the highest-scoring mask that claims it.
This guarantees zero overlap by construction.

**Related:** [[connected-components-threshold]]

## Anti-Pattern 3: Connected-Components Threshold Bug

`cv2.connectedComponents` labels background as 0, so a single foreground component
yields `n_labels = 2` (background + 1 component). Students checked `n_labels > 1`,
which is always true. The correct check is `n_labels > 2`.

**How to apply:** Always use `n_labels > 2` when checking for multi-component masks.
See [[solve-task]] step 5 for the exact code.

## Related
[[Claude.md]] — full project guidance
[[solve-task]] — step-by-step checklist

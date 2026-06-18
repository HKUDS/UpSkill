# solve-task — Data Science Checklist

Ordered checklist. Follow these steps exactly — do NOT skip or reorder.

## Universal Steps (All Tasks)

### 1. Project Setup
- Write `pyproject.toml` with dependencies (use `uv` for package management).
- Run `uv sync`.
- All scripts use `argparse` — never hardcode paths. Scripts run on hidden test sets.

### 2. Explore Input Data (≤5 min)
- Count files, check sizes, inspect types/schema.
- Note edge cases: empty files, boundary conditions, format quirks.
- Do NOT architect a utility library — start writing the actual script.

### 3. Validate Output
- Define a quality gate BEFORE saving: what must be true for output to be correct?
- Run the validation after writing output; fail loudly if it doesn't pass.

---

## Resharding Tasks

### 1. Write compress.py
- Read input files in binary mode.
- Group into shards, each ≤15 MB and ≤30 directory entries.
- Seal shards on clean directory boundaries (don't split a directory across shards).
- Write a manifest recording what went into each shard.

### 2. Test compress.py Immediately
- Verify shard count is correct.
- Verify every shard ≤15 MB.
- Verify every shard ≤30 entries.
- Fix bugs before proceeding.

### 3. Write decompress.py
- Read the manifest. Reconstruct the original directory tree from shards.

### 4. Roundtrip Test
```bash
diff -r <original_dir> <decompressed_dir>   # must be silent
```

---

## Segmentation / SAM Tasks

### 1. Parse Arguments & Load Model
```python
import argparse, torch, cv2, numpy as np, pandas as pd
from mobile_sam import sam_model_registry, SamPredictor

# argparse: --weights_path, --output_path (file, not dir), --rgb_path, --csv_path

model = sam_model_registry["vit_t"](checkpoint=args.weights_path)
model.to("cpu"); model.eval()
```

### 2. Load Image (Once) & CSV
```python
image_bgr = cv2.imread(args.rgb_path)
image_rgb = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2RGB)
predictor = SamPredictor(model)
predictor.set_image(image_rgb, image_format="RGB")  # expensive — ONE call

df = pd.read_csv(args.csv_path)  # do NOT set index_col
# Expect columns: xmin, ymin, xmax, ymax, coords_x, coords_y (+ others)
```

### 3. Generate SAM Masks for All Cells
Loop through all rows with `torch.no_grad()` and `tqdm`:
- Box = `np.array([xmin, ymin, xmax, ymax])` (XYXY).
- `predictor.predict(box=box, multimask_output=False)` → one mask per box.
- Collect `masks[i]` (bool H×W) and `scores[i]` (float IoU).

### 4. Resolve Overlaps at Raster Level (CRITICAL)
```python
sorted_idx = np.argsort(scores)[::-1]  # highest score first
label_map = np.zeros((H, W), dtype=np.int32)
for idx in sorted_idx:
    label_map[(masks[idx]) & (label_map == 0)] = idx + 1
```
Each pixel belongs to exactly 0 or 1 masks. Zero overlap by construction.
**Do NOT erode masks. Do NOT resolve after polygon extraction.**

### 5. Ensure Contiguity
For each cell `i`:
```python
cell = (label_map == i + 1).astype(np.uint8)
if cell.sum() == 0: continue  # fully covered → bbox fallback
n_labels, labels, stats, _ = cv2.connectedComponentsWithStats(cell, connectivity=8)
if n_labels > 2:  # >2, NOT >1 — background is label 0
    areas = stats[1:, cv2.CC_STAT_AREA]
    largest = np.argmax(areas) + 1
    label_map[(label_map == i + 1) & (labels != largest)] = 0
```

### 6. Extract Polylines
```python
contours, _ = cv2.findContours(cell_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
if contours:
    contour = max(contours, key=cv2.contourArea)
    coords_x = contour[:, 0, 0].tolist()
    coords_y = contour[:, 0, 1].tolist()
else:
    # Fallback: bbox as rectangle polyline
    coords_x = [xmin, xmax, xmax, xmin]
    coords_y = [ymin, ymin, ymax, ymax]
```

### 7. Validate & Write Output
- Verify masks are polylines (not just rectangles with 4 points).
- Copy input DataFrame, update the 6 columns, preserve all others.
- `result_df.to_csv(args.output_path, index=False)` — match input CSV format.

---

## Common Pitfalls (Both Task Families)
- ❌ Over-planning: spending >5 min on exploration without writing code.
- ❌ Hardcoding paths instead of using argparse.
- ❌ Resolving segmentation overlaps via erosion or post-polygon — do it at raster level.
- ❌ `n_labels > 1` for connected components — use `n_labels > 2`.
- ❌ `multimask_output=True` with box prompts — use `False` for single masks.
- ❌ Calling `set_image()` more than once — wasteful.
- ❌ Building decompress before compress is validated — can't test without real shard output.

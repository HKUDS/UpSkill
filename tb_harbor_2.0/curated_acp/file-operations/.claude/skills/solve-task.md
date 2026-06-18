# solve-task — File Operations Skill

Unified skill for file reading and transformation tasks. Identify the task type below, then follow the corresponding checklist.

---

## Type A: Gcode Text Extraction

**Goal:** Extract embedded text from a PrusaSlicer gcode file and write it as plain text.

### Checklist

- [ ] **Read the file directly** — use `head -200 /app/text.gcode` or the Read tool. Gcode is plain text; do NOT parse toolpath coordinates.
- [ ] **Search for text in comments** (in order):
  - `grep -i 'emboss' /app/text.gcode`
  - `grep ';.*".*"' /app/text.gcode | head -20`
  - `grep '^;' /app/text.gcode | head -100`
  - Read the first 100–200 lines manually
- [ ] **Identify the text string** — PrusaSlicer embeds it as `; Embossed text: "YOUR TEXT"` or labels the object in header comments
- [ ] **If not found in headers**, check layer-change comments: `grep -i 'text\|emboss' /app/text.gcode`
- [ ] **Write ONLY the text string** to `/app/out.txt`: `echo "the text" > /app/out.txt`
  - No preamble, no analysis, no geometry description, no dimensions
- [ ] **Verify:** `cat /app/out.txt` — confirm it contains ONLY the text, matching the gcode comment

### Common Failure: Geometry Analysis
The text is in a comment line. Parsing G0/G1 coordinates, describing shapes, or tracing toolpaths is wasted effort and will produce wrong output.

---

## Type B: Vim Macro CSV Transformation

**Goal:** Transform a large CSV file using headless Vim macros with a keystroke budget.

### Phase 1: Understand the Diff

- [ ] **Read first 5 lines of input.csv** — note column count, delimiter, whitespace
- [ ] **Read first 5 lines of expected.csv** — note column order, delimiters, casing, added/dropped columns
- [ ] **Articulate the full transformation** in plain English before touching Vim:
  - Delimiter change? Whitespace trim? Case change? Column reorder? Literal appends?
- [ ] **Check the last column** — is it a literal (like `OK`) or a transformed column?

### Phase 2: Design 3 Macros

**One concern per macro.** Split the work:

| Macro | Typical Role | Example |
|-------|-------------|---------|
| `a` | Delimiter + whitespace | `:s/\v\s*,\s*/;/g^M` (17 ks) |
| `b` | Casing | `gUU` (3 ks) |
| `c` | Column reorder + literal | `:s/\v^([^;]*);([^;]*);([^;]*);(.*)$/\3;\2;\1;OK/^M` (~53 ks) |

- [ ] **Use bare `:s/` (NOT `:%s/`)** — `:%normal!` already iterates lines; `%` causes O(n²)
- [ ] **Count every keystroke** — `^M` counts as 1; total must be < 200 across all 3 macros
- [ ] **Macros must be non-empty and distinct** — each register does something different
- [ ] **Design assuming sequential execution** — macro `a` output is macro `b` input, etc.

### Phase 3: Write the Script

- [ ] **Script path:** `/app/apply_macros.vim`
- [ ] **Allowed commands only:** `call setreg()`, `:%normal!`, `:wq`
- [ ] **No Vimscript functions, shell escapes, or scripting languages** in macros
- [ ] **Single-quoted `setreg()` calls preferred** — avoids double-escaping backslashes:
  ```vim
  call setreg('a', ':s/\v\s*,\s*/;/g^M')   " ^M = literal 0x0D byte
  call setreg('b', 'gUU')
  call setreg('c', ':s/\v^([^;]*);([^;]*);([^;]*);(.*)$/\3;\2;\1;OK/^M')
  ```
  If using double quotes, escape backslashes: `\\v`, `\\s`, `\\3`, and use `\<CR>` for carriage return.

### Phase 4: Test and Verify

- [ ] **Copy input first** (script edits in-place): `cp /app/input.csv /app/test_input.csv`
- [ ] **Run:** `vim -Nu NONE -n -Es /app/test_input.csv -S /app/apply_macros.vim`
- [ ] **Check exit:** `echo "exit=$?"` — must be 0
- [ ] **Diff:** `diff /app/test_input.csv /app/expected.csv && echo PASS || echo FAIL`
- [ ] **Count keystrokes** (before transformation, on a copy):
  ```bash
  vim -Nu NONE -n -Es -c 'echo strlen(getreg("a")) + strlen(getreg("b")) + strlen(getreg("c"))' -c 'q' /app/input.csv
  ```

### Common Pitfalls
| Mistake | Fix |
|---------|-----|
| `:%s/` inside macro (O(n²)) | Use bare `:s/` |
| `^M` typed as two characters | Insert literal 0x0D with `<C-v><CR>` |
| Backslashes not escaped in double-quoted `setreg()` | Use single quotes, or double-escape |
| Macros executed in wrong order | Design assuming sequential order: a → b → c |

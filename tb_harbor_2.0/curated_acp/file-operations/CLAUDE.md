# CLAUDE.md — File Operations

## Gcode Text Extraction

Gcode from PrusaSlicer is **plain text**. Embossed text lives in comments — do NOT parse coordinates or reverse-engineer geometry.

### Approach
1. Read the first 200 lines: `head -200 file.gcode` or use the Read tool
2. Search for the text in comments:
   - `grep -i 'emboss' file.gcode`
   - `grep ';.*".*"' file.gcode | head -20`
   - `grep '^;' file.gcode | head -100`
3. PrusaSlicer typically writes: `; Embossed text: "YOUR TEXT HERE"`
4. Write **only** the text string to the output file — no preamble, no geometry

### Anti-Patterns
- ❌ Parsing G0/G1 coordinates or describing shapes
- ❌ Writing narrative summaries instead of the raw text string
- ❌ Overthinking: the answer is in a comment, not the toolpath

---

## CSV Transformation with Headless Vim

Transform large CSV files (up to 1M rows) using Vim macros with **keystroke budgets** (< 200 total).

### Workflow
```
1. Read input.csv + expected.csv (first 5–10 lines) → understand the diff
2. Design 3 macros (registers a, b, c), each doing ONE transformation concern
3. Write /app/apply_macros.vim with setreg() + %normal! + :wq
4. Test: vim -Nu NONE -n -Es input.csv -S apply_macros.vim
5. Verify: diff input.csv expected.csv
```

### Macro Design Rules

| Macro | Typical Role | Example |
|-------|-------------|---------|
| `a` | Delimiter + whitespace | `:s/\v\s*,\s*/;/g` |
| `b` | Casing | `gUU` (3 ks) or `:s/.*/\U&/` (11 ks) |
| `c` | Column reorder + literal append | `:s/\v^([^;]*);([^;]*);([^;]*);(.*)$/\3;\2;\1;OK/` |

**Critical rules:**
- **Use bare `:s/` (NOT `:%s/`)** — `:%normal!` already iterates every line; `%` inside causes O(n²)
- **One concern per macro** — split delimiter, casing, and reorder into separate registers
- **`:%normal!` with `!`** — prevents user mappings from interfering
- **`^M` must be a literal carriage return** (byte 0x0D), typed via `<C-v><CR>`, not caret+M

### setreg() Escaping
- **Single-quoted strings (recommended):** `setreg('a', ':s/\v\s*,\s*/;/g^M')` — no double-escaping; `^M` is a literal 0x0D byte
- **Double-quoted strings:** backslashes must be escaped: `\\v`, `\\s`, `\\3`, etc.; use `\<CR>` for carriage return

### Vim Invocation
```bash
vim -Nu NONE -n -Es /app/input.csv -S /app/apply_macros.vim
```
| Flag | Purpose |
|------|---------|
| `-N` | nocompatible (modern behavior) |
| `-u NONE` | no vimrc (reproducible) |
| `-n` | no swap file |
| `-E` | improved Ex mode (silent batch) |
| `-s` | silent |
| `-S` | source script |

### Keystroke Reference
| Content | Count |
|---------|-------|
| `:s/\v\s*,\s*/;/g^M` | 17 |
| `gUU` | 3 |
| `:s/.*/\U&/^M` | 11 |
| `:s/\v^\s+//^M` | 11 |
| `:s/\v\s+$//^M` | 11 |
| Column reverse + OK append | ~53 |

### Script Template
```vim
" Macro a: delimiter + whitespace trim
call setreg('a', ":s/\\v\\s*,\\s*/;/g\<CR>")
" Macro b: uppercase
call setreg('b', "gUU")
" Macro c: reverse cols + literal OK
call setreg('c', ":s/\\v^([^;]*);([^;]*);([^;]*);(.*)$/\\3;\\2;\\1;OK/\<CR>")
:%normal! @a
:%normal! @b
:%normal! @c
:wq
```

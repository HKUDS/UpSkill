---
name: solve-scientific-computing-task
description: Unified skill for solving scientific computing tasks — bioinformatics, Python modernization, data analysis
metadata:
  type: skill
  category: scientific-computing
---

# solve-scientific-computing-task

Use this skill for any task in the scientific-computing category: bioinformatics
(primer design, Tm calculation, sequence analysis), legacy Python 2→3 modernization,
or data analysis with numpy/pandas/scipy.

---

## Phase 1: READ — Understand Before Acting

1. **Inventory inputs.** List every file the task depends on: source code, data files (CSV,
   FASTA, etc.), config files (INI, YAML, JSON). Read them all before writing anything.
2. **Identify the domain.** Is this bioinformatics? Python modernization? Data analysis?
   The domain determines which rules apply (see Domain Quick Reference below).
3. **Note the output spec.** What exact format must the output take? Is there a required
   precision (`:.1f`), suffix (`°C`), or delimiter? Record it verbatim.

## Phase 2: MAP — Systematic Execution

### For Python Modernization Tasks

1. Run the legacy-Python-2 grep sweep:
   ```bash
   grep -nE 'print [^(]|iteritems|has_key|unicode|basestring|raw_input|execfile|file\(|xrange' <script>
   ```
2. Map every hit to its Python 3 equivalent using the migration table in CLAUDE.md.
3. Write the modernized script, preferring `pathlib.Path`, `pandas`, and `configparser`.
4. Re-run the grep on the new script — it must return nothing.

### For Bioinformatics / Primer Design Tasks

1. Identify the annealing portion of each forward primer (the 3' region that base-pairs
   with the template). 5' extensions (insertions, tags, overhangs) are NOT annealing.
2. Extract it: `primer[-annealing_len:]`
3. Compute Tm using ONLY the annealing portion:
   ```bash
   oligotm -tp 1 -sc 1 -mv 50 -dv 2 -n 0.8 -d 500 <annealing-portion>
   ```
   These flags are exact. Do not modify them.
4. Print both the full primer and the substring sent to oligotm for visual confirmation.

### For Data Analysis Tasks

1. Read data with `pandas.read_csv(path, encoding="utf-8")`.
2. Check dtypes before grouping/aggregating — numeric parsing of categorical columns
   (like station IDs) is a silent bug.
3. Use `numpy` for array operations, `scipy` for statistical functions.

## Phase 3: VERIFY — Independent Confirmation

1. **Run against real data.** Never trust that the script "should work" — execute it
   with the actual input files.
2. **Verify output format.** Does it match the spec character-for-character?
   Check precision, suffixes, delimiters, and Unicode.
3. **Independently re-verify tool output.** For oligotm: call it a second time from a
   separate verification script. For modernized scripts: run the grep sweep again.
4. **Minimize.** Before declaring done, ask: can this be achieved with fewer primers,
   fewer dependencies, or fewer steps?

---

## Domain Quick Reference

### Bioinformatics
- **Tm calculation:** annealing portion only → `oligotm -tp 1 -sc 1 -mv 50 -dv 2 -n 0.8 -d 500`
- **Forward primers:** `primer[-annealing_len:]` (3' end)
- **Reverse primers:** full primer (no 5' extensions in Q5 SDM)
- **Checklist:** extract → compute → verify independently → minimize pairs

### Python Modernization
- **Grep sweep:** `print [^(]|iteritems|has_key|unicode|basestring|raw_input|execfile|file\(|xrange`
- **ConfigParser:** fall back to `read_string(path.read_text())` if `read(Path)` fails
- **CSV:** always `encoding="utf-8"`, always check dtypes after `read_csv`
- **Output:** match format exactly, including Unicode (`°C`)

### Data Analysis
- **Stack:** numpy + pandas + scipy (prefer scipy over matplotlib when only one needed)
- **Versions:** `numpy>=1.20`, `pandas>=1.3`, `scipy>=1.7`

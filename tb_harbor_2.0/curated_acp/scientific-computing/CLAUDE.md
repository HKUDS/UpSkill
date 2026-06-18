# CLAUDE.md — Scientific Computing

## Category Overview

This package covers bioinformatics (primer design, Tm calculation, sequence analysis) and
legacy-science-code modernization (Python 2→3, dependency upgrades, output-preserving rewrites).
The unifying principle: **read first, execute systematically, verify last.**

---

## General Principles

1. **Read before writing.** Inspect input data, config files, and legacy code before producing a
   single line of output. Data schemas and config formats vary; assumptions break silently.
2. **Verify independently.** Run a verification script that exercises the real tool/script against
   real data before declaring success. Do not trust your own output without a second call.
3. **Minimize scope.** Before finalizing, ask: can this be done with fewer steps / fewer
   primers / fewer dependencies? Complexity is the enemy of reproducibility.

---

## Python 2 → 3 Modernization

### Migration Table

| Legacy Pattern | Modern Replacement |
|---|---|
| `ConfigParser.SafeConfigParser` | `configparser.ConfigParser` |
| `os.path` / string paths | `pathlib.Path` |
| `print` statement | `print()` function |
| `open(file, "rb")` / manual CSV parsing | `pandas.read_csv(Path, encoding="utf-8")` |
| `file()` builtin | `open()` |
| `iteritems()` | `items()` |
| `has_key()` | `in` operator |
| `unicode` / `basestring` | `str` |
| `raw_input()` | `input()` |
| `execfile()` | `exec(open(f).read())` |
| `xrange()` | `range()` |

### Workflow

1. **Read** the legacy script, its input data, and any config files.
2. **Grep** for Python 2 remnants:
   ```bash
   grep -nE 'print [^(]|iteritems|has_key|unicode|basestring|raw_input|execfile|file\(|xrange' <script>
   ```
3. **Map** every legacy construct to its Python 3 equivalent before writing.
4. **Verify** by running the new script against real data and re-running the grep —
   it must return nothing. Confirm output format matches the spec exactly.

### Dependency Baseline

Prefer `numpy>=1.20`, `pandas>=1.3`, `scipy>=1.7` for data-heavy scripts.
Use `scipy` over `matplotlib` when only one is needed — it's lighter.

### Pitfalls

- `configparser.ConfigParser.read()` may not accept `pathlib.Path` — use
  `config.read_string(path.read_text())` as a fallback.
- Pandas `groupby` on string columns: verify dtypes — station IDs parsed as numeric
  will silently break grouping.
- Always pass `encoding="utf-8"` when reading CSVs with pandas.
- Output format must match the spec exactly, including Unicode characters like `°C`.

---

## Bioinformatics: Primer Design & Tm Calculation

### Core Rule: Tm on Annealing Portion Only

When computing primer Tm, only the annealing portion goes to `oligotm` — never the
full primer with 5' extensions. The 5' insertion does not anneal to the template;
it hangs off as an overhang. Including it inflates Tm by 10–20°C.

**How to apply:**
- Forward primer: `primer[-annealing_len:]` (the 3' end that anneals)
- Reverse primer: entire primer (reverse primers in Q5 SDM don't have 5' extensions)

Always print both the full primer and the substring sent to oligotm so you can
visually confirm the extraction.

### oligotm Invocation

```bash
oligotm -tp 1 -sc 1 -mv 50 -dv 2 -n 0.8 -d 500 <annealing-portion>
```

These flags are exact and non-negotiable. Do not add, remove, or reorder them.

### Design Checklist

- [ ] Annealing portion extracted (forward primer only)
- [ ] Exact oligotm flags used
- [ ] Tm verified with independent oligotm call
- [ ] Asked: can these mutations be covered by fewer primer pairs?

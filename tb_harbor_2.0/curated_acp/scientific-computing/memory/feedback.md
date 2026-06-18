---
name: scientific-computing-feedback
description: Consolidated feedback from scientific-computing tasks — primer Tm rules, Python modernization patterns, verification discipline
metadata:
  type: feedback
---

# Consolidated Feedback — Scientific Computing

## 1. Tm on annealing portion only

**Why:** Including 5' extensions in oligotm inflates Tm by 10–20°C because the
extension does not anneal to the template — it hangs off as an overhang.

**Apply:** Slice forward primers to `primer[-annealing_len:]` before calling
`oligotm -tp 1 -sc 1 -mv 50 -dv 2 -n 0.8 -d 500`. Print both full and sliced
sequences so the extraction is visually confirmed. Reverse primers are used
in full (no 5' extensions in Q5 SDM).

See also: [[verify-before-declaring-success]], [[minimum-primer-pairs]]

## 2. Read-then-write, map-then-migrate, verify-last

**Why:** Skipping the read phase misses edge cases in data schemas and config
formats. Skipping the grep sweep leaves Python 2 remnants. Skipping verification
ships broken code.

**Apply:** (1) Read legacy code + data + config before writing. (2) Run
`grep -nE 'print [^(]|iteritems|has_key|unicode|basestring|raw_input|execfile|file\(|xrange'`
on the legacy file. (3) After writing, run the new script against real data and
re-run the grep — it must return nothing.

See also: [[primer-design-oligotm-tm-calculation]]

## 3. Verify independently, every time

**Why:** Self-consistency is not verification. The same mistake (wrong flags,
wrong slice, wrong format string) will produce the same wrong answer twice if
you don't change the verification method.

**Apply:** Run oligotm from a separate verification script. Run the modernized
script and diff its output against the expected format. Spend one extra command
to confirm — it's cheaper than shipping a broken result.

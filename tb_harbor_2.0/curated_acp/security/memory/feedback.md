---
name: security-task-patterns
description: Consolidated rules for security tasks — archive cracking and CWE vulnerability fixing
metadata:
  type: feedback
---

# Rule 1: Archive Extraction
Always crack password-protected archives with the `*2john → john → extract` pipeline
before trying anything else. Passwords are almost always short and simple (4-digit
years, dictionary words, `admin`, `test`). The `7z` `-o` flag takes NO space:
`-o/tmp/out` not `-o /tmp/out`.

**Why:** This is the canonical CTF workflow — `7z2john.pl` produces a
John-the-Ripper-compatible hash, john cracks short passwords in seconds with
incremental mode, and `7z x -p<PASS>` extracts cleanly. Skipping to exotic
tools wastes time when the password is `1998`.

**How to apply:** find → 7z l → *2john → john --incremental → john --show →
7z x -p -o → cat secret → echo to /app/solution.txt.

# Rule 2: CWE Vulnerability Fixing
When fixing CWE vulnerabilities in Python web frameworks, always follow the
test-driven discovery pattern: run tests first, read the failing test to extract
expected exception type/message, trace to vulnerable code, map to CWE from the
provided list only, write the report BEFORE fixing, add eager input validation at
function entry points raising `ValueError`, then verify all tests pass.

**Why:** The deliberately failing test is the complete specification — it
identifies the vulnerable function, the malicious input, and the exact fix
contract. Guessing the CWE or fix shape without reading the test leads to
mismatches. Writing the report first ensures the vulnerability is documented
even if the fix needs iteration.

**How to apply:** pytest -rA → grep test → read test → grep function →
match CWE from provided list → write /app/report.jsonl → add \r\n\0 checks
with ValueError → pytest -rA to confirm.

See also: [[archive-extraction-workflow]] [[cwe-reference-list]]

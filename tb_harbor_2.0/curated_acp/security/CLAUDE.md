# CLAUDE.md — Security Tasks

## 1. Password-Protected Archive Extraction

When a task requires extracting a secret from a `.7z`, `.zip`, or `.rar` archive,
use the canonical `hash-extract → crack → extract` pipeline.

### Workflow
1. **Locate**: `find /app -type f \( -name "*.7z" -o -name "*.zip" -o -name "*.rar" \)`
2. **Confirm encryption**: `7z l <archive>` — look for `Encrypted = +`. If `-`, skip
   cracking.
3. **Extract hash**: Use the matching `*2john` tool:
   - `.7z` → `/opt/john/run/7z2john.pl`
   - `.zip` → `zip2john`
   - `.rar` → `rar2john`
   - Output to `/tmp/archive.hash`
4. **Crack**: `john --incremental /tmp/archive.hash` (passwords are almost always
   short: 4-digit years, `password`, `admin`, `test`). Fall back to wordlist:
   `john --wordlist=<path> /tmp/archive.hash`.
5. **Show password**: `john --show /tmp/archive.hash`
6. **Extract**:
   - 7z: `7z x <archive> -p<PASS> -o/tmp/extracted/` (NO space after `-o`!)
   - zip: `unzip -P <PASS> <archive> -d /tmp/extracted/`
   - rar: `unrar x -p<PASS> <archive> /tmp/extracted/`
7. **Read & write**: `cat /tmp/extracted/<secret>` then `echo "<word>" > /app/solution.txt`

### Gotchas
- `-o` has no space: `-o/tmp/out` not `-o /tmp/out`
- Find tool paths with `find / -name "7z2john.pl" -o -name "zip2john" 2>/dev/null`
- Wordlist path: `find / -name "rockyou.txt" 2>/dev/null | head -3`
- If archive isn't encrypted, skip steps 3–4 and extract without `-p`

## 2. CWE Vulnerability Fixing (Python Web Frameworks)

Follow the **test-driven discovery pattern** — the failing test is the signal.

### Workflow
1. **Run tests**: `python3 -m pytest -rA 2>&1 | head -60` — find deliberately failing tests
2. **Read the failing test**: grep the test name, read its definition to extract the
   expected exception type and message
3. **Trace to vulnerable code**: grep the functions called in the test
4. **Map to CWE** from the provided list only (never from memory):
   - `\r` / `\n` header injection → CWE-93
   - Missing input validation → CWE-20
5. **Report first**: Write `/app/report.jsonl` with format:
   `{"file_path": "/app/<source>.py", "cwe_id": ["CWE-93"]}` — uppercase, hyphenated
6. **Fix**: Add eager input validation at the start of vulnerable functions — check for
   `\r`, `\n`, `\0`; raise `ValueError` with a descriptive message before any processing
7. **Verify**: `python3 -m pytest -rA` — all tests must pass

### Key Principle
The failing test tells you exactly: which function is vulnerable, what input breaks it,
and what exception to raise. Never guess the CWE or the fix shape — let the test guide you.

## Environment
- `7z` (p7zip) and John the Ripper are pre-installed; check `/opt/john/run/` or PATH
- Wordlists live under `/usr/share/wordlists/`
- `/app` is the working directory for archives, source files, and solution targets
- Python tests use pytest; CWE report format is JSONL (one JSON object per line)

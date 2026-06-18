# Solve Task: Security

Checklist-based skill covering archive cracking and CWE vulnerability fixing.
Follow steps in order; skip only when you have a confirmed result.

---

## A. Extract Secret from Password-Protected Archive

### A1. Find the archive
```bash
find /app -type f \( -name "*.7z" -o -name "*.zip" -o -name "*.rar" \) 2>/dev/null
```
If nothing found: `ls -la /app/` and `file /app/<name>` — files may have nonstandard
extensions but still be archives.

### A2. Confirm encryption
```bash
7z l /app/<archive>
```
- `Encrypted = +` → continue to A3
- `Encrypted = -` → skip to A5 (extract without `-p`)

### A3. Extract the hash
Find the tool first:
```bash
find / -name "7z2john.pl" -o -name "zip2john" -o -name "rar2john" 2>/dev/null
```
Then convert:
```bash
# .7z: /opt/john/run/7z2john.pl /app/<archive> > /tmp/archive.hash
# .zip: zip2john /app/<archive> > /tmp/archive.hash
# .rar: rar2john /app/<archive> > /tmp/archive.hash
```

### A4. Crack the password
Try wordlist first (fast):
```bash
find / -name "rockyou.txt" -o -name "*.lst" 2>/dev/null | head -5
john --wordlist=/path/to/wordlist /tmp/archive.hash
```
If wordlist fails, use incremental (slower, catches short/simple passwords):
```bash
john --incremental /tmp/archive.hash
```
Show the cracked password:
```bash
john --show /tmp/archive.hash | tail -1 | awk -F: '{print $NF}'
```
Manual fallback list (if john doesn't crack quickly): `1998`, `2000`, `2020`, `2024`,
`1234`, `123456`, `password`, `admin`, `test`, `secret`, `flag`, `ctf`.

### A5. Extract the archive
```bash
# 7z — NO space after -o!
7z x /app/<archive> -p<PASSWORD> -o/tmp/extracted/

# zip
unzip -P <PASSWORD> /app/<archive> -d /tmp/extracted/

# rar
unrar x -p<PASSWORD> /app/<archive> /tmp/extracted/
```

### A6. Read the secret and write solution
```bash
ls -la /tmp/extracted/ && find /tmp/extracted/ -type f
cat /tmp/extracted/<secret_file>
echo "<the_word>" > /app/solution.txt && cat /app/solution.txt
```

### A7. Troubleshooting
| Problem | Fix |
|---------|-----|
| `7z2john.pl` missing | `apt-get install -y john` or look in `/opt/john/run/` |
| `john` not found | `apt-get install -y john` or `/opt/john/run/john` |
| No wordlist available | Use `john --incremental` |
| `7z x` errors on `-o` | NO space after `-o`: use `-o/tmp/out` not `-o /tmp/out` |
| Archive not encrypted | Skip A3–A4, extract without `-p` flag |
| Multiple extracted files | Read each one; target is usually `secret_file.txt` |

---

## B. Fix CWE Vulnerabilities in Python Web Code

### B1. Find the failing test
```bash
python3 -m pytest -rA 2>&1 | head -60
```
Look for `FAILED` — this is the intentional signal test.

### B2. Read the test to understand expectations
```bash
grep -n "test_name_here" /app/test_*.py
```
Extract: which function is called, what bad input is passed, what exception is expected,
and the expected error message.

### B3. Trace to the vulnerable code
```bash
grep -n "def vulnerable_function" /app/<source>.py
```
Read the function — identify where input flows without validation.

### B4. Map to the correct CWE
Use ONLY the provided CWE list. Common mappings:
- Header `\r` / `\n` injection → **CWE-93**
- Missing input validation → **CWE-20**

### B5. Write the report BEFORE fixing
```bash
echo '{"file_path": "/app/<source>.py", "cwe_id": ["CWE-93"]}' > /app/report.jsonl
```
Format: uppercase, hyphenated CWE IDs, JSONL (one object per line).

### B6. Apply the fix
Add validation at the **start** of each vulnerable function, before any processing:
```python
def vulnerable_function(header_value):
    for char in '\r\n\0':
        if char in header_value:
            raise ValueError("Invalid character in header value")
    # ... rest of function
```
- Raise `ValueError` (not generic `Exception`) with a descriptive message
- Match the exception type and message the test expects

### B7. Verify all tests pass
```bash
python3 -m pytest -rA
```

### B8. Troubleshooting
| Problem | Fix |
|---------|-----|
| No failing tests visible | Check for skipped tests: `pytest -rA` shows all output |
| Wrong CWE chosen | Re-read the provided CWE list; map by vulnerability type, not by guess |
| Fix doesn't match test | Re-read the test — it specifies exact exception type and message |
| report.jsonl rejected | Validate JSON: single line, double quotes, uppercase CWE-X format |

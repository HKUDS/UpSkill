# Solve Task: Software Engineering

Unified skill for building C projects, image-to-code tasks, GC bug fixes, and git recovery.

---

## 1. Build C Project from Source (No X11)

### Phase 1 — Acquire Source
- [ ] Use distro source when task warns upstream is unreliable: `apt-get source <pkgname>`
- [ ] Verify extraction: `ls <pkgname>-*/` shows source files and a Makefile

### Phase 2 — Understand the Build System
- [ ] **Read the Makefile before editing.** `grep -n 'X11\|XWINGRAPHX\|GRAPHX' Makefile`
- [ ] Identify TWO things: the compile-time `-D` flag AND the link-time `-l` library

### Phase 3 — Disable X11 (Two-Part Edit)
- [ ] Remove the `-D` flag from CFLAGS (e.g., `-DXWINGRAPHX`) — missing this → compile error on X11 headers
- [ ] Remove the `-l` library from linker (e.g., `-lX11`) — missing this → linker failure
- [ ] **Verify both:** grep again, expect zero hits for both patterns

### Phase 4 — Build & Install
- [ ] `make` or `make -C src`; fix any remaining X11 references
- [ ] `cp <binary> /usr/local/bin/<name>` then `chmod 755`
- [ ] `which <name>` returns `/usr/local/bin/<name>`

### Phase 5 — Verify (Three Dimensions)
- [ ] **Functional:** run the task's exact test command
- [ ] **No X11 deps:** `ldd /usr/local/bin/<name> | grep -i x11` returns nothing
- [ ] **Provenance:** `debian/changelog` exists in source tree

---

## 2. Image-to-Code (OCR + Hash Chain)

- [ ] **OCR first:** `tesseract /app/code.png stdout` (fallback: EasyOCR)
- [ ] Parse the hash function, salt constant, and slice notation from OCR output
- [ ] Intermediate hashes → `.digest()`, final output → `.hexdigest()`
- [ ] **Verify prefix** against any hint BEFORE writing to `/app/output.txt`
- [ ] Write **only the hex string** to output file

---

## 3. GC / Bootstrap Bug Fix (Sibling Function Diff)

- [ ] Identify the function to fix and its sibling functions that iterate the same data structure
- [ ] `grep` for sibling functions in the same file; diff their loop bodies
- [ ] Any discrepancy in pointer advancement is the bug
- [ ] Match the pattern used by the majority of siblings (e.g., `p += wh`, not `p += Whsize_hd(hd)`)
- [ ] Rebuild and verify the bootstrap completes

---

## 4. Git Secret Recovery & Purge

- [ ] `git reflog --all` — find orphaned commits (reset/amend doesn't delete, it orphans)
- [ ] `git show <hash> | grep -o 'secret\[[^]]*\]'` — extract the secret
- [ ] Write to `/app/secret.txt` (OUTSIDE the repo)
- [ ] Purge: `git reflog expire --expire=now --all && git gc --prune=now --aggressive`
- [ ] Verify: grep both history AND working tree for the secret pattern

---

## 5. Polyglot C/Python Verification

- [ ] Compile C with `-Wall -Wextra -pedantic -Werror` — zero warnings required
- [ ] Python syntax check: `python3 -c "compile(open(f).read(), f, 'exec')"`
- [ ] Cross-validate: run both interpreters for `n=0,1,2,3,10,20,30`, assert all outputs match

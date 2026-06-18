# Software Engineering — Curated Guidance

## Build C from Source Without X11

Use **distro package source**, not upstream websites. Disable X11 with a **two-part Makefile edit**.

```bash
# 1. Get Debian-packaged source
apt-get source <pkgname>

# 2. Install build deps
apt-get build-dep <pkgname>   # fallback: apt-get install -y gcc make

# 3. Find and remove X11 references (ALWAYS grep first)
grep -n 'X11\|XWINGRAPHX\|GRAPHX' <pkgname>-*/Makefile
# Remove -DXWINGRAPHX from CFLAGS AND -lX11 from the link line

# 4. Build
make -C <pkgname>-*/src

# 5. Install
cp <pkgname>-*/src/<binary> /usr/local/bin/
chmod 755 /usr/local/bin/<binary>
```

**Verify:** `ldd /usr/local/bin/<binary> | grep -i x11` must return nothing. Run the functional test exactly as given. Check `debian/changelog` for source provenance.

## Image-to-Code (OCR + SHA-256)

When given an image of pseudocode, **OCR first — never guess.**

```bash
tesseract /app/code.png stdout    # primary; fallback: EasyOCR
```

For SHA-256 chain tasks: use `.digest()` for intermediate hashes, `.hexdigest()` only for the final output. **Verify the prefix** against any hint before writing.

## OCaml GC: Pool Sweep Pointer Bug

In `runtime/shared_heap.c`, pool-iteration functions (`pool_sweep`, `pool_finalise`, `calc_pool_stats`) must advance by `wh` (slot width), not `Whsize_hd(hd)` (individual object size). When fixing one, **diff against sibling functions** — the correct pattern is already implemented in at least one of them.

## Git Secret Recovery

Commits removed by reset/amend aren't deleted — they're orphaned.

```bash
git reflog --all                                    # find orphaned commit
git show <hash> | grep -o 'secret\[[^]]*\]'         # extract secret
# Write to /app/secret.txt (OUTSIDE the repo)
git reflog expire --expire=now --all && git gc --prune=now --aggressive  # purge
```

## Polyglot C/Python

Single-file polyglot using `#if 0` / `//"""` trick. Key insight: `0 // """` opens a Python triple-quoted string (right operand of floor-div) while `//` hides the rest from C.

```bash
python3 /app/polyglot/main.py.c N
gcc /app/polyglot/main.py.c -o /app/polyglot/cmain -Wall -Wextra -pedantic -Werror
```

**Cross-validate:** run both interpreters for `n in 0 1 2 3 10 20 30` and assert outputs match.

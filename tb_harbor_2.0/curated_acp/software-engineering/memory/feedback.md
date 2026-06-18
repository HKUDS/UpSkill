# Software Engineering — Consolidated Feedback

## X11 Disable Is Always a Two-Part Edit

When building C programs without X11, you MUST remove BOTH the compile-time `-D` flag (e.g., `-DXWINGRAPHX`) AND the link-time `-l` library (e.g., `-lX11`). Missing either causes a different failure: compile error on headers vs. linker failure on library. **Always grep before and after the edit.** Use distro package source (`apt-get source`) instead of upstream websites — it comes pre-patched and ready to build. Verify with `ldd | grep x11` (must be empty) + functional test + source provenance check (`debian/changelog`).

## OCR First, Never Guess

For image-to-code tasks, ALWAYS run `tesseract` or EasyOCR to extract pseudocode text before implementing. For SHA-256 chains: `.digest()` for intermediates, `.hexdigest()` only for final output. **Verify the output prefix matches** any hint before writing to file. Write only the hex string, nothing else.

## Compare Sibling Functions for Loop Bugs

When a GC or bootstrap crashes in C, find sibling functions in the same file that iterate the same data structure. The correct loop pattern is already implemented in at least one of them. Diff their loop bodies — any discrepancy in pointer advancement or bounds checking is the bug. In pool allocation: advance by slot width `wh`, not object size `Whsize_hd(hd)`. [[pool-sweep-pointer-advancement-bug]]

## Git Reset Orphans, Doesn't Delete

Commits removed by reset/amend/rebase persist in the reflog (90 days) and as dangling objects. Recover: `git reflog --all` → `git show <hash> | grep -o 'secret\[[^]]*\]'` → write OUTSIDE the repo. Purge: `git reflog expire --expire=now --all && git gc --prune=now --aggressive`. This preserves reachable SHAs unlike `git filter-branch`. Always verify by grepping both history AND working tree. [[git-leak-recovery]]

## Polyglot Verification Pattern

For polyglot files, compile C with `-Wall -Wextra -pedantic -Werror` (zero warnings), check Python syntax with `compile()`, then cross-validate both interpreters on `n=0,1,2,3,10,20,30` and assert all outputs match exactly.

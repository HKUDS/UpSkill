---
name: system-administration-feedback
description: Consolidated feedback rules for server infrastructure and C compilation tasks
metadata:
  type: feedback
---

# System Administration — Consolidated Feedback

## Incremental Verification (Server Infrastructure)

**Rule**: When setting up multi-component server infrastructure (SSH + Git + Nginx + hooks),
verify each component in isolation before integration testing. Test SSH with a direct `ssh`
command. Test bare repos with `git ls-remote`. Test Nginx with `curl -k`. Test hooks manually
with `echo "...refs/heads/branch" | bash hook`. Then integrate.

**Why**: Multi-component failures have many independent causes. Testing everything at once
makes debugging a needle-in-haystack problem. Isolated verification narrows failures to a
single component.

**How to apply**: Follow the checklist order. Do not skip verification steps. If a verification
fails, fix that component before configuring the next one. [[incremental-verify-git-server-setup]]

## Nginx alias vs root

**Rule**: Use `alias /var/www/dev/` (not `root /var/www/dev`) for subdirectory locations like
`location /dev/`. `root` appends the location path, causing Nginx to look for files at the
wrong path.

**Why**: With `root /var/www/dev` and `location /dev/`, Nginx resolves `/dev/index.html` to
`/var/www/dev/dev/index.html` — a double path that causes 404s. `alias` does a direct path
substitution without appending.

## gcov LDFLAGS Requirement

**Rule**: When compiling C projects with gcov coverage, always pass `LDFLAGS="-lgcov"` in
addition to `CFLAGS="-fprofile-arcs -ftest-coverage -O0 -g"`. Use `./configure` (not raw
`gcc`) for autotools projects.

**Why**: Without `-lgcov`, the binary compiles successfully but the coverage runtime is never
linked, so `.gcda` files are silently never emitted. `-O0` prevents compiler optimizations
from inlining branches and skewing coverage data. [[c-coverage-pitfalls]] [[autotools-gcov-pattern]]

## Ownership and Directory Pre-creation

**Rule**: Always verify file/directory ownership matches the runtime user, and pre-create
directories that daemons expect (`/var/run/sshd`, SSL cert dirs, deployment docroots).

**Why**: Services fail silently or with cryptic errors when they can't write to their runtime
directories. SSH won't start without `/var/run/sshd`. Nginx won't start if SSL files don't
exist. Git hooks fail if the pushing user doesn't own the work-tree directories.

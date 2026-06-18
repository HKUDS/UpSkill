# System Administration — Solve Task Skill

Unified skill for setting up multi-component server infrastructure and compiling C projects with coverage instrumentation. Follow the checklist-driven, incremental-verify pattern.

## Server Infrastructure Tasks

Use this flow for any multi-service setup (Git, SSH, Nginx, hooks, etc.).

### Phase 1: Prerequisites
- [ ] Install packages: `apt-get update && apt-get install -y <pkg1> <pkg2> ...`
- [ ] Create required runtime directories (e.g., `/var/run/sshd`, `/etc/nginx/ssl`)
- [ ] Kill any stale service processes: `pkill <service> 2>/dev/null` before starting fresh

### Phase 2: Component Setup (one at a time)
For each component, follow this sub-cycle:
1. **Configure** — write config files, set permissions
2. **Start** — launch the service (prefer direct binary: `/usr/sbin/sshd`, `nginx`)
3. **Verify in isolation** — test that specific component before moving on
   - SSH: `ssh user@localhost echo OK`
   - Git repo: `git ls-remote git@localhost:/path`
   - Nginx: `curl -k https://localhost:PORT/`
   - Hook: `echo "old new refs/heads/branch" | bash /path/hooks/post-receive`
4. **Fix ownership** — ensure runtime user owns all served directories

### Phase 3: Integration
- [ ] Wire components together (hooks, deploy dirs, symlinks)
- [ ] Test end-to-end with measured timing: `time <operation>`
- [ ] Push one branch at a time, verify each endpoint independently

### SSH Configuration
- Set `PasswordAuthentication yes` and `UsePAM yes` in `sshd_config`
- For testing, configure `StrictHostKeyChecking no` in `~/.ssh/config`
- Pre-create `/var/run/sshd` in minimal container images

### Nginx Configuration
- **Critical rule**: `alias` for subdirectory locations, `root` for `/`
- Generate SSL certs **before** the Nginx config references them
- Test config syntax: `nginx -t` before starting
- Remove default site: `rm -f /etc/nginx/sites-enabled/default`

### Git Post-Receive Hook Template
```bash
#!/bin/bash
DEPLOY_MAIN=/var/www/main
DEPLOY_DEV=/var/www/dev

while read oldrev newrev refname; do
    branch=$(basename "$refname")
    case "$branch" in
        main) rm -rf "$DEPLOY_MAIN"/*
              git --work-tree="$DEPLOY_MAIN" --git-dir=/git/project checkout -f main ;;
        dev)  rm -rf "$DEPLOY_DEV"/*
              git --work-tree="$DEPLOY_DEV" --git-dir=/git/project checkout -f dev ;;
    esac
done
```
Make executable: `chmod +x /git/project/hooks/post-receive`

### Troubleshooting Quick Reference
| Symptom | Cause | Fix |
|---------|-------|-----|
| SSH connection refused | sshd not running | `/usr/sbin/sshd` |
| Permission denied (publickey) | Password auth off | Set `PasswordAuthentication yes` |
| Git: not a repository | Wrong path or not bare | `git init --bare /path` |
| Hook permission denied | Not executable | `chmod +x hooks/post-receive` |
| Nginx 404 on subdirectory | Used `root` not `alias` | Switch to `alias /path/` |
| Nginx SSL error | Cert files missing | Generate certs before config |
| Branch not deploying | Hook doesn't match branch name | Check `basename "$refname"` output |

## C Compilation with gcov Tasks

### Build Recipe
```bash
# Extract
tar -xzf vendor/<project>.tar.gz -C /tmp/build && cd /tmp/build/*/

# Configure with instrumentation flags
./configure --prefix=/app/<project>/build \
  CFLAGS="-fprofile-arcs -ftest-coverage -O0 -g" \
  LDFLAGS="-lgcov"

# Build and install
make -j$(nproc) && make install

# Link into PATH
ln -sf /app/<project>/build/bin/<binary> /usr/local/bin/<binary>
```

### Verification Checklist
- [ ] `strings /path/to/binary | grep -c gcda` returns > 0 (confirms instrumentation linked)
- [ ] Run the binary to generate `.gcda` files
- [ ] `find . -name '*.gcda'` confirms coverage data was emitted
- [ ] `gcov *.c` or `lcov` to produce reports

### Critical Flags
| Flag | Purpose | Omission Effect |
|------|---------|-----------------|
| `-fprofile-arcs` | Instrument branches | No coverage data |
| `-ftest-coverage` | Generate `.gcno` files | No coverage data |
| `-O0` | Disable optimization | Misleading coverage (inlined branches) |
| `-g` | Debug symbols | Harder to map coverage to source |
| `-lgcov` (LDFLAGS) | Link coverage runtime | **Silent failure**: compiles but emits zero `.gcda` |

## Universal Verification Pattern

1. Test each component in isolation before integration
2. Use explicit measurement (`time`, `strings | grep -c`, direct `curl`)
3. Run automation scripts manually first to catch syntax errors
4. Check ownership and permissions at every step
5. When a test fails, fix that component before proceeding — never debug the whole chain at once

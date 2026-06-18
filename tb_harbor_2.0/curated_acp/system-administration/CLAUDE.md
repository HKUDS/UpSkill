# System Administration — CLAUDE.md

Project guidance for server infrastructure setup and C toolchain tasks.

## Server Infrastructure (Git + SSH + Nginx)

Pattern: multi-component server tasks require **incremental verification** — test each layer
independently before end-to-end integration. Order: SSH → bare repo → Nginx → hooks → push.

### SSH with Password Auth
- Edit `/etc/ssh/sshd_config`: `PasswordAuthentication yes`, `UsePAM yes`
- Set password: `echo 'user:password' | chpasswd`
- Start: `/usr/sbin/sshd` (not `service ssh restart` — may fail in minimal containers)
- Pre-create `/var/run/sshd` if missing
- **Verify**: `ssh -o StrictHostKeyChecking=no user@localhost echo OK`

### Bare Git Repo + Post-Receive Hook
- `git init --bare /git/project` and ensure SSH user owns it
- **Verify**: `git ls-remote git@localhost:/git/project` (empty, no error)
- Hook: parse `while read oldrev newrev refname`, extract branch via `basename "$refname"`
- Checkout: `git --work-tree="$DEPLOY" --git-dir=/git/project checkout -f $branch`
- Clear contents only: `rm -rf "$DEPLOY"/*` — never delete the directory itself
- `chmod +x` the hook
- **Verify hook manually**: `echo "old new refs/heads/main" | bash /git/project/hooks/post-receive`

### Nginx + SSL
- Generate cert **before** configuring Nginx: `openssl req -x509 -nodes -days 365 -newkey rsa:2048`
- **Critical**: Use `alias` for subdirectory locations (e.g., `/dev/`), `root` for `/`
  - `root /var/www/dev` with `location /dev/` → Nginx looks for `/var/www/dev/dev/` (WRONG)
  - `alias /var/www/dev/` with `location /dev/` → Nginx looks for `/var/www/dev/` (CORRECT)
- Remove default site, test with `nginx -t`, kill stale processes with `pkill nginx`
- **Verify**: `curl -k https://localhost:8443/` (connection refused = Nginx not running)

### SSH Config for Testing
```
Host localhost
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
```
Or inline: `GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" git push`

## C Compilation with gcov (Autotools)

Always pass **three** flag sets:
- `CFLAGS="-fprofile-arcs -ftest-coverage -O0 -g"` — compile-time instrumentation
- `LDFLAGS="-lgcov"` — link-time runtime support (without this: zero `.gcda` output, silent failure)
- Use `./configure --prefix=...` (not raw `gcc`) — handles headers, libs, pkg-config

Build recipe:
```bash
tar -xzf vendor/sqlite-fossil-release.tar.gz -C /tmp/sqlite-src && cd /tmp/sqlite-src/*/
./configure --prefix=/app/sqlite/build \
  CFLAGS="-fprofile-arcs -ftest-coverage -O0 -g" LDFLAGS="-lgcov"
make -j$(nproc) && make install
ln -sf /app/sqlite/build/bin/sqlite3 /usr/local/bin/sqlite3
```
**Verify**: `strings /app/sqlite/build/bin/sqlite3 | grep -c gcda` must return > 0.

## Universal Rules

1. **Incremental verification**: Test each component in isolation before integration.
2. **Explicit measurement**: Time operations (`time git push`, `time make`) — never assume.
3. **Check ownership**: File/directory ownership must match the runtime user (SSH user, Nginx worker).
4. **Pre-create directories**: Many services silently fail on missing paths (`/var/run/sshd`, SSL dirs).
5. **Kill stale processes**: `pkill` before restarting daemons in container/minimal environments.
6. **Test manually before automating**: Run hook scripts by hand, curl endpoints directly, check `strings` output.

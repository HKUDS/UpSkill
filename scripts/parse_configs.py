#!/usr/bin/env python3
"""Parse CC-generated config output into ACP (AgentBrew Configuration Package).

Modes:
  New:    python3 parse_configs.py <log> <acp_dir> --task-name <name>
  Merge:  python3 parse_configs.py <log> <acp_dir> --task-name <name> --merge

In merge mode, new notes are appended/merged into the existing ACP.
CLAUDE.md gets a per-task section. Skills are added (skip duplicates).
Memory is merged by frontmatter name field.
"""

import re, sys, os, json, time
from pathlib import Path


def parse_marked_files(text: str) -> dict[str, str]:
    """Parse BEGIN_FILE/END_FILE markers (flexible format). Returns {relpath: content}."""
    # Match: ===BEGIN_FILE: path=== or BEGIN_FILE: path (with or without ===)
    # Normalize slashes in path, strip /app/ prefix
    pattern = re.compile(
        r'(?:===)?\s*BEGIN_FILE:\s*(.+?)\s*(?:===)?\s*\n(.*?)(?:===)?\s*END_FILE:\s*\1\s*(?:===)?',
        re.DOTALL,
    )
    result = {}
    for m in pattern.finditer(text):
        path = m.group(1).strip()
        # Normalize: remove leading /app/ or /workspace/ prefixes
        path = re.sub(r'^(/app/|/workspace/)', '', path)
        path = re.sub(r'^\./', '', path)
        content = m.group(2).strip()
        result[path] = content
    return result


def write_file(dest: Path, content: str):
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(content + "\n")


def new_acp(files: dict, base: Path, task_name: str):
    """Create fresh ACP from parsed files."""
    created = {}
    for relpath, content in files.items():
        write_file(base / relpath, content)
        created[relpath] = True
        print(f"  [parse] wrote {relpath} ({len(content)} chars)")
    return created


def merge_acp(files: dict, base: Path, task_name: str):
    """Merge new files into existing ACP."""
    created = {}

    # --- CLAUDE.md: append per-task section ---
    if 'CLAUDE.md' in files:
        claude_path = base / 'CLAUDE.md'
        existing = claude_path.read_text() if claude_path.exists() else ""
        new_section = f"\n\n---\n## Task: {task_name}\n\n{files['CLAUDE.md']}"
        claude_path.write_text(existing + new_section)
        print(f"  [merge] CLAUDE.md: appended section for {task_name}")
        created['CLAUDE.md'] = True

    # --- Skills: add new, skip duplicates ---
    for relpath, content in files.items():
        if not relpath.startswith('.claude/skills/'):
            continue
        dest = base / relpath
        if dest.exists():
            print(f"  [merge] {relpath}: already exists, skipped")
        else:
            write_file(dest, content)
            print(f"  [merge] {relpath}: added")
        created[relpath] = True

    # --- Memory: merge by name field in frontmatter ---
    for relpath, content in files.items():
        if not relpath.startswith('memory/'):
            continue
        # Extract name from frontmatter
        name_match = re.search(r'name:\s*(.+)', content)
        if name_match:
            name = name_match.group(1).strip()
            dest = base / f'memory/{name}.md'
        else:
            dest = base / relpath

        if dest.exists():
            print(f"  [merge] {dest.name}: updated (merge by name)")
        else:
            print(f"  [merge] {dest.name}: added (new)")
        write_file(dest, content)
        created[str(dest.relative_to(base))] = True

    return created


def write_manifest(base: Path, created: dict, task_name: str, mode: str):
    """Write/update manifest.yaml."""
    manifest_path = base / 'manifest.yaml'
    ts = time.strftime("%Y-%m-%dT%H:%M:%S")

    if mode == 'merge' and manifest_path.exists():
        existing = manifest_path.read_text()
        # Append task record
        record = f"\n  - task: {task_name}\n    at: {ts}\n    files: {list(created.keys())}"
        manifest_path.write_text(existing + record)
    else:
        content = f"""# ACP Manifest
package: {base.name}
mode: cumulative
created: {ts}
tasks:
  - {task_name} (created {ts})
files:
"""
        for f in sorted(created.keys()):
            content += f"  - {f}\n"
        manifest_path.write_text(content)
    print(f"  [parse] manifest updated ({mode})")


# ---- main ----
if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <log> <acp_dir> --task-name <n> [--merge]")
        sys.exit(1)

    log_path = sys.argv[1]
    base = Path(sys.argv[2])
    task_name = ""
    merge_mode = False

    args = sys.argv[3:]
    for i, a in enumerate(args):
        if a == '--task-name' and i + 1 < len(args):
            task_name = args[i + 1]
        elif a == '--merge':
            merge_mode = True

    text = open(log_path).read()
    files = parse_marked_files(text)

    if not files:
        print("  [parse] WARNING: no marked files, trying fallback...")
        # Try alternative marker format: BEGIN_FILE: path (without ===)
        alt_pattern = re.compile(
            r'BEGIN_FILE:\s*(.+?)\s*\n(.*?)(?:END_FILE|$)',
            re.DOTALL,
        )
        for m in alt_pattern.finditer(text):
            path = m.group(1).strip()
            path = re.sub(r'^(/app/|/workspace/|\./)', '', path)
            content = m.group(2).strip()
            files[path] = content
            print(f"  [parse:alt] found {path} ({len(content)} chars)")

    if not files:
        # Last resort: look for markdown sections
        sections = re.split(r"\n(?=#{1,3}\s+)", text)
        for s in sections:
            s = s.strip()
            if not s: continue
            header = s.split('\n')[0].strip('#').strip().lower()
            body = '\n'.join(s.split('\n')[1:]).strip()
            if not body: continue
            if 'claude.md' in header:
                files['CLAUDE.md'] = body
            elif 'skill' in header or 'solve-task' in header:
                files['.claude/skills/solve-task.md'] = body
            elif 'memory' in header or 'feedback' in header:
                files['memory/feedback.md'] = body

        if files:
            print(f"  [parse:fallback] found {len(files)} file(s)")

    if not files:
        print("  [parse] WARNING: no marked files found. First 200 chars:")
        print(text[:200])
        # Don't exit with error — caller may be in a pipeline

    base.mkdir(parents=True, exist_ok=True)

    if merge_mode and base.joinpath('CLAUDE.md').exists():
        print(f"  [parse] Merging into existing ACP: {base}")
        created = merge_acp(files, base, task_name)
    else:
        if merge_mode:
            print(f"  [parse] Creating new ACP (merge mode, no existing): {base}")
        created = new_acp(files, base, task_name)

    write_manifest(base, created, task_name, 'merge' if merge_mode else 'new')
    print(f"  [parse] Done: {len(created)} files -> {base}")

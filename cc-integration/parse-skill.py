#!/usr/bin/env python3
"""Parse CC-generated config output into a SKILL.md file.

Usage:
  python3 parse-skill.py <log> <skill_dir> --task-name <name>
"""
import re, sys
from pathlib import Path


def parse_marked_files(text: str) -> dict[str, str]:
    """Parse ===BEGIN_FILE: path=== / ===END_FILE: path=== markers."""
    pattern = re.compile(
        r'(?:===)?\s*BEGIN_FILE:\s*(.+?)\s*(?:===)?\s*\n(.*?)(?:===)?\s*END_FILE:\s*\1\s*(?:===)?',
        re.DOTALL,
    )
    result = {}
    for m in pattern.finditer(text):
        path = m.group(1).strip()
        path = re.sub(r'^(/app/|/workspace/|\./)', '', path)
        content = m.group(2).strip()
        if content:
            result[path] = content
    return result


def write_file(dest: Path, content: str, base: Path):
    resolved = (base / dest).resolve()
    if not str(resolved).startswith(str(base.resolve())):
        print(f"  [parse] REJECTED (path traversal): {dest}")
        return
    resolved.parent.mkdir(parents=True, exist_ok=True)
    resolved.write_text(content + "\n")


if __name__ == "__main__":
    if len(sys.argv) < 3 or sys.argv[1] in ('--help', '-h'):
        print(f"Usage: {sys.argv[0]} <log> <skill_dir> --task-name <name>")
        print()
        print("Parse CC-generated SKILL.md output with BEGIN_FILE/END_FILE markers.")
        sys.exit(0)

    log_path = sys.argv[1]
    base = Path(sys.argv[2])
    try:
        idx = sys.argv.index('--task-name')
        task_name = sys.argv[idx + 1] if idx + 1 < len(sys.argv) else "unknown"
    except (ValueError, IndexError):
        task_name = "unknown"

    text = open(log_path).read()
    files = parse_marked_files(text)

    if not files:
        # Fallback: try without ===
        alt = re.compile(r'BEGIN_FILE:\s*(.+?)\s*\n(.*?)(?:END_FILE|$)', re.DOTALL)
        for m in alt.finditer(text):
            path = m.group(1).strip()
            path = re.sub(r'^(/app/|/workspace/|\./)', '', path)
            content = m.group(2).strip()
            if content:
                files[path] = content
                print(f"  [parse:alt] found {path} ({len(content)} chars)")

    if not files:
        print("  [parse] WARNING: no marked files found. First 200 chars:")
        print(text[:200])

    base.mkdir(parents=True, exist_ok=True)

    # Extract description
    desc_match = re.search(r'===?\s*SKILL_DESCRIPTION\s*===?\s*\n?(.+?)(?:===|$)', text, re.DOTALL)
    description = desc_match.group(1).strip() if desc_match else ""
    if not description:
        for pattern in [r'##\s*Summary\s*\n(.+?)(?:\n##|\n===|$)', r'##\s*Description\s*\n(.+?)(?:\n##|\n===|$)']:
            dm = re.search(pattern, text, re.DOTALL)
            if dm:
                description = dm.group(1).strip()
                break
    if not description:
        prefix = text.split('===BEGIN_FILE:')[0] if '===BEGIN_FILE:' in text else text[:500]
        lines = [l.strip() for l in prefix.split('\n') if l.strip() and not l.startswith('#') and not l.startswith('===')]
        if lines:
            description = lines[-1][:200]

    if description:
        (base / 'description.txt').write_text(description + "\n")
        print(f"  [parse] description: {description[:120]}...")

    # Write SKILL.md
    if 'SKILL.md' in files:
        write_file(Path('SKILL.md'), files['SKILL.md'], base)
        print(f"  [parse] wrote SKILL.md ({len(files['SKILL.md'])} chars)")
        print(f"  [parse] Done: SKILL.md -> {base}")
    else:
        # Fallback: try to extract SKILL.md from markdown sections
        sections = re.split(r"\n(?=#{1,3}\s+)", text)
        for s in sections:
            s = s.strip()
            if not s:
                continue
            header = s.split('\n')[0].strip('#').strip().lower()
            body = '\n'.join(s.split('\n')[1:]).strip()
            if not body:
                continue
            if 'domain knowledge' in header or 'skill' in header:
                # Wrap as minimal SKILL.md
                fallback = f"# Domain Knowledge\n\n{body}\n"
                write_file(Path('SKILL.md'), fallback, base)
                print(f"  [parse:fallback] wrote SKILL.md from markdown ({len(fallback)} chars)")
                break
        else:
            print("  [parse] WARNING: no SKILL.md found in output")

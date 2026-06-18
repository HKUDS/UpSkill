#!/usr/bin/env python3
"""
Teacher-based ACP retrieval: let strong model select relevant skills/memory.
Usage: python3 retrieve_teacher.py <task_dir> <acp_dir> [--top-k 3]
"""
import sys, re, json
from pathlib import Path

def build_catalog(acp_dir: Path) -> str:
    """Build a numbered catalog of all ACP items with descriptions."""
    items = []
    idx = 1

    # Skills
    skills_dir = acp_dir / '.claude' / 'skills'
    if skills_dir.exists():
        for sf in sorted(skills_dir.iterdir()):
            if not sf.is_file() or sf.suffix != '.md': continue
            content = sf.read_text()
            title = ""
            for line in content.split('\n'):
                if line.startswith('# '):
                    title = line.strip('# ').strip()
                    break
            items.append(f"  [{idx}] SKILL: {title} (file: {sf.name})")
            idx += 1

    # Memory
    mem_dir = acp_dir / '.claude' / 'memory'
    if mem_dir.exists():
        for mf in sorted(mem_dir.iterdir()):
            if not mf.is_file() or mf.name == 'MEMORY.md': continue
            content = mf.read_text()
            m = re.search(r'description:\s*(.+)', content)
            desc = m.group(1).strip() if m else mf.stem.replace('-', ' ')
            items.append(f"  [{idx}] MEMORY: {desc} (file: {mf.name})")
            idx += 1

    return '\n'.join(items)

def retrieve(task_dir: str, acp_dir: str, top_k: int = 3) -> list[str]:
    """Teacher selects relevant skills/memory indices. Returns list of filenames."""
    task_path = Path(task_dir)
    acp_path = Path(acp_dir)
    inst_file = task_path / 'instruction.md'
    if not inst_file.exists(): return []

    instruction = inst_file.read_text()
    catalog = build_catalog(acp_path)
    if not catalog.strip(): return []

    # Ask Teacher to pick most relevant items
    prompt = f"""You are selecting relevant guidance for a task.

## Available Skills & Memory (numbered catalog)
{catalog}

## Task
{instruction}

## Your Job
Select the {top_k} most relevant items from the catalog above.
Output ONLY the item numbers, one per line, like this:
3
7
12

If nothing is relevant, output: NONE"""

    pf = Path('/tmp') / f'teacher_retrieval_{task_path.name}.txt'
    pf.write_text(prompt)

    import subprocess
    from pathlib import Path as P
    PROJECT_DIR = P('/Users/jiangyangqin/Desktop/research/HKUDS/Upskill')
    STRONG_ENV = PROJECT_DIR / 'configs/strong.env'

    # Use any available image
    r = subprocess.run(['docker','images','--format','{{.Repository}}:{{.Tag}}'],
                       capture_output=True, text=True)
    images = [l for l in r.stdout.split('\n') if l.startswith('eh-')]
    image = images[0] if images else 'eh-jq-data-processing:latest'

    try:
        r = subprocess.run(['docker','run','--rm','--env-file',str(STRONG_ENV),
            '-v','/tmp:/out',image,'-c',
            f'timeout 120 claude -p "$(cat /out/teacher_retrieval_{task_path.name}.txt)" 2>&1'
        ], capture_output=True, text=True, timeout=180)
        output = r.stdout
    except:
        output = ""

    pf.unlink(missing_ok=True)

    # Parse selected indices
    selected = []
    for line in output.split('\n'):
        line = line.strip()
        if line.upper() == 'NONE':
            break
        if line.isdigit():
            selected.append(int(line))

    # Map indices back to filenames
    all_items = []
    skills_dir = acp_path / '.claude' / 'skills'
    mem_dir = acp_path / '.claude' / 'memory'

    if skills_dir.exists():
        for sf in sorted(skills_dir.iterdir()):
            if sf.is_file() and sf.suffix == '.md':
                all_items.append(('skill', sf))
    if mem_dir.exists():
        for mf in sorted(mem_dir.iterdir()):
            if mf.is_file() and mf.name != 'MEMORY.md':
                all_items.append(('memory', mf))

    filenames = []
    for idx in selected[:top_k]:
        if 1 <= idx <= len(all_items):
            ctype, filepath = all_items[idx - 1]
            filenames.append((ctype, filepath))

    return filenames

def format_guidance(selected: list) -> str:
    """Format selected items as guidance text."""
    if not selected: return ""
    lines = ["## AgentBrew Relevant Guidance (Teacher-selected)\n"]
    for ctype, filepath in selected:
        lines.append(f"### {ctype}: {filepath.stem}\n")
        try:
            content = filepath.read_text()
            if len(content) > 600:
                content = content[:600] + "\n...(truncated)"
            lines.append(content + "\n")
        except: pass
    return '\n'.join(lines)

if __name__ == '__main__':
    args = sys.argv[1:]
    if len(args) < 2:
        print(f"Usage: {sys.argv[0]} <task_dir> <acp_dir> [--top-k N]")
        sys.exit(1)
    task_dir = args[0]; acp_dir = args[1]
    top_k = 3
    for i, a in enumerate(args):
        if a == '--top-k' and i+1 < len(args): top_k = int(args[i+1])
    selected = retrieve(task_dir, acp_dir, top_k)
    print(format_guidance(selected))

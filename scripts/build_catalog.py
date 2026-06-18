#!/usr/bin/env python3
"""Build task-specific guidance by matching category + keywords. Injects directly into prompt."""
import re, sys
from pathlib import Path

def get_task_category(task_dir: Path) -> str:
    mf = task_dir / 'metadata.yaml'
    if mf.exists():
        for line in mf.read_text().split('\n'):
            m = re.match(r'category:\s*(.+)', line)
            if m: return m.group(1).strip()
    return ''

def extract_keywords(text: str) -> set:
    """Extract meaningful words from text."""
    words = set()
    for w in re.findall(r'[a-z]{4,}', text.lower()):
        if w not in ('this','that','with','from','your','will','have','been','they','them','then','than','when','what','where','which','there','their','about','would','could','should','also','into','over','after','before','between','through','during','because','without','under','other','each','some','only','very','just','more','same','such','here','still','well','part','many','make','made','like','even','much','most','must','need','take','give','find','found','keep','left','right','know','seen','said','look','show','work','call','come','back','down','high','long','small','large','good','great','used','using','name','type','case','does','done','next','last','first','second','third','every','both','these','those','being','been','having','doing','getting','going','looking','check','file','task','write','read','test','data','code','time','line','set','get','see','one','two','can','may','use','new','old','run','end','put','add','let','way','day','now','also','based','given','follow','create','provide','include') and len(w) > 3:
            words.add(w)
    return words

def score_item(item_text: str, task_keywords: set, task_category: str, item_category: str) -> float:
    """Score how relevant an ACP item is to a task."""
    score = 0.0
    item_words = set(item_text.lower().split())

    # Category match (strong signal)
    if task_category and item_category and task_category == item_category:
        score += 0.4

    # Keyword overlap
    if task_keywords and item_words:
        overlap = len(task_keywords & item_words)
        score += min(overlap * 0.05, 0.4)

    # Title keyword match (filename is task name)
    return min(score, 1.0)

def build_injected_guidance(task_dir: Path, acp_dir: Path, top_k: int = 5) -> str:
    instruction = (task_dir / 'instruction.md').read_text() if (task_dir / 'instruction.md').exists() else ""
    task_category = get_task_category(task_dir)
    task_keywords = extract_keywords(instruction)

    # Collect all items with scores
    items = []

    skills_dir = acp_dir / '.claude' / 'skills'
    if skills_dir.exists():
        for sf in sorted(skills_dir.iterdir()):
            if not sf.is_file() or sf.suffix != '.md': continue
            content = sf.read_text()
            title = ""
            for line in content.split('\n'):
                if line.startswith('# '): title = line.strip('# ').strip(); break
            # Infer category from filename/brewing
            task_name = sf.stem.replace('solve-task-', '')
            s = score_item(title + ' ' + task_name, task_keywords, task_category, '')
            items.append(('skill', sf, s, title[:100]))

    mem_dir = acp_dir / '.claude' / 'memory'
    if mem_dir.exists():
        for mf in sorted(mem_dir.iterdir()):
            if not mf.is_file() or mf.name == 'MEMORY.md': continue
            content = mf.read_text()
            m = re.search(r'description:\s*(.+)', content)
            desc = m.group(1).strip() if m else mf.stem
            s = score_item(desc + ' ' + mf.stem, task_keywords, task_category, '')
            items.append(('memory', mf, s, desc[:100]))

    items.sort(key=lambda x: -x[2])
    top = items[:top_k]

    if not top:
        return ""

    lines = [f"## Relevant Guidance (matched to task: {task_category})\n"]
    for ctype, filepath, score, summary in top:
        lines.append(f"### {ctype}: {filepath.stem}\n")
        try:
            content = filepath.read_text()
            if len(content) > 500:
                content = content[:500] + "\n...(truncated)"
            lines.append(content + "\n")
        except: pass

    return '\n'.join(lines)

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <task_dir> <acp_dir> [--top-k N]")
        sys.exit(1)
    task_dir = Path(sys.argv[1]); acp_dir = Path(sys.argv[2])
    top_k = int(sys.argv[4]) if len(sys.argv) > 4 and sys.argv[3] == '--top-k' else 5
    print(build_injected_guidance(task_dir, acp_dir, top_k))

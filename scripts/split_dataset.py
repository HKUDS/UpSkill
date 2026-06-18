#!/usr/bin/env python3
"""Split TB tasks into train/test sets by category.

Usage:
    python3 scripts/split_dataset.py --category software-engineering --train 14 --test 7
    python3 scripts/split_dataset.py --category software-engineering --train 14 --test 7 --dry-run
"""

import sys
import random
import re
import os
from pathlib import Path


def get_task_info(task_dir: Path) -> dict | None:
    """Parse task.yaml for a single task."""
    yaml_path = task_dir / 'task.yaml'
    if not yaml_path.exists():
        return None

    text = yaml_path.read_text()
    info = {'name': task_dir.name}

    for line in text.split('\n'):
        for field in ['difficulty', 'category']:
            m = re.match(rf'{field}:\s*(.+)', line)
            if m:
                info[field] = m.group(1).strip()

    return info


def main():
    # Parse args: --key=value or --key value or --flag
    args = {}
    i = 1
    while i < len(sys.argv):
        a = sys.argv[i]
        if a.startswith('--'):
            if '=' in a:
                key, val = a[2:].split('=', 1)
                args[key] = val
            else:
                key = a[2:]
                if i + 1 < len(sys.argv) and not sys.argv[i + 1].startswith('--'):
                    args[key] = sys.argv[i + 1]
                    i += 1
                else:
                    args[key] = True
        i += 1

    category = args.get('category', 'software-engineering')
    n_train = int(args.get('train', 14))
    n_test = int(args.get('test', 7))
    dry_run = 'dry-run' in args
    seed = int(args.get('seed', 42))
    tasks_root = args.get('tasks_root', 'tb_repo/original-tasks')

    random.seed(seed)

    # Collect eligible tasks
    eligible = []
    tasks_root = Path(tasks_root)
    for task_dir in sorted(tasks_root.iterdir()):
        if not task_dir.is_dir():
            continue
        info = get_task_info(task_dir)
        if not info:
            continue
        if info.get('category') != category:
            continue
        if not args.get('include-hard') and info.get('difficulty') == 'hard':
            continue
        eligible.append(info)

    print(f"Category: {category}")
    print(f"Eligible (easy+medium): {len(eligible)}")

    if len(eligible) < n_train + n_test:
        print(f"WARNING: only {len(eligible)} eligible, "
              f"need {n_train + n_test}. Reducing split.")
        total = len(eligible)
        n_train = int(total * 0.7)
        n_test = total - n_train

    # Shuffle and split
    random.shuffle(eligible)
    train = sorted(eligible[:n_train], key=lambda x: x['name'])
    test = sorted(eligible[n_train:n_train + n_test], key=lambda x: x['name'])

    print(f"Train: {len(train)}")
    print(f"Test:  {len(test)}")
    print()

    if dry_run:
        print("=== TRAIN (dry-run) ===")
        for t in train:
            print(f"  {t['name']} ({t.get('difficulty', '?')})")
        print("=== TEST (dry-run) ===")
        for t in test:
            print(f"  {t['name']} ({t.get('difficulty', '?')})")
        return

    # Write split files
    output_dir = Path('dataset')
    output_dir.mkdir(exist_ok=True)

    for label, tasks in [('train', train), ('test', test)]:
        lines = []
        for t in tasks:
            lines.append(f"  - {t['name']}  # {t.get('difficulty', '?')}")

        content = f"# {category} — {label} set\n"
        content += f"# {len(tasks)} tasks\n"
        content += f"tasks:\n" + '\n'.join(lines) + '\n'

        path = output_dir / f'{category}_{label}.yaml'
        path.write_text(content)
        print(f"Written: {path}")

    # Also write a plain list for bash processing
    for label, tasks in [('train', train), ('test', test)]:
        path = output_dir / f'{category}_{label}.txt'
        path.write_text('\n'.join(t['name'] for t in tasks) + '\n')
        print(f"Written: {path}")

    print(f"\nTo import all split tasks:")
    print(f"  bash scripts/import_split.sh dataset/{category}_train.txt")
    print(f"  bash scripts/import_split.sh dataset/{category}_test.txt")


if __name__ == '__main__':
    main()

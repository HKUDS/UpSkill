#!/usr/bin/env python3
"""
Phase 4: Merge per-task ACPs into one curated ACP per category.
Usage:
  python3 scripts/run_curator.py --acp-dir brew_acp [--output-dir curated_acp]
"""
import argparse, json, os, re, shutil, subprocess
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent
HARBOR = PROJECT_DIR / ".venv_harbor" / "bin" / "harbor"
STRONG_ENV = PROJECT_DIR / "configs" / "strong.env"


def parse_args():
    p = argparse.ArgumentParser(description="Curate per-task ACP into per-category ACP")
    p.add_argument("--acp-dir", required=True, help="Directory with per-task ACP files")
    p.add_argument("--output-dir", default=None, help="Output for curated ACP")
    p.add_argument("--n-concurrent", type=int, default=4)
    p.add_argument("--timeout-multiplier", type=float, default=4)
    return p.parse_args()


def extract_acp(traj_path):
    """Same extraction logic as run_brew.py."""
    acp = {}
    with open(traj_path) as f:
        traj = json.load(f)

    for step in traj.get("steps", []):
        for tc in step.get("tool_calls", []):
            fn = tc.get("function_name", "")
            fp = tc.get("arguments", {}).get("file_path", "")
            if ("Write" not in fn and "Edit" not in fn):
                continue
            if not any(x in fp for x in ["CLAUDE.md", "solve-task", "feedback"]):
                continue
            for obs in step.get("observation", {}).get("results", []):
                c = str(obs.get("content", ""))
                m = re.search(r"\[metadata\] (\{.*\})", c, re.DOTALL)
                if not m:
                    continue
                try:
                    meta = json.loads(m.group(1))
                except json.JSONDecodeError:
                    continue
                content = meta.get("new_string") or meta.get("content", "")
                if not content or len(content) < 100:
                    continue
                if "CLAUDE.md" in fp and "/.claude/" not in fp:
                    acp["CLAUDE.md"] = content
                elif "solve-task" in fp:
                    acp["solve-task.md"] = content
                elif "feedback" in fp:
                    acp["feedback.md"] = content
    return acp


def main():
    args = parse_args()
    acp_dir = Path(args.acp_dir)
    if not acp_dir.is_absolute():
        acp_dir = PROJECT_DIR / "tb_harbor_2.0" / args.acp_dir
    if not acp_dir.exists():
        print(f"Error: ACP directory not found: {acp_dir}")
        sys.exit(1)

    output_dir = Path(args.output_dir) if args.output_dir else (PROJECT_DIR / "tb_harbor_2.0" / "curated_acp")
    jobs_dir = PROJECT_DIR / "tb_harbor_2.0" / "jobs_curator"
    temp_tasks_dir = PROJECT_DIR / "tb_harbor_2.0" / ".curator_temp_tasks"

    shutil.rmtree(temp_tasks_dir, ignore_errors=True)
    shutil.rmtree(jobs_dir, ignore_errors=True)
    os.makedirs(output_dir, exist_ok=True)
    os.makedirs(temp_tasks_dir, exist_ok=True)

    categories = sorted(d for d in acp_dir.iterdir() if d.is_dir())

    print(f"Curating {len(categories)} categories")
    print(f"Input ACP:  {acp_dir}")
    print(f"Output:     {output_dir}")

    for cat_dir in categories:
        cat = cat_dir.name
        files = sorted(cat_dir.iterdir())

        # Collect all ACP content per type
        claude_parts = []
        skill_parts = []
        feedback_parts = []
        for f in files:
            content = f.read_text()
            if "_CLAUDE.md" in f.name:
                task = f.name.replace("_CLAUDE.md", "")
                claude_parts.append(f"### From: {task}\n{content}")
            elif "_solve-task.md" in f.name:
                task = f.name.replace("_solve-task.md", "")
                skill_parts.append(f"### From: {task}\n{content}")
            elif "_feedback.md" in f.name:
                task = f.name.replace("_feedback.md", "")
                feedback_parts.append(f"### From: {task}\n{content}")

        if not claude_parts:
            print(f"  {cat}: no ACP found, skipping")
            continue

        curator_prompt = f"""You are a CURATOR agent. Merge multiple per-task ACP files into ONE cohesive config package for the "{cat}" category.

## CLAUDE.md (from {len(claude_parts)} tasks)
{chr(10).join(claude_parts)[:8000]}

## Skills (from {len(skill_parts)} tasks)
{chr(10).join(skill_parts)[:6000]}

## Feedback Memory (from {len(feedback_parts)} tasks)
{chr(10).join(feedback_parts)[:4000]}

## Your Job
Synthesize these into a SINGLE clean, non-redundant package. Remove duplicates. Keep the BEST version of each insight. Organize by topic.

Use Write tool:
1. /app/CLAUDE.md — curated project guidance for {cat} category (~80 lines)
2. /app/.claude/skills/solve-task.md — unified skill (~100 lines)
3. /app/memory/feedback.md — consolidated feedback memory (~50 lines)

Be concise. Remove redundancy."""

        task_dir = temp_tasks_dir / cat
        for sub in ["environment", "tests", "solution"]:
            (task_dir / sub).mkdir(parents=True, exist_ok=True)
        (task_dir / "instruction.md").write_text(curator_prompt)
        (task_dir / "task.toml").write_text(
            f'category = "{cat}"\ndifficulty = "medium"\nmax_agent_timeout_sec = 1200\nmax_test_timeout_sec = 600\n'
        )
        (task_dir / "environment" / "Dockerfile").write_text("FROM ubuntu:24.04\nWORKDIR /app\n")
        (task_dir / "tests" / "test_outputs.py").write_text("def test_dummy():\n    assert True\n")
        (task_dir / "tests" / "test.sh").write_text("#!/bin/bash\necho ok\n")
        (task_dir / "solution" / "solve.sh").write_text("#!/bin/bash\necho ok\n")

    print(f"\nRunning curator via Harbor...")

    subprocess.run(
        [
            str(HARBOR), "run",
            "--path", str(temp_tasks_dir),
            "--agent", "claude-code",
            "--model", "deepseek-v4-pro",
            "--env-file", str(STRONG_ENV),
            "--n-concurrent", str(args.n_concurrent),
            "--jobs-dir", str(jobs_dir),
            "--timeout-multiplier", str(args.timeout_multiplier),
            "--quiet", "-y",
        ],
        check=True,
    )

    # Extract curated ACP
    print("\nExtracting curated ACP...")
    jds = sorted([d for d in jobs_dir.iterdir() if d.is_dir()])
    extracted = 0
    if jds:
        job_dir = jds[-1]
        for d in job_dir.iterdir():
            if not d.is_dir():
                continue
            cat = re.sub(r"__[A-Za-z0-9]+$", "", d.name)
            traj_path = d / "agent" / "trajectory.json"
            if not traj_path.exists():
                continue

            acp = extract_acp(str(traj_path))
            if not acp:
                print(f"  {cat}: no curated ACP found")
                continue

            cat_out = output_dir / cat
            for fname, content in acp.items():
                if fname == "CLAUDE.md":
                    dest = cat_out / "CLAUDE.md"
                elif fname == "solve-task.md":
                    dest = cat_out / ".claude" / "skills" / "solve-task.md"
                else:
                    dest = cat_out / "memory" / "feedback.md"
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_text(content)

            total_chars = sum(len(v) for v in acp.values())
            print(f"  {cat}: {len(acp)} files, {total_chars} chars")
            extracted += 1

    print(f"\nCurated {extracted}/{len(categories)} categories")
    print(f"ACP saved to: {output_dir}")

    shutil.rmtree(temp_tasks_dir, ignore_errors=True)


if __name__ == "__main__":
    main()

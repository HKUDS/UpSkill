#!/usr/bin/env python3
"""
Phase 3: Generate per-task ACP from student trajectories using teacher model.
Usage:
  python3 scripts/run_brew.py --student-job <dir> [--split train] [--output-dir brew_acp]
"""
import argparse, json, os, re, shutil, subprocess, sys, tempfile
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent
HARBOR = PROJECT_DIR / ".venv_harbor" / "bin" / "harbor"
TASKS_DIR = PROJECT_DIR / "tb_harbor_2.0" / "tasks"
SPLIT_FILE = PROJECT_DIR / "tb_harbor_2.0" / "split.json"
STRONG_ENV = PROJECT_DIR / "configs" / "strong.env"


def parse_args():
    p = argparse.ArgumentParser(description="Generate per-task ACP via teacher")
    p.add_argument("--student-job", required=True, help="Path to student baseline Harbor job")
    p.add_argument("--split", default="train", choices=["train", "test"])
    p.add_argument("--output-dir", default=None, help="Output for ACP files")
    p.add_argument("--n-concurrent", type=int, default=4)
    p.add_argument("--timeout-multiplier", type=float, default=4)
    p.add_argument("--n-tasks", type=int, default=0, help="Max tasks (0=all)")
    return p.parse_args()


def load_split():
    with open(SPLIT_FILE) as f:
        data = json.load(f)
    return data


def build_brew_prompt(instruction, trajectory, result):
    result_note = "The student SUCCEEDED. Analyze what they did RIGHT and capture the winning approach as reusable guidance." if result == "PASS" else "The student FAILED. Analyze WHY and capture corrective guidance."
    return f"""You are a TEACHER agent (deepseek-v4-pro). Your student (deepseek-v4-flash) {result} this task.

## Task Instruction
{instruction}

## Student Trajectory
{trajectory}

## Your Job
{result_note}

Generate a CONFIG PACKAGE using the Write tool:
1. /app/CLAUDE.md — project guidance with approach, pitfalls, command patterns
2. /app/.claude/skills/solve-task.md — ordered checklist for this task type
3. /app/memory/feedback.md — feedback memory (Rule/Why/How format)

Be CONCRETE. Give exact commands. Think about what another flash student needs."""


def extract_acp_from_trajectory(traj_path):
    """Extract ACP files written by teacher via Write tool from trajectory.json."""
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
                    key = "CLAUDE.md"
                elif "solve-task" in fp:
                    key = "solve-task.md"
                elif "feedback" in fp:
                    key = "feedback.md"
                else:
                    continue

                if key not in acp or "Edit" in fn:
                    # Edit: overwrite (partial update). Write: use latest.
                    if "Edit" in fn and key in acp:
                        continue  # keep original if already have full Write
                acp[key] = content

    return acp


def main():
    args = parse_args()
    split = load_split()
    tasks = list(split[args.split].keys())

    if args.n_tasks > 0:
        tasks = tasks[: args.n_tasks]

    output_dir = Path(args.output_dir) if args.output_dir else (PROJECT_DIR / "tb_harbor_2.0" / "brew_acp")
    jobs_dir = PROJECT_DIR / "tb_harbor_2.0" / "jobs_brew"
    temp_tasks_dir = PROJECT_DIR / "tb_harbor_2.0" / ".brew_temp_tasks"

    # Clean
    shutil.rmtree(temp_tasks_dir, ignore_errors=True)
    shutil.rmtree(jobs_dir, ignore_errors=True)
    os.makedirs(output_dir, exist_ok=True)
    os.makedirs(temp_tasks_dir, exist_ok=True)

    # Map task -> trial dir in student job
    student_job_dir = Path(args.student_job)
    if not student_job_dir.exists():
        # Try to find the latest job dir inside
        jds = sorted([d for d in student_job_dir.iterdir() if d.is_dir()])
        if jds:
            student_job_dir = jds[-1]

    trial_map = {}
    for d in student_job_dir.iterdir():
        if d.is_dir() and "__" in d.name:
            task_name = re.sub(r"__[A-Za-z0-9]+$", "", d.name)
            trial_map[task_name] = d.name

    print(f"Brewing {len(tasks)} tasks from {args.split} split")
    print(f"Student job: {student_job_dir}")
    print(f"Output ACP:  {output_dir}")
    print(f"Temp tasks:  {temp_tasks_dir}")
    print()

    # Create temp task dirs with brewing prompts
    brew_count = 0
    for task in tasks:
        cat = split[args.split][task]
        trial_name = trial_map.get(task)
        if not trial_name:
            print(f"  SKIP {task}: no trial in student job")
            continue

        traj_path = student_job_dir / trial_name / "agent" / "trajectory.json"
        if not traj_path.exists():
            print(f"  SKIP {task}: no trajectory")
            continue

        with open(traj_path) as f:
            traj = json.load(f)

        # Extract student trajectory summary
        trajectory_text = ""
        for step in traj.get("steps", [])[-15:]:
            msg = step.get("message", "")
            if msg:
                trajectory_text += (msg[:250] + "...\n") if len(msg) > 250 else msg + "\n"

        # Determine if student passed or failed
        # Check result.json from student job
        result = "FAIL"  # default
        result_path = student_job_dir / "result.json"
        if result_path.exists():
            with open(result_path) as f:
                rs = json.load(f)["stats"]
            for ed in rs.get("evals", {}).values():
                for t in ed.get("reward_stats", {}).get("reward", {}).get("1.0", []):
                    if re.sub(r"__[A-Za-z0-9]+$", "", t) == task:
                        result = "PASS"

        # Read instruction
        inst_path = TASKS_DIR / task / "instruction.md"
        if not inst_path.exists():
            print(f"  SKIP {task}: no instruction.md")
            continue
        instruction = inst_path.read_text()

        brew_prompt = build_brew_prompt(instruction, trajectory_text, result)

        # Create temp task
        task_dir = temp_tasks_dir / task
        for sub in ["environment", "tests", "solution"]:
            (task_dir / sub).mkdir(parents=True, exist_ok=True)

        (task_dir / "instruction.md").write_text(brew_prompt)
        (task_dir / "task.toml").write_text(
            f'category = "{cat}"\ndifficulty = "medium"\nmax_agent_timeout_sec = 1800\nmax_test_timeout_sec = 1200\n'
        )
        (task_dir / "environment" / "Dockerfile").write_text("FROM ubuntu:24.04\nWORKDIR /app\n")
        (task_dir / "tests" / "test_outputs.py").write_text("def test_dummy():\n    assert True\n")
        (task_dir / "tests" / "test.sh").write_text("#!/bin/bash\necho ok\n")
        (task_dir / "solution" / "solve.sh").write_text("#!/bin/bash\necho ok\n")

        brew_count += 1

    print(f"Created {brew_count} brew tasks, running Harbor teacher...")

    # Run Harbor on all brew tasks
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

    # Extract ACP from each completed task
    print("\nExtracting ACP...")
    extracted = 0
    jds = sorted([d for d in jobs_dir.iterdir() if d.is_dir()])
    if jds:
        job_dir = jds[-1]
        for d in job_dir.iterdir():
            if not d.is_dir():
                continue
            task_name = re.sub(r"__[A-Za-z0-9]+$", "", d.name)
            traj_path = d / "agent" / "trajectory.json"
            if not traj_path.exists():
                continue

            acp = extract_acp_from_trajectory(str(traj_path))
            if not acp:
                print(f"  {task_name}: no ACP found")
                continue

            cat = split[args.split].get(task_name, "unknown")
            cat_dir = output_dir / cat
            cat_dir.mkdir(parents=True, exist_ok=True)

            for fname, content in acp.items():
                dest = cat_dir / f"{task_name}_{fname}"
                dest.write_text(content)

            cost = 0
            with open(traj_path) as f:
                cost = json.load(f).get("final_metrics", {}).get("total_cost_usd", 0) or 0
            print(f"  {task_name}: {len(acp)} files ({sum(len(v) for v in acp.values())} chars, \${cost:.2f})")
            extracted += 1

    print(f"\nExtracted ACP for {extracted}/{brew_count} tasks")
    print(f"ACP saved to: {output_dir}")

    # Cleanup temp tasks
    shutil.rmtree(temp_tasks_dir, ignore_errors=True)


if __name__ == "__main__":
    main()

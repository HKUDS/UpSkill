#!/usr/bin/env python3
"""
Phase 5: Validate ACP with student CC, iteratively refine on failure.
Usage:
  python3 scripts/run_ralph.py --acp-dir brew_acp --student-job <dir> [--max-rounds 3]
"""
import argparse, json, os, re, shutil, subprocess, sys
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent
HARBOR = PROJECT_DIR / ".venv_harbor" / "bin" / "harbor"
TASKS_DIR = PROJECT_DIR / "tb_harbor_2.0" / "tasks"
SPLIT_FILE = PROJECT_DIR / "tb_harbor_2.0" / "split.json"
WEAK_ENV = PROJECT_DIR / "configs" / "weak.env"
STRONG_ENV = PROJECT_DIR / "configs" / "strong.env"


def parse_args():
    p = argparse.ArgumentParser(description="Ralph validation loop")
    p.add_argument("--acp-dir", required=True, help="Per-task ACP directory")
    p.add_argument("--student-job", required=True, help="Student baseline Harbor job dir")
    p.add_argument("--max-rounds", type=int, default=3)
    p.add_argument("--n-concurrent", type=int, default=4)
    p.add_argument("--timeout-multiplier", type=float, default=4)
    return p.parse_args()


def load_split():
    with open(SPLIT_FILE) as f:
        return json.load(f)


def clean_task_id(name):
    return re.sub(r"__[A-Za-z0-9]+$", "", name)


def get_job_results(job_dir):
    """Return (passed, failed, errored) sets from a Harbor job directory."""
    jds = sorted([d for d in job_dir.iterdir() if d.is_dir()])
    if not jds:
        return set(), set(), set()
    result_path = jds[-1] / "result.json"
    if not result_path.exists():
        return set(), set(), set()

    with open(result_path) as f:
        s = json.load(f)["stats"]

    passed = set()
    failed = set()
    errored = set()
    for ed in s.get("evals", {}).values():
        for t in ed.get("reward_stats", {}).get("reward", {}).get("1.0", []):
            passed.add(clean_task_id(t))
        for t in ed.get("reward_stats", {}).get("reward", {}).get("0.0", []):
            failed.add(clean_task_id(t))
        for ex, tasks in ed.get("exception_stats", {}).items():
            for t in tasks:
                errored.add(clean_task_id(t))
    return passed, failed, errored


def extract_failure_trajectory(trial_dir, n_steps=10):
    """Extract last n steps from a trial's trajectory."""
    traj_path = trial_dir / "agent" / "trajectory.json"
    if not traj_path.exists():
        return "(no trajectory)"
    with open(traj_path) as f:
        traj = json.load(f)
    text = ""
    for step in traj.get("steps", [])[-n_steps:]:
        msg = step.get("message", "")
        if msg:
            text += (msg[:200] + "...\n") if len(msg) > 200 else msg + "\n"
    return text


def run_harbor_round(task_list, env_path, model, job_name):
    """Run Harbor on a list of task dirs. Returns job dir."""
    jobs_dir = PROJECT_DIR / "tb_harbor_2.0" / f"jobs_ralph_{job_name}"
    shutil.rmtree(jobs_dir, ignore_errors=True)
    subprocess.run(
        [
            str(HARBOR), "run",
            "--path", str(PROJECT_DIR / "tb_harbor_2.0" / f".ralph_tasks_{job_name}"),
            "--agent", "claude-code",
            "--model", model,
            "--env-file", str(env_path),
            "--n-concurrent", "4",
            "--jobs-dir", str(jobs_dir),
            "--timeout-multiplier", "4",
            "--quiet", "-y",
        ],
        check=True,
    )
    return jobs_dir


def find_trial(job_dir, task):
    """Find trial dir for a task in a Harbor job."""
    jds = sorted([d for d in job_dir.iterdir() if d.is_dir()])
    if not jds:
        return None
    for d in jds[-1].iterdir():
        if d.is_dir() and clean_task_id(d.name) == task:
            return d
    return None


def main():
    args = parse_args()
    split = load_split()
    acp_dir = Path(args.acp_dir)
    if not acp_dir.is_absolute():
        acp_dir = PROJECT_DIR / "tb_harbor_2.0" / args.acp_dir

    student_job = Path(args.student_job)
    if not student_job.exists():
        jds = sorted([d for d in student_job.iterdir() if d.is_dir()])
        if jds:
            student_job = jds[-1]

    # Get baseline results
    base_pass, base_fail, base_err = get_job_results(student_job)
    # Only consider train tasks that have ACP
    train_tasks = set(split["train"].keys())
    acp_cats = set(d.name for d in acp_dir.iterdir() if d.is_dir())

    # Find tasks with ACP
    brew_tasks = set()
    for cat_dir in acp_dir.iterdir():
        if not cat_dir.is_dir():
            continue
        for f in cat_dir.iterdir():
            if "_CLAUDE.md" in f.name:
                task = f.name.replace("_CLAUDE.md", "")
                if task in train_tasks:
                    brew_tasks.add(task)

    needs_validation = brew_tasks

    print(f"Ralph validation: {len(needs_validation)} tasks, max {args.max_rounds} rounds")
    print(f"ACP dir: {acp_dir}")
    print()

    status = {}  # task -> 'validated' or 'failed_after_N'

    for round_num in range(1, args.max_rounds + 1):
        # Determine which tasks still need validation this round
        current_tasks = set()
        if round_num == 1:
            current_tasks = set(needs_validation)
        else:
            current_tasks = {t for t in needs_validation if status.get(t, "").startswith("failed")}

        if not current_tasks:
            print(f"Round {round_num}: all tasks validated or exhausted, done!")
            break

        print(f"\n{'='*60}")
        print(f"Round {round_num}: {len(current_tasks)} tasks")
        print(f"{'='*60}")

        # Create task dirs with ACP deployed
        temp_dir = PROJECT_DIR / "tb_harbor_2.0" / f".ralph_tasks_r{round_num}"
        shutil.rmtree(temp_dir, ignore_errors=True)
        os.makedirs(temp_dir, exist_ok=True)

        for task in sorted(current_tasks):
            cat = split["train"].get(task, "unknown")
            src = TASKS_DIR / task
            dst = temp_dir / task
            if dst.exists():
                shutil.rmtree(dst)
            if not src.exists():
                print(f"  SKIP {task}: source not found")
                continue
            shutil.copytree(src, dst)

            # Deploy CLAUDE.md
            acp_file = acp_dir / cat / f"{task}_CLAUDE.md"
            if acp_file.exists():
                shutil.copy(acp_file, dst / "CLAUDE.md")

        # Run student validation
        jobs_dir = PROJECT_DIR / "tb_harbor_2.0" / f"jobs_ralph_r{round_num}"
        shutil.rmtree(jobs_dir, ignore_errors=True)
        subprocess.run(
            [
                str(HARBOR), "run",
                "--path", str(temp_dir),
                "--agent", "claude-code",
                "--model", "deepseek-v4-flash",
                "--env-file", str(WEAK_ENV),
                "--n-concurrent", str(args.n_concurrent),
                "--jobs-dir", str(jobs_dir),
                "--timeout-multiplier", str(args.timeout_multiplier),
                "--quiet", "-y",
            ],
            check=True,
        )

        # Check results
        r_pass, r_fail, r_err = get_job_results(jobs_dir)
        r_all = r_pass | r_fail | r_err

        for task in sorted(current_tasks):
            if task in r_pass:
                status[task] = "validated"
                print(f"  ✅ {task}: PASS (round {round_num})")
            elif task not in r_all:
                status[task] = f"failed_after_{round_num}"
                print(f"  ❌ {task}: not found in results")
            else:
                status[task] = f"failed_after_{round_num}"
                if round_num < args.max_rounds:
                    print(f"  🔄 {task}: FAIL → refine for round {round_num + 1}")

        # If not last round, revise ACP for FAIL tasks
        if round_num < args.max_rounds:
            fail_this_round = (r_fail | r_err) & current_tasks
            if not fail_this_round:
                print("  No failures to refine, breaking early")
                break

            print(f"\n  Refining ACP for {len(fail_this_round)} failed tasks...")
            refine_dir = PROJECT_DIR / "tb_harbor_2.0" / f".refine_tasks_r{round_num + 1}"
            shutil.rmtree(refine_dir, ignore_errors=True)
            os.makedirs(refine_dir, exist_ok=True)

            for task in sorted(fail_this_round):
                cat = split["train"].get(task, "unknown")
                trial = find_trial(jobs_dir, task)
                if not trial:
                    continue

                failure_text = extract_failure_trajectory(trial)

                # Read current ACP
                acp_file = acp_dir / cat / f"{task}_CLAUDE.md"
                current_claude = acp_file.read_text()[:2000] if acp_file.exists() else ""

                inst = (TASKS_DIR / task / "instruction.md").read_text()
                revise_prompt = f"""You are the TEACHER. Student FAILED with your ACP. REVISE IT.

## Task
{inst}

## Current CLAUDE.md
{current_claude}

## Student Failure with ACP
{failure_text}

REVISE ALL 3 files with Write tool. Make instructions MORE EXPLICIT:
1. /app/CLAUDE.md — Add exact commands, fix wrong steps
2. /app/.claude/skills/solve-task.md — Numbered checklist with exact commands
3. /app/memory/feedback.md — New error patterns"""

                task_dir = refine_dir / task
                for sub in ["environment", "tests", "solution"]:
                    (task_dir / sub).mkdir(parents=True, exist_ok=True)
                (task_dir / "instruction.md").write_text(revise_prompt)
                (task_dir / "task.toml").write_text(
                    f'category = "{cat}"\ndifficulty = "medium"\nmax_agent_timeout_sec = 1800\nmax_test_timeout_sec = 1200\n'
                )
                (task_dir / "environment" / "Dockerfile").write_text("FROM ubuntu:24.04\nWORKDIR /app\n")
                (task_dir / "tests" / "test_outputs.py").write_text("def test_dummy():\n    assert True\n")
                (task_dir / "tests" / "test.sh").write_text("#!/bin/bash\necho ok\n")
                (task_dir / "solution" / "solve.sh").write_text("#!/bin/bash\necho ok\n")

            # Run teacher revision
            refine_jobs = PROJECT_DIR / "tb_harbor_2.0" / f"jobs_refine_r{round_num + 1}"
            shutil.rmtree(refine_jobs, ignore_errors=True)
            subprocess.run(
                [
                    str(HARBOR), "run",
                    "--path", str(refine_dir),
                    "--agent", "claude-code",
                    "--model", "deepseek-v4-pro",
                    "--env-file", str(STRONG_ENV),
                    "--n-concurrent", str(args.n_concurrent),
                    "--jobs-dir", str(refine_jobs),
                    "--timeout-multiplier", str(args.timeout_multiplier),
                    "--quiet", "-y",
                ],
                check=True,
            )

            # Extract revised ACP and update
            jds2 = sorted([d for d in refine_jobs.iterdir() if d.is_dir()])
            if jds2:
                for d in jds2[-1].iterdir():
                    if not d.is_dir():
                        continue
                    task = clean_task_id(d.name)
                    cat = split["train"].get(task, "unknown")
                    traj_path = d / "agent" / "trajectory.json"
                    if not traj_path.exists():
                        continue

                    with open(traj_path) as f:
                        traj = json.load(f)

                    for step in traj.get("steps", []):
                        for tc in step.get("tool_calls", []):
                            fn = tc.get("function_name", "")
                            fp = tc.get("arguments", {}).get("file_path", "")
                            if ("Write" not in fn) or "CLAUDE.md" not in fp or "/.claude/" in fp:
                                continue
                            for obs in step.get("observation", {}).get("results", []):
                                c = str(obs.get("content", ""))
                                m = re.search(r"\[metadata\] (\{.*\})", c, re.DOTALL)
                                if not m:
                                    continue
                                try:
                                    meta = json.loads(m.group(1))
                                    content = meta.get("content", "")
                                    if content and len(content) > 100:
                                        dest = acp_dir / cat / f"{task}_CLAUDE.md"
                                        dest.parent.mkdir(parents=True, exist_ok=True)
                                        dest.write_text(content)
                                        print(f"    Updated ACP: {task}")
                                except json.JSONDecodeError:
                                    pass

            shutil.rmtree(refine_dir, ignore_errors=True)

        # Cleanup
        shutil.rmtree(temp_dir, ignore_errors=True)

    # Summary
    print(f"\n{'='*60}")
    print("Ralph Final Summary")
    print(f"{'='*60}")
    validated = sum(1 for v in status.values() if v == "validated")
    failed = sum(1 for v in status.values() if v.startswith("failed"))
    print(f"  Validated: {validated}/{len(status)}")
    print(f"  Failed:    {failed}/{len(status)}")

    # Save status
    status_path = PROJECT_DIR / "tb_harbor_2.0" / "ralph_status.json"
    with open(status_path, "w") as f:
        json.dump(status, f, indent=2)
    print(f"  Status saved to: {status_path}")


if __name__ == "__main__":
    main()

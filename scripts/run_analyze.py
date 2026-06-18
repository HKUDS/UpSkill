#!/usr/bin/env python3
"""
Analyze experiment results: pass rates, GAIN/LOSS, cost breakdown, per-category delta.
Usage:
  python3 scripts/run_analyze.py \
    --baseline-student <job> --baseline-teacher <job> --serve <job> \
    --split split.json [--output RESULTS.md]
"""
import argparse, json, os, re, sys
from collections import defaultdict
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent

# DeepSeek Official Pricing per 1M tokens
PRICING = {
    "flash": {"miss": 0.14, "hit": 0.0028, "output": 0.28},
    "pro": {"miss": 0.435, "hit": 0.003625, "output": 0.87},
}


def parse_args():
    p = argparse.ArgumentParser(description="Analyze experiment results")
    p.add_argument("--baseline-student", required=True, help="Student baseline Harbor job")
    p.add_argument("--baseline-teacher", required=True, help="Teacher baseline Harbor job")
    p.add_argument("--serve", required=True, help="Serve (student+ACP) Harbor job")
    p.add_argument("--split", required=True, help="Path to split.json")
    p.add_argument("--output", default=None, help="Output markdown file")
    return p.parse_args()


def clean(t):
    return re.sub(r"__[A-Za-z0-9]+$", "", t)


def get_results(job_dir, test_set=None):
    """Return (passed, failed, errored) sets and token/cost data."""
    jds = sorted([d for d in job_dir.iterdir() if d.is_dir()])
    if not jds:
        return set(), set(), set(), {}
    with open(jds[-1] / "result.json") as f:
        s = json.load(f)["stats"]

    passed = set()
    failed = set()
    errored = set()
    for ed in s.get("evals", {}).values():
        for t in ed.get("reward_stats", {}).get("reward", {}).get("1.0", []):
            passed.add(clean(t))
        for t in ed.get("reward_stats", {}).get("reward", {}).get("0.0", []):
            failed.add(clean(t))
        for ex, tasks in ed.get("exception_stats", {}).items():
            for t in tasks:
                errored.add(clean(t))

    if test_set:
        passed &= test_set
        failed &= test_set
        errored &= test_set

    # Aggregate token data from trajectories
    tokens = {"prompt": 0, "cache_read": 0, "completion": 0}
    for d in jds[-1].iterdir():
        if not d.is_dir():
            continue
        t = clean(d.name)
        if test_set and t not in test_set:
            continue
        traj_path = d / "agent" / "trajectory.json"
        if not traj_path.exists():
            continue
        with open(traj_path) as f:
            traj = json.load(f)
        fm = traj.get("final_metrics", {})
        extra = fm.get("extra", {}) or {}
        tokens["prompt"] += fm.get("total_prompt_tokens", 0) or 0
        tokens["cache_read"] += extra.get("total_cache_read_input_tokens", 0) or 0
        tokens["completion"] += fm.get("total_completion_tokens", 0) or 0

    return passed, failed, errored, tokens


def calc_cost(tokens, model):
    """Calculate cost using DeepSeek pricing."""
    p = PRICING[model]
    miss = max(0, tokens["prompt"] - tokens["cache_read"])
    hit = tokens["cache_read"]
    out = tokens["completion"]
    return {
        "miss_cost": miss * p["miss"] / 1e6,
        "hit_cost": hit * p["hit"] / 1e6,
        "output_cost": out * p["output"] / 1e6,
        "total": miss * p["miss"] / 1e6 + hit * p["hit"] / 1e6 + out * p["output"] / 1e6,
        "miss_tokens": miss,
        "hit_tokens": hit,
        "out_tokens": out,
    }


def get_all_three_pass_tasks(sp, tp, vp, test_set):
    """Get tasks that PASS in all 3 experiments."""
    all_pass = (sp & tp & vp) & test_set
    return all_pass


def compute_all_pass_cost(all_pass, job_dirs, test_set):
    """Compute per-task cost for all-three-pass tasks."""
    results = {"student": [], "teacher": [], "serve": []}

    for label, (job_dir, model) in job_dirs.items():
        jds = sorted([d for d in job_dir.iterdir() if d.is_dir()])
        if not jds:
            continue
        for d in jds[-1].iterdir():
            if not d.is_dir():
                continue
            t = clean(d.name)
            if t not in all_pass:
                continue
            traj_path = d / "agent" / "trajectory.json"
            if not traj_path.exists():
                continue
            with open(traj_path) as f:
                traj = json.load(f)
            fm = traj.get("final_metrics", {})
            extra = fm.get("extra", {}) or {}
            prompt = fm.get("total_prompt_tokens", 0) or 0
            cache_read = extra.get("total_cache_read_input_tokens", 0) or 0
            completion = fm.get("total_completion_tokens", 0) or 0
            cost = calc_cost({"prompt": prompt, "cache_read": cache_read, "completion": completion}, model)
            results[label].append({"task": t, "prompt": prompt, "cache_read": cache_read, "completion": completion, "cost": cost["total"]})

    return results


def generate_md(args, split, sp, sf, se, s_tok, tp, tf, te, t_tok, vp, vf, ve, v_tok, all_pass, all_pass_costs):
    """Generate markdown report."""
    test_set = set(split["test"].keys())
    all_cats = {**split["train"], **split["test"]}

    sf_total = sf | se
    tf_total = tf | te
    vf_total = vf | ve
    TOTAL = 64

    gain = sorted(vp & sf)
    loss = sorted((vf | ve) & sp)

    s_cost = calc_cost(s_tok, "flash")
    t_cost = calc_cost(t_tok, "pro")
    v_cost = calc_cost(v_tok, "flash")

    # Per-category
    cat_rows = []
    for cat in sorted(set(all_cats.values())):
        tasks = [t for t in test_set if all_cats[t] == cat]
        n = len(tasks)
        bp = len([t for t in tasks if t in sp])
        bf = len([t for t in tasks if t in sf_total])
        vp_c = len([t for t in tasks if t in vp])
        vf_c = len([t for t in tasks if t in vf_total])
        br = bp / n * 100
        vr = vp_c / n * 100
        d = vr - br
        marker = "↑" if d > 0 else ("↓" if d < 0 else "—")
        cat_rows.append((cat, n, br, vr, d, marker))

    lines = []
    lines.append("# Terminal-Bench 2.0 — Experimental Results\n")
    lines.append(f"**Dataset**: 89 tasks, stratified 25 train / 64 test  \n")
    lines.append(f"**Student**: `deepseek-v4-flash`, **Teacher**: `deepseek-v4-pro[1m]`\n\n")

    lines.append("## Test Set Results (64 tasks)\n\n")
    lines.append("```\n")
    lines.append(f"                       Student    Teacher    Serve+ACP\n")
    lines.append(f"PASS                      {len(sp):>2}         {len(tp):>2}          {len(vp):>2}\n")
    lines.append(f"FAIL (incl. ERROR)        {len(sf_total):>2}         {len(tf_total):>2}          {len(vf_total):>2}\n")
    lines.append(f"  - pure FAIL             {len(sf-se):>2}         {len(tf-te):>2}          {len(vf-ve):>2}\n")
    lines.append(f"  - FAIL ∩ ERROR          {len(sf&se):>2}         {len(tf&te):>2}          {len(vf&ve):>2}\n")
    lines.append(f"  - pure ERROR            {len(se-sf):>2}         {len(te-tf):>2}          {len(ve-vf):>2}\n")
    lines.append("──────────────────────────────────────────────────\n")
    lines.append(f"合计                      {TOTAL:>2}         {TOTAL:>2}          {TOTAL:>2}\n")
    lines.append(f"Pass Rate               {len(sp)/TOTAL*100:4.1f}%       {len(tp)/TOTAL*100:4.1f}%        {len(vp)/TOTAL*100:4.1f}%\n")
    lines.append("```\n\n")

    lines.append(f"### GAIN / LOSS\n\n")
    lines.append(f"| Metric | Count |\n")
    lines.append(f"|------|:--:|\n")
    lines.append(f"| GAIN (F→P) | {len(gain)} |\n")
    lines.append(f"| LOSS (P→F/ERR) | {len(loss)} |\n")
    lines.append(f"| Net | {len(gain)-len(loss):+d} |\n\n")

    if gain:
        lines.append("**GAIN tasks:**\n")
        for t in gain:
            lines.append(f"- {t} ({all_cats[t]})\n")
    if loss:
        lines.append("\n**LOSS tasks:**\n")
        for t in loss:
            lines.append(f"- {t} ({all_cats[t]})\n")

    lines.append("\n## Cost Analysis (DeepSeek Official Pricing)\n\n")
    lines.append("| | V4-Flash | V4-Pro |\n")
    lines.append("|------|:--:|:--:|\n")
    lines.append("| Input (cache miss) | $0.14/M | $0.435/M |\n")
    lines.append("| Input (cache hit) | $0.0028/M | $0.003625/M |\n")
    lines.append("| Output | $0.28/M | $0.87/M |\n\n")

    lines.append("### Token Usage (Test Set)\n\n")
    lines.append("```\n")
    lines.append(f"                         Student          Teacher          Student+ACP\n")
    lines.append(f"Input (prompt)         {s_tok['prompt']:>12,}  {t_tok['prompt']:>12,}   {v_tok['prompt']:>12,}\n")
    lines.append(f"Cache Read (hit)       {s_tok['cache_read']:>12,}  {t_tok['cache_read']:>12,}   {v_tok['cache_read']:>12,}\n")
    lines.append(f"Uncached (miss)        {max(0, s_tok['prompt']-s_tok['cache_read']):>12,}  {max(0, t_tok['prompt']-t_tok['cache_read']):>12,}   {max(0, v_tok['prompt']-v_tok['cache_read']):>12,}\n")
    lines.append(f"Output                 {s_tok['completion']:>12,}  {t_tok['completion']:>12,}   {v_tok['completion']:>12,}\n")
    s_cache = s_tok["cache_read"] / s_tok["prompt"] * 100 if s_tok["prompt"] else 0
    t_cache = t_tok["cache_read"] / t_tok["prompt"] * 100 if t_tok["prompt"] else 0
    v_cache = v_tok["cache_read"] / v_tok["prompt"] * 100 if v_tok["prompt"] else 0
    lines.append(f"Cache Hit Rate          {s_cache:>11.1f}%  {t_cache:>11.1f}%   {v_cache:>11.1f}%\n")
    lines.append("```\n\n")

    lines.append("### Cost Breakdown (Test Set)\n\n")
    lines.append("```\n")
    lines.append(f"                         Student          Teacher          Student+ACP\n")
    lines.append(f"Input (cache miss)     ${s_cost['miss_cost']:>9,.2f}       ${t_cost['miss_cost']:>9,.2f}        ${v_cost['miss_cost']:>9,.2f}\n")
    lines.append(f"Input (cache hit)      ${s_cost['hit_cost']:>9,.2f}       ${t_cost['hit_cost']:>9,.2f}        ${v_cost['hit_cost']:>9,.2f}\n")
    lines.append(f"Output                ${s_cost['output_cost']:>9,.2f}       ${t_cost['output_cost']:>9,.2f}        ${v_cost['output_cost']:>9,.2f}\n")
    lines.append(f"TOTAL                 ${s_cost['total']:>9,.2f}       ${t_cost['total']:>9,.2f}        ${v_cost['total']:>9,.2f}\n")
    lines.append(f"Avg per task           ${s_cost['total']/TOTAL:>9,.2f}       ${t_cost['total']/TOTAL:>9,.2f}        ${v_cost['total']/TOTAL:>9,.2f}\n")
    lines.append("```\n\n")

    # All-three-PASS cost
    if all_pass_costs:
        n_ap = len(all_pass_costs["student"])
        s_ap = sum(c["cost"] for c in all_pass_costs["student"])
        t_ap = sum(c["cost"] for c in all_pass_costs["teacher"])
        v_ap = sum(c["cost"] for c in all_pass_costs["serve"])
        lines.append(f"### Cost on All-Three-PASS Tasks ({n_ap} tasks)\n\n")
        lines.append("```\n")
        lines.append(f"                       Student    Teacher    Serve+ACP\n")
        lines.append(f"PASS in all 3              {n_ap}         {n_ap}          {n_ap}\n")
        lines.append(f"Avg Cost               ${s_ap/n_ap:>7,.2f}     ${t_ap/n_ap:>7,.2f}      ${v_ap/n_ap:>7,.2f}\n")
        lines.append(f"Total Cost             ${s_ap:>7,.2f}     ${t_ap:>7,.2f}      ${v_ap:>7,.2f}\n")
        lines.append("```\n\n")

    lines.append("## Per-Category Delta (Test Set)\n\n")
    lines.append(f"| Category | #Tasks | Baseline | Serve+ACP | Δ |\n")
    lines.append(f"|------|:--:|:--:|:--:|:--:|\n")
    for cat, n, br, vr, d, marker in cat_rows:
        if d != 0:
            lines.append(f"| {cat} | {n} | {br:.1f}% | {vr:.1f}% | **{d:+.1f}%** {marker} |\n")
        else:
            lines.append(f"| {cat} | {n} | {br:.1f}% | {vr:.1f}% | — |\n")

    return "".join(lines)


def main():
    args = parse_args()

    # Load split
    split_path = Path(args.split)
    if not split_path.is_absolute():
        split_path = PROJECT_DIR / "tb_harbor_2.0" / args.split
    with open(split_path) as f:
        split = json.load(f)
    test_set = set(split["test"].keys())

    # Resolve job directories
    def resolve_job(path_str):
        p = Path(path_str)
        if not p.is_absolute():
            p = PROJECT_DIR / "tb_harbor_2.0" / p
        if not p.exists():
            # Try finding nested job dir
            jds = sorted([d for d in p.iterdir() if d.is_dir()])
            if jds:
                return jds[-1]
        return p

    student_job = resolve_job(args.baseline_student)
    teacher_job = resolve_job(args.baseline_teacher)
    serve_job = resolve_job(args.serve)

    # Get results
    sp, sf, se, s_tok = get_results(student_job, test_set)
    tp, tf, te, t_tok = get_results(teacher_job, test_set)
    vp, vf, ve, v_tok = get_results(serve_job, test_set)

    # All-three-PASS
    all_pass = get_all_three_pass_tasks(sp, tp, vp, test_set)
    job_dirs = {
        "student": (student_job, "flash"),
        "teacher": (teacher_job, "pro"),
        "serve": (serve_job, "flash"),
    }
    all_pass_costs = compute_all_pass_cost(all_pass, job_dirs, test_set)

    # Generate markdown
    md = generate_md(args, split, sp, sf, se, s_tok, tp, tf, te, t_tok, vp, vf, ve, v_tok, all_pass, all_pass_costs)

    output_path = Path(args.output) if args.output else (PROJECT_DIR / "tb_harbor_2.0" / "RESULTS.md")
    output_path.write_text(md)
    print(f"Report written to: {output_path}")

    # Print summary to stdout
    print(f"\nQuick Summary:")
    print(f"  Student: {len(sp)}/{len(sp|sf|se)} = {len(sp)/64*100:.1f}%")
    print(f"  Teacher: {len(tp)}/{len(tp|tf|te)} = {len(tp)/64*100:.1f}%")
    print(f"  Serve:   {len(vp)}/{len(vp|vf|ve)} = {len(vp)/64*100:.1f}%")


if __name__ == "__main__":
    main()

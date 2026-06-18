#!/bin/bash
# Run student or teacher baseline on TB 2.0 tasks via Harbor.
# Usage:
#   bash scripts/run_baseline.sh --model student --split train    # train only
#   bash scripts/run_baseline.sh --model teacher --split all      # all 89 tasks
#   bash scripts/run_baseline.sh --model student --n-concurrent 8 --timeout-multiplier 6
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
HARBOR="$PROJECT_DIR/.venv_harbor/bin/harbor"

TASKS_DIR="$PROJECT_DIR/tb_harbor_2.0/tasks"
TRAIN_FILE="$PROJECT_DIR/tb_harbor_2.0/train.txt"
TEST_FILE="$PROJECT_DIR/tb_harbor_2.0/test.txt"

# Defaults
MODEL="student"
SPLIT="all"
N_CONCURRENT=4
TIMEOUT_MULTIPLIER=4
OUTPUT_DIR=""
EXTRA_ARGS=""

usage() {
    cat <<EOF
Usage: $0 --model student|teacher [options]

Options:
  --model <name>            student (deepseek-v4-flash) or teacher (deepseek-v4-pro)
  --split <name>            train, test, or all (default: all)
  --n-concurrent <n>        Concurrent trials (default: 4)
  --timeout-multiplier <n>  Timeout multiplier (default: 4)
  --output-dir <path>       Custom output directory
  --extra <args>            Extra flags passed to harbor run
  --help                    Show this message
EOF
    exit 0
}

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --model) MODEL="$2"; shift 2 ;;
        --split) SPLIT="$2"; shift 2 ;;
        --n-concurrent) N_CONCURRENT="$2"; shift 2 ;;
        --timeout-multiplier) TIMEOUT_MULTIPLIER="$2"; shift 2 ;;
        --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        --extra) EXTRA_ARGS="$2"; shift 2 ;;
        --help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

# Resolve model config
case "$MODEL" in
    student|flash)
        ENV_FILE="$PROJECT_DIR/configs/weak.env"
        HARBOR_MODEL="deepseek-v4-flash"
        JOB_NAME="baseline_student"
        ;;
    teacher|pro)
        ENV_FILE="$PROJECT_DIR/configs/strong.env"
        HARBOR_MODEL="deepseek-v4-pro"
        JOB_NAME="baseline_teacher"
        ;;
    *) echo "Unknown model: $MODEL (use student or teacher)"; exit 1 ;;
esac

# Resolve split
INCLUDE_FLAGS=""
case "$SPLIT" in
    train)
        while read -r task; do
            [ -n "$task" ] && INCLUDE_FLAGS="$INCLUDE_FLAGS -i $task"
        done < "$TRAIN_FILE"
        JOB_NAME="${JOB_NAME}_train"
        ;;
    test)
        while read -r task; do
            [ -n "$task" ] && INCLUDE_FLAGS="$INCLUDE_FLAGS -i $task"
        done < "$TEST_FILE"
        JOB_NAME="${JOB_NAME}_test"
        ;;
    all)
        JOB_NAME="${JOB_NAME}_all"
        ;;
    *) echo "Unknown split: $SPLIT (use train, test, or all)"; exit 1 ;;
esac

# Output directory
if [ -z "$OUTPUT_DIR" ]; then
    OUTPUT_DIR="$PROJECT_DIR/tb_harbor_2.0/jobs_${JOB_NAME}"
fi

echo "============================================"
echo "  Baseline: $MODEL ($HARBOR_MODEL)"
echo "  Split:    $SPLIT"
echo "  Concurrent: $N_CONCURRENT"
echo "  Timeout:  ${TIMEOUT_MULTIPLIER}x"
echo "  Output:   $OUTPUT_DIR"
echo "============================================"
echo ""

# Run via Harbor
rm -rf "$OUTPUT_DIR"

# shellcheck disable=SC2086
$HARBOR run \
    --path "$TASKS_DIR" \
    --agent claude-code \
    --model "$HARBOR_MODEL" \
    --env-file "$ENV_FILE" \
    --n-concurrent "$N_CONCURRENT" \
    --jobs-dir "$OUTPUT_DIR" \
    --timeout-multiplier "$TIMEOUT_MULTIPLIER" \
    --quiet \
    -y \
    $INCLUDE_FLAGS \
    $EXTRA_ARGS

echo ""
echo "Baseline complete. Results: $OUTPUT_DIR"

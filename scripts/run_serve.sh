#!/bin/bash
# Serve: deploy curated ACP to test tasks and run student CC via Harbor.
# Usage:
#   bash scripts/run_serve.sh --acp-dir curated_acp [--n-concurrent 4]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
HARBOR="$PROJECT_DIR/.venv_harbor/bin/harbor"

TASKS_DIR="$PROJECT_DIR/tb_harbor_2.0/tasks"
TEST_FILE="$PROJECT_DIR/tb_harbor_2.0/test.txt"
SPLIT_FILE="$PROJECT_DIR/tb_harbor_2.0/split.json"
WEAK_ENV="$PROJECT_DIR/configs/weak.env"

ACP_DIR=""
N_CONCURRENT=4
TIMEOUT_MULTIPLIER=4
OUTPUT_DIR=""
SERVE_TASKS_DIR=""

usage() {
    cat <<EOF
Usage: $0 --acp-dir <curated_acp> [options]

Options:
  --acp-dir <path>          Directory with curated ACP (<category>/CLAUDE.md)
  --n-concurrent <n>        Concurrent trials (default: 4)
  --timeout-multiplier <n>  Timeout multiplier (default: 4)
  --output-dir <path>       Custom output directory for Harbor job
  --help                    Show this message
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --acp-dir) ACP_DIR="$2"; shift 2 ;;
        --n-concurrent) N_CONCURRENT="$2"; shift 2 ;;
        --timeout-multiplier) TIMEOUT_MULTIPLIER="$2"; shift 2 ;;
        --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        --help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

if [ -z "$ACP_DIR" ]; then
    echo "Error: --acp-dir is required"
    usage
fi

# Resolve paths
if [ ! -d "$ACP_DIR" ]; then
    ACP_DIR="$PROJECT_DIR/tb_harbor_2.0/$ACP_DIR"
fi
if [ ! -d "$ACP_DIR" ]; then
    echo "Error: ACP directory not found: $ACP_DIR"
    exit 1
fi

# Create serve tasks directory with ACP deployed
SERVE_TASKS_DIR="$PROJECT_DIR/tb_harbor_2.0/serve_tasks"
rm -rf "$SERVE_TASKS_DIR"
mkdir -p "$SERVE_TASKS_DIR"

# Get categories that have ACP
HAS_ACP_CATS=$(ls "$ACP_DIR" 2>/dev/null || true)

DEPLOYED=0
NO_ACP=0

echo "Deploying ACP to test tasks..."
while read -r task; do
    [ -z "$task" ] && continue
    src="$TASKS_DIR/$task"
    [ ! -d "$src" ] && continue
    dst="$SERVE_TASKS_DIR/$task"
    cp -r "$src" "$dst"

    # Get task category from split.json
    cat=$(python3 -c "import json; s=json.load(open('$SPLIT_FILE')); print(s['test'].get('$task', ''))" 2>/dev/null || echo "")

    if [ -n "$cat" ] && echo "$HAS_ACP_CATS" | grep -q "^${cat}$"; then
        acp_claude="$ACP_DIR/$cat/CLAUDE.md"
        if [ -f "$acp_claude" ]; then
            cp "$acp_claude" "$dst/CLAUDE.md"
            DEPLOYED=$((DEPLOYED + 1))
        fi
    else
        NO_ACP=$((NO_ACP + 1))
        echo "  [no ACP] $task ($cat)"
    fi
done < "$TEST_FILE"

echo "  Deployed ACP to $DEPLOYED tasks, $NO_ACP without ACP"

# Output directory
if [ -z "$OUTPUT_DIR" ]; then
    OUTPUT_DIR="$PROJECT_DIR/tb_harbor_2.0/jobs_serve"
fi

echo ""
echo "============================================"
echo "  Serve: Student + Curated ACP"
echo "  ACP:     $ACP_DIR"
echo "  Tasks:   $DEPLOYED with ACP, $NO_ACP without"
echo "  Output:  $OUTPUT_DIR"
echo "============================================"
echo ""

rm -rf "$OUTPUT_DIR"

$HARBOR run \
    --path "$SERVE_TASKS_DIR" \
    --agent claude-code \
    --model deepseek-v4-flash \
    --env-file "$WEAK_ENV" \
    --n-concurrent "$N_CONCURRENT" \
    --jobs-dir "$OUTPUT_DIR" \
    --timeout-multiplier "$TIMEOUT_MULTIPLIER" \
    --quiet \
    -y

echo ""
echo "Serve complete. Results: $OUTPUT_DIR"

#!/bin/bash
# inject-skill.sh — per-project skill injection helper.
#
# Skills are now served globally via /upskill-run (interactive) or auto-mode
# keyword matching — no per-project file sync needed.
#
# Usage: inject-skill.sh [--help]

set -euo pipefail

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    echo "Skills are served globally via /upskill-run and auto-mode keyword matching."
    echo "This script is a no-op placeholder kept for hook compatibility."
    exit 0
fi

# No-op: skill content is loaded on-demand via /upskill-run or auto-mode matching

#!/bin/bash
# Upskill CC Integration — Bootstrap
#
# Downloads the /upskill-init skill (and companion skills).
# After this, open Claude Code and run /upskill-init to complete setup.
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/HKUDS/Upskill/main/cc-integration/bootstrap.sh | bash

set -euo pipefail

REPO="${UPSKILL_REPO:-https://raw.githubusercontent.com/HKUDS/Upskill/main/cc-integration}"

# Install to both user-level and project-level so CC finds them in any project
USER_SKILLS="$HOME/.claude/skills"
PROJECT_SKILLS="$(pwd)/.claude/skills"
mkdir -p "$USER_SKILLS" "$PROJECT_SKILLS"

echo "Upskill Bootstrap"
echo "=================="
echo ""

# Download management skills (directory-based format like install.sh)
for skill in upskill-init upskill-list upskill-build upskill-status upskill-remove upskill-mode upskill-model upskill-configure upskill-uninstall upskill-run; do
    mkdir -p "$USER_SKILLS/$skill" "$PROJECT_SKILLS/$skill"
    curl -sSL "$REPO/skills/${skill}.md" -o "$USER_SKILLS/$skill/SKILL.md"
    cp "$USER_SKILLS/$skill/SKILL.md" "$PROJECT_SKILLS/$skill/SKILL.md"
    echo "  ✓ /${skill}"
done

echo ""
echo "Done. Open Claude Code and run: /upskill-init"
echo "(If /upskill-init is not recognized, restart CC or re-run this bootstrap"
echo " in your target project directory.)"
echo ""

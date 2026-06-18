#!/bin/bash
# Upskill Pipeline Test — no-CC automated test
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CC_DIR="$(dirname "$SCRIPT_DIR")"
TEST_DIR="/tmp/upskill-test-$$"
PASS=0
FAIL=0

cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

mkdir -p "$TEST_DIR/upskill-store/.building"
export HOME="$TEST_DIR"
export UPSKILL_STORE="$TEST_DIR/upskill-store"

check() {
    local msg="${*:2}"
    if [ "$1" = "0" ]; then
        echo "  ✓ $msg"; PASS=$((PASS + 1))
    else
        echo "  ✗ FAIL: $msg (exit=$1)"; FAIL=$((FAIL + 1))
    fi
}

echo ""
echo "=============================================="
echo "  Upskill Pipeline Test"
echo "=============================================="

# ---- 1. Config ----
echo ""; echo "--- 1. Config ---"
cat > "$TEST_DIR/upskill.conf" << 'EOF'
UPSKILL_TEACHER="deepseek-v4-pro[1m]"
UPSKILL_STUDENT="deepseek-v4-flash"
UPSKILL_SERVE_MODE="advisory"
EOF
[ -f "$TEST_DIR/upskill.conf" ]; check $? "upskill.conf created"

# ---- 2. Mock skill ----
echo ""; echo "--- 2. Mock skill ---"
MOCK_LOG="$TEST_DIR/mock_phase3.log"
cat > "$MOCK_LOG" << 'MOCKEOF'
===BEGIN_FILE: SKILL.md===
---
name: skill_test
description: For shell scripting tasks — always quote variables and use shellcheck
metadata:
  category: software-engineering
  base_model: deepseek-v4-flash
  trigger_keywords: [bash, shell, script, quoting]
---

# Domain Knowledge
## Common Pitfalls
- Using `cat file | grep pattern` instead of `grep pattern file`
- Forgetting to quote variables

## Correct Approach
1. Always quote shell variables
2. Use `grep pattern file` directly
3. Run `shellcheck` on scripts

# Step-by-Step
1. Run shellcheck your_script.sh
2. Fix SC2086 warnings (unquoted variables)
3. Test with set -euo pipefail

# Feedback / Lessons
Rule: Always quote shell variables with double quotes
Why: Unquoted variables undergo word splitting
How to apply: Use "$var" instead of $var. Run shellcheck.
===END_FILE: SKILL.md===

===SKILL_DESCRIPTION===
For shell scripting tasks: always quote variables, use shellcheck, and avoid useless cat pipes. Apply to any bash/shell task.
===SKILL_DESCRIPTION===
MOCKEOF
[ -f "$MOCK_LOG" ]; check $? "Mock skill created"

# ---- 3. Parse ----
echo ""; echo "--- 3. Parse ---"
SKILL_OUT="$TEST_DIR/skill_output"
mkdir -p "$SKILL_OUT"
python3 "$CC_DIR/parse-skill.py" "$MOCK_LOG" "$SKILL_OUT" --task-name "mock" > /dev/null
[ -f "$SKILL_OUT/SKILL.md" ]; check $? "SKILL.md parsed"
[ -f "$SKILL_OUT/description.txt" ]; check $? "description.txt parsed"

# ---- 4. Store ----
echo ""; echo "--- 4. Store ---"
CAT="software-engineering"
BID="skill_20260605_000001"
STORE_DIR="$UPSKILL_STORE/$CAT/$BID"
mkdir -p "$STORE_DIR"
cp "$SKILL_OUT/SKILL.md" "$STORE_DIR/"
cp "$SKILL_OUT/description.txt" "$STORE_DIR/"

bash "$CC_DIR/upskill-store.sh" add --category "$CAT" --skill-id "$BID" \
    --prompt "create a bash script to parse csv files" \
    --base-model "deepseek-v4-flash" --skill-dir "$SKILL_OUT" --store="$UPSKILL_STORE"
[ -f "$STORE_DIR/SKILL.md" ]; check $? "Stored: SKILL.md"
[ -f "$UPSKILL_STORE/$CAT/manifest.yaml" ]; check $? "Stored: manifest"

# ---- 5. Sync ----
echo ""; echo "--- 5. Sync ---"
bash "$CC_DIR/upskill-store.sh" sync --store="$UPSKILL_STORE"
GLOBAL=$(cat "$UPSKILL_STORE/CLAUDE.md")
[ -f "$UPSKILL_STORE/CLAUDE.md" ]; check $? "Global CLAUDE.md generated"

# ---- 6. Verify global CLAUDE.md ----
echo ""; echo "--- 6. Verify CLAUDE.md ---"
echo "$GLOBAL" | grep -q "Management Commands"; check $? "Management section"
echo "$GLOBAL" | grep -q "Skill Matching Protocol"; check $? "Skill Matching Protocol"
echo "$GLOBAL" | grep -q "$CAT"; check $? "Category listed"
echo "$GLOBAL" | grep -q "$BID"; check $? "Skill ID listed"
echo "$GLOBAL" | grep -q "deepseek-v4-flash"; check $? "Base model listed"
echo "$GLOBAL" | grep -q "upskill-store.sh list"; check $? "Management: list"
echo "$GLOBAL" | grep -q "upskill-store.sh status"; check $? "Management: status"
echo "$GLOBAL" | grep -q "upskill-store.sh remove"; check $? "Management: remove"
echo "$GLOBAL" | grep -q "SKILL.md"; check $? "SKILL.md path referenced"

# ---- 7. Management CLI ----
echo ""; echo "--- 7. CLI ---"
echo "$(bash "$CC_DIR/upskill-store.sh" list --store="$UPSKILL_STORE")" | grep -q "$CAT"; check $? "list shows category"
echo "$(bash "$CC_DIR/upskill-store.sh" status --store="$UPSKILL_STORE")" | grep -q "1 skills"; check $? "status shows count"
echo "$(bash "$CC_DIR/upskill-store.sh" search "bash" --store="$UPSKILL_STORE")" | grep -q "$BID"; check $? "search finds skill"
bash "$CC_DIR/upskill-store.sh" help > /dev/null 2>&1; check $? "help works"

# ---- 8. SKILL.md content ----
echo ""; echo "--- 8. SKILL.md ---"
[ -f "$STORE_DIR/SKILL.md" ]; check $? "SKILL.md exists"
grep -q 'shellcheck' "$STORE_DIR/SKILL.md"; check $? "SKILL.md has shellcheck guidance"

# ---- 9. Remove ----
echo ""; echo "--- 9. Remove ---"
bash "$CC_DIR/upskill-store.sh" remove --category "$CAT" --skill-id "$BID" --store="$UPSKILL_STORE"
[ ! -d "$STORE_DIR" ]; check $? "Skill directory removed"
bash "$CC_DIR/upskill-store.sh" sync --store="$UPSKILL_STORE"
GLOBAL2=$(cat "$UPSKILL_STORE/CLAUDE.md")
echo "$GLOBAL2" | grep -qv "$BID"; check $? "CLAUDE.md updated (skill gone)"

# ---- 10. Multi-skill ----
echo ""; echo "--- 10. Multi-skill ---"
for i in 1 2; do
    BID2="skill_test_00${i}"
    BDIR2="$UPSKILL_STORE/$CAT/$BID2"
    mkdir -p "$BDIR2"
    cat > "$BDIR2/SKILL.md" << MEMEOF
---
name: skill_test_00${i}
description: Rule $i
metadata: {base_model: flash, category: $CAT}
---
# Domain Knowledge
Test skill $i
# Step-by-Step
1. Run test $i
# Feedback / Lessons
Rule: Rule $i
Why: Testing
How to apply: Test $i
MEMEOF
    bash "$CC_DIR/upskill-store.sh" add --category "$CAT" --skill-id "$BID2" \
        --prompt "test $i" --base-model "flash" --skill-dir "$BDIR2" --store="$UPSKILL_STORE"
done
bash "$CC_DIR/upskill-store.sh" sync --store="$UPSKILL_STORE"
GLOBAL3=$(cat "$UPSKILL_STORE/CLAUDE.md")
echo "$GLOBAL3" | grep -q "2 skills"; check $? "Multi-skill: '2 skills'"

# ---- 11. Idempotent sync ----
echo ""; echo "--- 11. Idempotent ---"
bash "$CC_DIR/upskill-store.sh" sync --store="$UPSKILL_STORE"
bash "$CC_DIR/upskill-store.sh" sync --store="$UPSKILL_STORE"
[ -f "$UPSKILL_STORE/CLAUDE.md" ]; check $? "Double sync OK"

# ---- 12. Path traversal ----
echo ""; echo "--- 12. Security ---"
cat > "$TEST_DIR/trav.log" << 'TRAVEOF'
===BEGIN_FILE: ../../etc/passwd===
malicious content
===END_FILE: ../../etc/passwd===
TRAVEOF
python3 "$CC_DIR/parse-skill.py" "$TEST_DIR/trav.log" "$TEST_DIR/trav_out" --task-name "t" 2>&1 | grep -q "REJECTED"
check $? "Path traversal blocked"

# ---- Results ----
echo ""
echo "=============================================="
echo "  Results: $PASS passed, $FAIL failed"
echo "=============================================="
[ "$FAIL" -eq 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit $FAIL

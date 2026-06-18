#!/bin/bash
# skill store management CLI.
#
# Usage:
#   upskill-store.sh add    --category <c> --skill-id <id> --prompt <p> --store <s> --skill-dir <d>
#   upskill-store.sh list   [--store <s>] [--category <c>]
#   upskill-store.sh search <query> [--store <s>]
#   upskill-store.sh status [--store <s>]
#   upskill-store.sh remove --category <c> --skill-id <id> [--store <s>]
#   upskill-store.sh sync  [--store <s>]
set -euo pipefail

UPSKILL_STORE="${UPSKILL_STORE:-$HOME/.claude/upskill-store}"

log() { echo "[upskill-store] $*"; }

cmd_list() {
    local store="${1:-$UPSKILL_STORE}"
    log "Skills in $store:"
    echo ""
    for cat_dir in "$store"/*/; do
        [ -d "$cat_dir" ] || continue
        cat_name=$(basename "$cat_dir")
        [[ "$cat_name" == .* ]] && continue

        local skill_count=0
        for entry_dir in "$cat_dir/skill_"*/; do
            [ -d "$entry_dir" ] && skill_count=$((skill_count + 1))
        done

        echo "  [$cat_name] ($skill_count skill$( [ "$skill_count" -ne 1 ] && echo 's'))"
        if [ -f "$cat_dir/manifest.yaml" ]; then
            grep 'base_model:' "$cat_dir/manifest.yaml" 2>/dev/null | head -1 | sed 's/^/    /'
        fi
        for entry_dir in "$cat_dir/skill_"*/; do
            [ -d "$entry_dir" ] || continue
            local bid=$(basename "$entry_dir")
            echo "    - $bid"
        done
        echo ""
    done
}

cmd_search() {
    local query="${1:?Usage: $0 search <query> [--store <s>]}"
    local store="${2:-$UPSKILL_STORE}"
    log "Searching for '$query' in $store..."
    echo ""

    for cat_dir in "$store"/*/; do
        [ -d "$cat_dir" ] || continue
        cat_name=$(basename "$cat_dir")

        if [ -f "$cat_dir/manifest.yaml" ]; then
            if grep -qi "$query" "$cat_dir/manifest.yaml" 2>/dev/null; then
                echo "  [$cat_name] (manifest match)"
                grep -i "$query" "$cat_dir/manifest.yaml" 2>/dev/null | sed 's/^/    /'
            fi
        fi

        for entry_dir in "$cat_dir/skill_"*/; do
            [ -d "$entry_dir" ] || continue
            local bid=$(basename "$entry_dir")
            if [ -f "$entry_dir/SKILL.md" ] && grep -qi "$query" "$entry_dir/SKILL.md" 2>/dev/null; then
                echo "  [$cat_name/$bid] SKILL.md match:"
                grep -i -A1 -B1 "$query" "$entry_dir/SKILL.md" 2>/dev/null | head -6 | sed 's/^/    /'
            fi
        done
    done
    echo ""
}

cmd_add() {
    local category="" skill_id="" prompt="" store="$UPSKILL_STORE" skill_dir="" base_model="unknown" description=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --category) category="$2"; shift 2 ;;
            --skill-id) skill_id="$2"; shift 2 ;;
            --prompt) prompt="$2"; shift 2 ;;
            --store) store="$2"; shift 2 ;;
            --skill-dir) skill_dir="$2"; shift 2 ;;
            --base-model) base_model="$2"; shift 2 ;;
            --description) description="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    local store_dir="$store/$category"
    local manifest="$store_dir/manifest.yaml"
    local ts=$(date +"%Y-%m-%dT%H:%M:%S")

    mkdir -p "$store_dir"

    # Read description from skill_dir if not explicitly provided
    if [ -z "$description" ] && [ -n "$skill_dir" ] && [ -f "$skill_dir/description.txt" ]; then
        description=$(head -1 "$skill_dir/description.txt" | cut -c1-300)
    fi
    # Fallback: use prompt summary
    if [ -z "$description" ]; then
        description=$(printf "%s" "$prompt" | cut -c1-200)
    fi

    # Extract meaningful trigger keywords from prompt
    local keywords=""
    keywords=$(printf "%s" "$prompt" | python3 -c "
import sys, re
text = sys.stdin.read()
# Split into words, keep alphanumeric + underscores + dots
words = re.findall(r'[a-zA-Z][a-zA-Z0-9_.]{2,}', text.lower())
# Filter out common boilerplate/stop words
stop = {'the','and','for','that','this','with','from','your','have','are','not','all','was',
        'will','can','has','its','you','use','end','cat','out','one','see','new','now','too',
        'echo','file','test','data','tmp','txt','csv','task','com','org','net','http','https',
        'brewresult','pass','fail','result','output','input','line','should','each','any',
        '注意','提示','验证','根据','准备','输出','格式','支持','使用','创建','完成',
        '以下','最后','全部','目录','任务','测试','文件','数据'}
words = [w for w in words if w not in stop]
# Count frequency for relevance
from collections import Counter
counts = Counter(words)
# Score: longer words + higher frequency = more relevant
scored = sorted(counts.items(), key=lambda x: (-len(x[0]), -x[1]))
top = [w for w,_ in scored[:15]]
# Always include the category
cat = '$category'.lower().replace('_','-')
if cat not in top:
    top.insert(0, cat)
print(','.join(top[:15]))
" 2>/dev/null)
    [ -z "$keywords" ] && keywords="$category"

    if [ ! -f "$manifest" ]; then
        cat > "$manifest" << EOF
# Upskill Skill Manifest — $category
category: $category
created: $ts
entries:
EOF
    fi

    # Escape quotes in description (bash 3.2 compat)
    DESC_ESCAPED=$(printf '%s' "$description" | sed 's/"/\\"/g')
    # Append entry
    cat >> "$manifest" << EOF
  - id: $skill_id
    at: $ts
    base_model: $base_model
    trigger_keywords: [$keywords]
    description: "$DESC_ESCAPED"
    files:
EOF

    if [ -n "$skill_dir" ] && [ -d "$skill_dir" ]; then
        find "$skill_dir" -type f | while IFS= read -r f; do
            rel=$(printf "%s" "$f" | sed "s|^$skill_dir/||")
            echo "      - $rel" >> "$manifest"
        done
    fi

    log "Added $skill_id to [$category]"
}

cmd_remove() {
    local category="" skill_id="" store="$UPSKILL_STORE"
    while [ $# -gt 0 ]; do
        case "$1" in
            --category) category="$2"; shift 2 ;;
            --skill-id) skill_id="$2"; shift 2 ;;
            --store) store="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [ -z "$category" ]; then
        log "ERROR: --category required."
        exit 1
    fi

    local store_dir="$store/$category"
    local manifest="$store_dir/manifest.yaml"

    if [ ! -d "$store_dir" ]; then
        log "Category [$category] does not exist."
        exit 1
    fi

    if [ -n "$skill_id" ]; then
        # Remove specific skill directory
        local entry_dir="$store_dir/$skill_id"
        if [ -d "$entry_dir" ]; then
            rm -rf "$entry_dir"
            log "Removed skill $skill_id from [$category]"
        else
            log "Skill $skill_id not found in [$category]"
        fi

        # Remove entry from category manifest
        if [ -f "$manifest" ]; then
            MANIFEST="$manifest" SKILL_ID="$skill_id" python3 -c "
import os, sys
manifest = os.environ['MANIFEST']
skill_id = os.environ['SKILL_ID']
with open(manifest) as f:
    lines = f.readlines()
out = []
skip = False
for line in lines:
    if line.startswith('  - id: ' + skill_id):
        skip = True
        continue
    if skip:
        if line.startswith('  - id:') or line.startswith('category:'):
            skip = False
            out.append(line)
        continue
    out.append(line)
with open(manifest, 'w') as f:
    f.writelines(out)
"
            log "  manifest updated"
        fi

        # Clean up per-skill global skills (legacy flat files + directory format)
        local skill_suffix="${category}-${skill_id}"
        rm -f "$HOME/.claude/skills/upskill-${skill_suffix}.md" 2>/dev/null || true
        rm -rf "$HOME/.claude/skills/upskill-${skill_suffix}" 2>/dev/null || true
        rm -f "$HOME/.claude/skills/upskill-memories-${skill_suffix}.md" 2>/dev/null || true
        rm -rf "$HOME/.claude/skills/upskill-memories-${skill_suffix}" 2>/dev/null || true
        rm -f "$HOME/.claude/skills/solve-task-${skill_suffix}.md" 2>/dev/null || true
        rm -rf "$HOME/.claude/skills/solve-task-${skill_suffix}" 2>/dev/null || true
    else
        # Remove entire category
        rm -rf "$store_dir"
        log "Removed entire category [$category]"
        # Clean up all skills matching this category
        rm -f "$HOME/.claude/skills/upskill-${category}-"*.md 2>/dev/null || true
        rm -rf "$HOME/.claude/skills/upskill-${category}-"* 2>/dev/null || true
        rm -f "$HOME/.claude/skills/upskill-memories-${category}-"*.md 2>/dev/null || true
        rm -rf "$HOME/.claude/skills/upskill-memories-${category}-"* 2>/dev/null || true
        rm -f "$HOME/.claude/skills/solve-task-${category}-"*.md 2>/dev/null || true
        rm -rf "$HOME/.claude/skills/solve-task-${category}-"* 2>/dev/null || true
    fi

    # Remove empty category dir
    if [ -d "$store_dir" ] && [ -z "$(ls -A "$store_dir" 2>/dev/null)" ]; then
        rmdir "$store_dir" 2>/dev/null || true
    fi

    # Rebuild global CLAUDE.md
    log "Rebuilding global skill index..."
    cmd_sync "$store"

    log "Remove complete."
}

cmd_sync() {
    local store="${1:-$UPSKILL_STORE}"
    local global_md="$store/CLAUDE.md"

    # Read serve mode from config
    local serve_mode="interactive"
    if [ -f "$HOME/.claude/upskill.conf" ]; then
        source "$HOME/.claude/upskill.conf" 2>/dev/null || true
        serve_mode="${UPSKILL_SERVE_MODE:-interactive}"
    fi
    # Map legacy modes to current equivalents
    case "$serve_mode" in
        interactive|auto) ;;  # current modes, keep as-is
        *) serve_mode="interactive" ;;  # legacy (advisory, etc.) → interactive
    esac

    echo "# Upskill Skill Library" > "$global_md"
    echo "<!-- Generated $(date +%Y-%m-%dT%H:%M:%S) -->" >> "$global_md"
    echo "" >> "$global_md"
    echo "Serve mode: **$serve_mode**." >> "$global_md"
    if [ "$serve_mode" = "interactive" ]; then
        echo "Use \`/upskill-run\` to browse skills, get recommendations, and apply guidance." >> "$global_md"
    elif [ "$serve_mode" = "auto" ]; then
        echo "Skills are auto-matched on every prompt. Confirm before applying." >> "$global_md"
    fi
    echo "" >> "$global_md"
    {
        echo "### Management Commands"
        echo ""
        echo "Run these to manage your skill library:"
        echo '- List Skills: `bash ~/.claude/hooks/upskill-store.sh list`'
        echo '- Status:    `bash ~/.claude/hooks/upskill-store.sh status`'
        echo '- Search:    `bash ~/.claude/hooks/upskill-store.sh search <keyword>`'
        echo '- Remove:    `bash ~/.claude/hooks/upskill-store.sh remove --category <c> --skill-id <id>`'
        echo '- Build:     `bash ~/.claude/hooks/upskill-build.sh "<prompt>" "<failure-log>" "<category>"`'
        echo '- Switch mode: edit ~/.claude/upskill.conf then `bash ~/.claude/hooks/upskill-store.sh sync`'
        echo ""
    } >> "$global_md"

    if [ "$serve_mode" = "interactive" ]; then
        {
            echo "### Skill Matching Protocol (interactive mode)"
            echo ""
            echo "The user invokes \`/upskill-run\` to start the skill workflow."
            echo "When \`/upskill-run\` is called:"
            echo "1. Collect the task if not already provided."
            echo "2. Run \`bash ~/.claude/hooks/upskill-store.sh list\` to get all skills."
            echo "3. Check \`~/.claude/upskill-store/.building/skill_match.txt\` for keyword matches."
            echo "4. Present ALL skills, marking matched ones with ★ as recommendations."
            echo "5. Let the user pick (by number, comma-separated) or \"none\" to skip."
            echo "6. For each selected skill, if validated model ≠ current model:"
            echo "   ask \"Switch to <model>? [Y/n]\". If yes, tell the user to run"
            echo "   \`/model\` and select <model>, then reply \"done\". Wait for them."
            echo "   (Claude cannot invoke /model — it is a TUI command.)"
            echo "7. Read the skill's SKILL.md (contains Domain Knowledge, Step-by-Step, and Feedback), then execute the task."
            echo ""
            echo "The hook silently saves keyword matches to skill_match.txt for use by /upskill-run."
        } >> "$global_md"
    else
        {
            echo "### Skill Matching Protocol (auto mode)"
            echo ""
            echo "**CRITICAL — BEFORE implementing any task, scan the skills below.**"
            echo "Compare the user's task against each skill's description and trigger keywords."
            echo "If any skill matches (same language, similar task structure, same bug class):"
            echo "1. STOP. Do NOT write any code yet."
            echo "2. Tell the user: \"Found a relevant skill: <skill_id> — <description>\""
            echo "3. Ask: \"Apply this skill? [Y/n]\""
            echo "4. If confirmed and validated model ≠ current model:"
            echo "   ask \"Switch to <model>? [Y/n]\". If yes, tell the user to run"
            echo "   \`/model\` and select <model>, then reply \"done\". Wait for them."
            echo "   (Claude cannot invoke /model — it is a TUI command.)"
            echo "5. Read the referenced SKILL.md (contains Domain Knowledge, Steps, and Feedback) BEFORE coding."
            echo "6. If declined, proceed without skill guidance."
            echo ""
            echo "This check is NOT optional — always scan before your first action on any task."
        } >> "$global_md"
    fi

    local synced=0
    for cat_dir in "$store"/*/; do
        [ -d "$cat_dir" ] || continue
        local cat_name
        cat_name=$(basename "$cat_dir")
        [[ "$cat_name" == .* ]] && continue

        local cat_manifest="$cat_dir/manifest.yaml"
        [ -f "$cat_manifest" ] || continue

        # Collect category-level metadata from all skills
        local triggers base_model skill_ids=""
        triggers=$(grep 'trigger_keywords:' "$cat_manifest" 2>/dev/null \
            | sed 's/.*trigger_keywords: *\[//;s/\]//' | tr ',' '\n' | sed 's/^ *//' | sort -u | tr '\n' ',' | sed 's/,$//' || true)
        [ -z "$triggers" ] && triggers="$cat_name"
        base_model=$(grep 'base_model:' "$cat_manifest" 2>/dev/null | head -1 | sed 's/.*base_model: *//' || echo "unknown")

        # Count skills and build skill list
        local skill_count=0
        local skill_list=""
        for entry_dir in "$cat_dir/skill_"*/; do
            [ -d "$entry_dir" ] || continue
            skill_id=$(basename "$entry_dir")
            [ -z "$skill_id" ] && continue

            # Extract per-skill description (from manifest) or fall back to SKILL.md / CLAUDE.md
            local summary=""
            # Try manifest description first (search 10 lines after skill id)
            if [ -f "$cat_manifest" ]; then
                summary=$(grep -A10 "id: $skill_id" "$cat_manifest" 2>/dev/null | grep 'description:' | head -1 | sed 's/.*description: *"//;s/"$//' | cut -c1-250 || true)
            fi
            # Fallback: SKILL.md frontmatter description
            if [ -z "$summary" ] && [ -f "$entry_dir/SKILL.md" ]; then
                summary=$(grep '^description:' "$entry_dir/SKILL.md" 2>/dev/null | head -1 | sed 's/^description: *//' | cut -c1-200 || true)
            fi
            # Fallback: SKILL.md first non-header content
            if [ -z "$summary" ] && [ -f "$entry_dir/SKILL.md" ]; then
                summary=$(grep -v '^#' "$entry_dir/SKILL.md" 2>/dev/null \
                    | grep -v '^$' | grep -v '^\`\`\`' | grep -v '^---$' \
                    | head -3 | sed 's/^[[:space:]]*//' | tr '\n' ' ' | sed 's/  */ /g' | cut -c1-200 || true)
            fi
            # Fallback: old-format CLAUDE.md summary
            if [ -z "$summary" ] && [ -f "$entry_dir/CLAUDE.md" ]; then
                summary=$(grep -v '^#' "$entry_dir/CLAUDE.md" 2>/dev/null \
                    | grep -v '^$' | grep -v '^\`\`\`' \
                    | head -3 | sed 's/^[[:space:]]*//' | tr '\n' ' ' | sed 's/  */ /g' | cut -c1-200 || true)
            fi
            [ -z "$summary" ] && summary="Task guidance for $cat_name"

            skill_count=$((skill_count + 1))

            local skill_path="$store/$cat_name/$skill_id"
            local mem_info=""
            [ -d "$entry_dir/memory" ] && [ -n "$(ls "$entry_dir/memory/"*.md 2>/dev/null)" ] && mem_info=" + memory"

            skill_list="${skill_list}  - \`$skill_id\` — $summary\n"
            skill_list="${skill_list}    → Read \`${skill_path}/SKILL.md\` for pitfalls, steps & lessons\n"
        done

        # Build mode-specific note
        local model_note
        model_note="**Model:** Validated on \`$base_model\`. For best results, use this model."

        # Category entry in global CLAUDE.md
        {
            echo ""
            echo "<!-- UPSKILL:$cat_name -->"
            echo "## Skill: $cat_name ($skill_count skill$( [ "$skill_count" -ne 1 ] && echo 's'))"
            echo "**Base model:** $base_model"
            echo "**Trigger:** $triggers"
            echo "$model_note"
            echo ""
            printf "%b" "$skill_list"
        } >> "$global_md"

        synced=$((synced + 1))
        log "  [$cat_name] $skill_count skills synced"
    done

    log "Synced $synced categories to global CLAUDE.md"
    log "Global CLAUDE.md: $global_md ($(wc -l < "$global_md") lines)"
}

cmd_status() {
    local store="${1:-$UPSKILL_STORE}"
    local total=0
    echo ""
    for cat_dir in "$store"/*/; do
        [ -d "$cat_dir" ] || continue
        cat_name=$(basename "$cat_dir")
        # Skip non-category dirs
        [[ "$cat_name" == .* ]] && continue
        count=$(grep -c '^  - id:' "$cat_dir/manifest.yaml" 2>/dev/null || echo 0)
        echo "  $cat_name: $count skills"
        total=$((total + count))
    done
    echo ""
    echo "  Total: $total skills"
    echo ""

    if [ -d "$store/.building" ]; then
        echo "  Active building jobs:"
        ls "$store/.building/" 2>/dev/null | sed 's/^/    - /' || echo "    (none)"
        echo ""
    fi
}

# ---- main ----
case "${1:-}" in
    list)
        shift
        store="$UPSKILL_STORE"
        [ $# -gt 0 ] && store="${1#--store=}"
        cmd_list "$store"
        ;;
    search)
        shift
        query="${1:?Usage: $0 search <query>}"
        shift || true
        store="$UPSKILL_STORE"
        [ $# -gt 0 ] && store="${1#--store=}"
        cmd_search "$query" "$store"
        ;;
    add)
        shift
        cmd_add "$@"
        ;;
    status)
        shift
        store="$UPSKILL_STORE"
        [ $# -gt 0 ] && store="${1#--store=}"
        cmd_status "$store"
        ;;
    remove)
        shift
        cmd_remove "$@"
        ;;
    sync)
        shift
        store="$UPSKILL_STORE"
        [ $# -gt 0 ] && store="${1#--store=}"
        cmd_sync "$store"
        ;;
    help|--help|-h)
        cat << 'HELP'
Usage: upskill-store.sh <command> [args]

Commands:
  list    [--store <path>]              List all skills by category
  search  <query> [--store <path>]      Search skills by keyword
  add     --category <c> --skill-id <id> --prompt <p> [--base-model <m>]
                                        Add a skill to the store
  remove  --category <c> [--skill-id <id>]
                                        Remove a skill or entire category
  sync    [--store <path>]              Rebuild global CLAUDE.md + skills
  status  [--store <path>]              Show skill counts and build status
  help                                  Show this help
HELP
        exit 0
        ;;
    *)
        echo "Usage: $0 {list|search|add|remove|sync|status|help} [args]"
        echo "Try '$0 help' for details."
        exit 1
        ;;
esac

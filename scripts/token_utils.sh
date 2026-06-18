#!/bin/bash
# Token tracking utilities using CC stream-json output for exact counts.

# Extract token usage from CC stream-json output.
# Returns "input_tokens output_tokens" or "0 0" if not found.
extract_tokens_from_log() {
    local log=$1
    if [ -f "$log" ]; then
        # CC stream-json: find the result line with usage info
        python3 -c "
import json, sys
try:
    for line in open('$log'):
        line = line.strip()
        if not line or not line.startswith('{'): continue
        try:
            data = json.loads(line)
            if data.get('type') == 'result' and 'usage' in data:
                u = data['usage']
                print(f\"{u.get('input_tokens', 0)} {u.get('output_tokens', 0)}\")
                sys.exit(0)
        except: pass
    print('0 0')
except: print('0 0')
" 2>/dev/null
    else
        echo "0 0"
    fi
}

# Record exact token usage for a task run
record_tokens_exact() {
    local out_dir=$1 task=$2 phase=$3 cc_log=$4 acp_chars=${5:-0}
    local json="$out_dir/tokens.json"

    local tokens=$(extract_tokens_from_log "$cc_log")
    local input_tokens=$(echo "$tokens" | cut -d' ' -f1)
    local output_tokens=$(echo "$tokens" | cut -d' ' -f2)
    local total=$((input_tokens + output_tokens))

    if [ ! -f "$json" ]; then
        echo '{"runs": []}' > "$json"
    fi
    python3 -c "
import json
data = json.load(open('$json'))
data['runs'].append({
    'task': '$task',
    'phase': '$phase',
    'input_tokens': $input_tokens,
    'output_tokens': $output_tokens,
    'total_tokens': $total,
    'acp_chars': $acp_chars,
})
json.dump(data, open('$json', 'w'), indent=2)
" 2>/dev/null || true
}

# Print token summary
print_token_summary() {
    local json=$1
    [ ! -f "$json" ] && return
    python3 -c "
import json
data = json.load(open('$json'))
runs = data['runs']
if not runs: return
total = sum(r['total_tokens'] for r in runs)
n = len(runs)
print(f'  Total runs: {n}')
print(f'  Total tokens: {total:,}')
print(f'  Avg tokens/run: {total//n:,}')
from collections import Counter
by_phase = Counter()
for r in runs:
    by_phase[r['phase']] += r['total_tokens']
print(f'  By phase:')
for p, t in by_phase.items():
    print(f'    {p}: {t:,} tokens')
" 2>/dev/null || true
}

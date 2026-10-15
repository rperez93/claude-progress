#!/usr/bin/env bash
# Self-contained checks for cc-progress. Usage: tests/run.sh
set -u
P="${CC_PROGRESS_BIN:-$(cd "$(dirname "$0")/.." && pwd)/bin/cc-progress}"
export CC_PROGRESS_DIR; CC_PROGRESS_DIR=$(mktemp -d)
export CC_PROGRESS_SESSION=test COLUMNS=140 NO_COLOR=1
trap 'rm -rf "$CC_PROGRESS_DIR"' EXIT
F="$CC_PROGRESS_DIR/test/main.json"
fails=0
check() { # NAME HAYSTACK NEEDLE
  if [[ $2 == *"$3"* ]]; then echo "ok   $1"; else echo "FAIL $1: expected '$3' in: $2"; fails=$((fails + 1)); fi
}
age() { jq -c "$1" "$F" > "$F.n" && mv "$F.n" "$F"; }

"$P" start --total 40 --label Converting --unit files
check "fresh bar"            "$("$P" show)" "0/40 files 0%"
check "no ETA before data"   "$("$P" show)" "ETA …"

age '.started_at -= 60 | .samples = [[.started_at, 0, 0], [now, 10, 10]] | .done = 10 | .wdone = 10 | .updated_at = now'
out=$("$P" show)
check "count and percent"    "$out" "10/40 files 25%"
check "elapsed"              "$out" "1m00s"
check "eta = 30 left x 6s"   "$out" "ETA ~3m00s"
check "average"              "$out" "6s/file"

age '.started_at -= 4 | .samples[] |= (.[0] -= 4) | .updated_at -= 4'
check "eta counts down between ticks" "$("$P" show)" "ETA ~2m56s"

"$P" set 10 --note "same value"   # a heartbeat: must not move the ETA anchor
check "same-value set keeps the countdown" "$("$P" show)" "ETA ~2m56s"

age '.started_at -= 26 | .samples[] |= (.[0] -= 26)'
out=$("$P" show)
check "overdue item: eta is a floor" "$out" "ETA ≥"
check "overdue item: in-flight time counted (10 in 90s, 29 left)" "$out" "ETA ≥4m21s"
check "overdue item: time on the current item shown" "$out" "same value 30s"

age '.updated_at -= 600'
check "stall is flagged"     "$("$P" show)" "no update for"

"$P" tick 5 --note "file.pdf"
check "tick and note"        "$("$P" show)" "15/40"
check "note shown"           "$("$P" show)" "file.pdf"

"$P" total 15
check "reaching total = done" "$("$P" show)" "✔ Converting"

"$P" start --id pre --total 23 --label Catchup; "$P" set 19 --id pre
check "work finished before start is shown" "$("$P" show | grep Catchup)" "19/23"
check "...but gives no rate or ETA" "$("$P" show | grep Catchup)" "ETA …"
check "...and becomes the baseline sample" "$(jq -c '.samples | length' "$CC_PROGRESS_DIR/test/pre.json")" "1"
"$P" start --id pre2 --total 23 --done 19 --label Catchup2
check "start --done" "$(jq -c '[.done, .samples[0][1]]' "$CC_PROGRESS_DIR/test/pre2.json")" "[19,19]"

"$P" start --id free --label Scanning --unit rows; "$P" set 1200 --id free
check "no total, no ETA"     "$("$P" show | grep Scanning)" "1200 rows"
check "no total: scanner"    "$("$P" show | grep Scanning)" "▓▓▓"

# weighted items: three files, 1 + 1 + 8 tests; the ETA is on tests, not on files
printf '1 a.py\n1 b.py\n8 c.py\n' > "$CC_PROGRESS_DIR/w.txt"
"$P" start --id w --label Weighted --unit files --weights "$CC_PROGRESS_DIR/w.txt"
check "weights set the total"  "$(jq -c '[.total, (.weights | add)]' "$CC_PROGRESS_DIR/test/w.json")" "[3,10]"
"$P" tick --id w --item a.py --note b.py
check "one light item = 10%"   "$("$P" show | grep Weighted)" "1/3 files 10%"
WF="$CC_PROGRESS_DIR/test/w.json"
jq -c '.started_at -= 30 | .samples[0][0] -= 30 | .samples[1][0] -= 20' "$WF" > "$WF.n" && mv "$WF.n" "$WF"
"$P" tick --id w --item b.py --note c.py
jq -c '.started_at -= 10 | .samples[] |= (.[0] -= 10)' "$WF" > "$WF.n" && mv "$WF.n" "$WF"
out=$("$P" show | grep Weighted)
check "two light items = 20%"  "$out" "2/3 files 20%"
check "eta on the heavy item: 8 tests x 15s, 10s in" "$out" "ETA ~1m50s"
check "weighted bar shows no per-file rate" "$(printf '%s' "$out" | grep -c '/file')" "0"
"$P" done --id w
check "done fills the weighted gauge" "$("$P" show | grep Weighted)" "100%"
printf '0 a.py\n0 b.py\n' > "$CC_PROGRESS_DIR/w0.txt"
"$P" start --id w0 --label Zero --weights "$CC_PROGRESS_DIR/w0.txt"; "$P" tick --id w0 --item a.py
check "all-zero weights still render" "$("$P" show | grep Zero)" "1/2 50%"
printf '{"id":"bad","label":"Broken","state":"running","started_at":"soon","updated_at":'"$(date +%s)"',"done":null,"total":3,"samples":[]}' > "$CC_PROGRESS_DIR/test/bad.json"
check "a corrupt bar degrades one line" "$("$P" show | grep Broken)" "cannot be rendered"
check "...and the others still render" "$("$P" show | grep -c Zero)" "1"
rm -f "$CC_PROGRESS_DIR/test/bad.json" "$CC_PROGRESS_DIR/test/w0.json"
printf '{"a.py": 2, "b.py": 3}' > "$CC_PROGRESS_DIR/w.json"
"$P" start --id wj --weights "$CC_PROGRESS_DIR/w.json"
check "weights as JSON"        "$(jq -c '.weights' "$CC_PROGRESS_DIR/test/wj.json")" '{"a.py":2,"b.py":3}'
[[ $("$P" show | grep Scanning) == *ETA* ]] && { echo "FAIL indeterminate bar shows ETA"; fails=$((fails + 1)); }

"$P" start --id par --total 300; seq 300 | xargs -P 16 -I{} "$P" tick --id par
check "300 parallel ticks, none lost" "$(jq -c .done "$CC_PROGRESS_DIR/test/par.json")" "300"

seq 7 | "$P" pipe --id pp --total 7 --label piped --quiet
check "pipe counts lines"    "$(jq -c '[.done, .state]' "$CC_PROGRESS_DIR/test/pp.json")" '[7,"done"]'
check "pipe passes through"  "$(printf 'a\nb\n' | "$P" pipe --id pt)" "b"

"$P" tick --id missing 2>/dev/null; check "tick without bar exits 0" "$?" "0"

"$P" note --id free "$(printf 'bad\033[31mcolour\ttab')"
check "escape codes stripped from the note" "$("$P" show | grep Scanning)" "bad colour tab"
out=$(echo '{"session_id":"test"}' | "$P" render)
check "render ends with a divider"  "$(printf '%s' "$out" | tail -1)" "────"
check "divider as wide as the widest bar" "$(printf '%s\n' "$out" | sed 's/\x1b\[[0-9;]*m//g' | awk '{ if (length($0) > m) m = length($0) } END { print m }')" "$(printf '%s' "$out" | tail -1 | sed 's/\x1b\[[0-9;]*m//g' | awk '{ print length($0) }')"
check "show has no divider"        "$("$P" show | grep -c '────')" "0"
check "ascii mode"                 "$(CC_PROGRESS_ASCII=1 "$P" show | grep Converting)" "####"
check "ascii divider"              "$(echo '{"session_id":"test"}' | CC_PROGRESS_ASCII=1 "$P" render | tail -1)" "----"
check "empty session renders nothing" "$(echo '{"session_id":"nobody"}' | "$P" render | wc -c)" "0"
"$P" fail --id par --note boom
check "failure shown"        "$("$P" show)" "✘ par"

age '.state = "done" | .finished_at = now - 120'
[[ $("$P" show) == *Converting* ]] && { echo "FAIL finished bar not hidden after keep window"; fails=$((fails + 1)); }

export CLAUDE_CODE_SESSION_ID=test
"$P" start --tasks --label Plan
# payload shapes below were captured from a real Claude Code 2.1.296 session
for i in 1 2 3; do echo '{"hook_event_name":"PostToolUse","tool_name":"TaskCreate","tool_input":{"subject":"task '$i'"},"tool_response":{"task":{"id":"'$i'","subject":"task '$i'"}}}' | "$P" hook; done
echo '{"hook_event_name":"PostToolUse","tool_name":"TaskUpdate","tool_input":{"taskId":"2","status":"in_progress"}}' | "$P" hook
check "in-progress task named in note" "$("$P" show | grep Plan)" "task 2"
echo '{"hook_event_name":"PostToolUse","tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"completed"}}' | "$P" hook
echo '{"hook_event_name":"PostToolUse","tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"completed"}}' | "$P" hook
check "task hook counts once" "$("$P" show | grep Plan)" "1/3"
check "render via stdin json" "$(echo '{"session_id":"test"}' | "$P" render | grep Plan)" "1/3"
"$P" start --agents --label Agents
# payload shapes captured from a real Claude Code 2.1.300 session
echo '{"hook_event_name":"SubagentStart","agent_id":"a1","agent_type":"general-purpose"}' | "$P" hook
echo '{"hook_event_name":"SubagentStart","agent_id":"a2","agent_type":"Explore"}' | "$P" hook
check "agents: two started"   "$("$P" show | grep Agents)" "0/2"
check "agents: running types in note" "$("$P" show | grep Agents)" "Explore, general-purpose"
jq -c '.updated_at -= 1800 | .samples[] |= (.[0] -= 1800)' "$CC_PROGRESS_DIR/test/agents.json" > "$CC_PROGRESS_DIR/x" && mv "$CC_PROGRESS_DIR/x" "$CC_PROGRESS_DIR/test/agents.json"
check "hook-fed bar is never flagged stalled" "$("$P" show | grep Agents | grep -c 'no update')" "0"
echo '{"hook_event_name":"SubagentStop","agent_id":"a1","agent_type":"general-purpose"}' | "$P" hook
check "agents: one finished"  "$("$P" show | grep Agents)" "1/2"
check "agents: finished one leaves the note" "$("$P" show | grep Agents | grep -c general-purpose)" "0"
echo '{"hook_event_name":"TaskCreated","task_id":"9","task_subject":"late task"}' | "$P" hook
check "TaskCreated counted once with TaskCreate" "$("$P" show | grep Plan)" "1/4"
echo '{"hook_event_name":"TaskCompleted","task_id":"9"}' | "$P" hook
check "TaskCompleted counted"  "$("$P" show | grep Plan)" "2/4"
echo '{"hook_event_name":"TaskCompleted","task_id":"9"}' | "$P" hook
check "TaskCompleted idempotent" "$("$P" show | grep Plan)" "2/4"
echo '{"hook_event_name":"TaskCreated","task_id":"10","task_subject":"event first"}' | "$P" hook
echo '{"hook_event_name":"PostToolUse","tool_name":"TaskCreate","tool_input":{"subject":"event first"},"tool_response":{"task":{"id":"10","subject":"event first"}}}' | "$P" hook
check "TaskCreated before TaskCreate counts once" "$("$P" show | grep Plan)" "2/5"
"$P" start --id keep --total 5 --label Keep; "$P" tick --id keep
"$P" start --id old --total 5 --label Old
for b in old agents; do jq -c '.updated_at -= 3600' "$CC_PROGRESS_DIR/test/$b.json" > "$CC_PROGRESS_DIR/x" && mv "$CC_PROGRESS_DIR/x" "$CC_PROGRESS_DIR/test/$b.json"; done
out=$("$P" prune)
check "prune removes finished bars"  "$out" "removed w"
check "prune removes stale bars"     "$out" "removed old"
[ -e "$CC_PROGRESS_DIR/test/keep.json" ] && echo "ok   prune keeps a live bar" || { echo "FAIL prune removed a live bar"; fails=$((fails + 1)); }
[ -e "$CC_PROGRESS_DIR/test/agents.json" ] && echo "ok   prune keeps a hook-fed bar" || { echo "FAIL prune removed the agents bar"; fails=$((fails + 1)); }
echo '{"hook_event_name":"SessionEnd"}' | "$P" hook
check "session end cleans up" "$(ls "$CC_PROGRESS_DIR")" ""

echo; [ "$fails" = 0 ] && echo "all checks passed" || { echo "$fails check(s) failed"; exit 1; }

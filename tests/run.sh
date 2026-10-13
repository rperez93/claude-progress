#!/usr/bin/env bash
# Self-contained checks for cc-progress. Usage: tests/run.sh
set -u
P="$(cd "$(dirname "$0")/.." && pwd)/bin/cc-progress"
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

age '.started_at -= 60 | .samples = [[.started_at, 0]] | .done = 10 | .updated_at = now'
out=$("$P" show)
check "count and percent"    "$out" "10/40 files 25%"
check "elapsed"              "$out" "1m00s"
check "eta = 30 left x 6s"   "$out" "ETA ~3m00s"
check "average"              "$out" "avg 6s"

age '.started_at -= 4 | .samples[0][0] -= 4 | .updated_at -= 4'
check "eta counts down between ticks" "$("$P" show)" "ETA ~2m56s"

age '.started_at -= 26 | .samples[0][0] -= 26 | .updated_at -= 26'
check "overrunning item floors eta at the rest" "$("$P" show)" "ETA ~2m54s"

age '.updated_at -= 600'
check "stall is flagged"     "$("$P" show)" "no update for"

"$P" tick 5 --note "file.pdf"
check "tick and note"        "$("$P" show)" "15/40"
check "note shown"           "$("$P" show)" "file.pdf"

"$P" total 15
check "reaching total = done" "$("$P" show)" "✔ Converting"

"$P" start --id free --label Scanning --unit rows; "$P" set 1200 --id free
check "no total, no ETA"     "$("$P" show | grep Scanning)" "1200 rows"
[[ $("$P" show | grep Scanning) == *ETA* ]] && { echo "FAIL indeterminate bar shows ETA"; fails=$((fails + 1)); }

"$P" start --id par --total 300; seq 300 | xargs -P 16 -I{} "$P" tick --id par
check "300 parallel ticks, none lost" "$(jq -c .done "$CC_PROGRESS_DIR/test/par.json")" "300"

seq 7 | "$P" pipe --id pp --total 7 --label piped --quiet
check "pipe counts lines"    "$(jq -c '[.done, .state]' "$CC_PROGRESS_DIR/test/pp.json")" '[7,"done"]'
check "pipe passes through"  "$(printf 'a\nb\n' | "$P" pipe --id pt)" "b"

"$P" tick --id missing 2>/dev/null; check "tick without bar exits 0" "$?" "0"
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
echo '{"hook_event_name":"SessionEnd"}' | "$P" hook
check "session end cleans up" "$(ls "$CC_PROGRESS_DIR")" ""

echo; [ "$fails" = 0 ] && echo "all checks passed" || { echo "$fails check(s) failed"; exit 1; }

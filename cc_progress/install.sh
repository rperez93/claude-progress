#!/usr/bin/env bash
# Install (or with --uninstall, remove) cc-progress for Claude Code:
#   - the CLI          -> ~/.local/bin/cc-progress            (symlink; skipped when the
#                         PyPI package already put cc-progress on PATH)
#   - the skill        -> ~/.claude/skills/progress-bar       (symlink)
#   - the rule         -> ~/.claude/rules/progress-bar.md     (symlink, loaded every session)
#   - a managed block  -> the statusLine command script (--create-statusline writes a
#                         minimal one when Claude Code has none)
#   - hooks            -> ~/.claude/settings.json (task tools, task events, subagent events, SessionEnd)
#   - statusLine.refreshInterval = 1 when unset (the spinner and countdown redraw once a second)
# The status line and the hooks call the bash script directly, never a Python wrapper, so a
# poll costs about 10 ms. Idempotent. settings.json and the status line script are backed up
# before any change.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
BIN_DIR="${CC_PROGRESS_BIN_DIR:-$HOME/.local/bin}"
SETTINGS="$CLAUDE_DIR/settings.json"
SKILL_LINK="$CLAUDE_DIR/skills/progress-bar"
RULE_LINK="$CLAUDE_DIR/rules/progress-bar.md"
BEGIN='# >>> CC-PROGRESS (managed by claude-progress install.sh) — do not edit by hand'
END='# <<< CC-PROGRESS'
STAMP="$(date +%Y%m%d-%H%M%S)"
CLI="$REPO/bin/cc-progress"          # what the status line and the hooks run
MODE=install CREATE_STATUSLINE=0
for arg in "$@"; do
  case "$arg" in
    --uninstall)         MODE=uninstall ;;
    --create-statusline) CREATE_STATUSLINE=1 ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg (try --help)" >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
command -v flock >/dev/null || { echo "flock (util-linux) is required" >&2; exit 1; }

backup() { mkdir -p "$CLAUDE_DIR/backups"; cp -p "$1" "$CLAUDE_DIR/backups/$(basename "$1").cc-progress-$STAMP"; }

# --- locate the status line script from settings.json
statusline_script() {
  local cmd
  cmd=$(jq -r '.statusLine.command // empty' "$SETTINGS" 2>/dev/null || true)
  cmd=${cmd/#\~/$HOME}
  [ -n "$cmd" ] && [ -f "$cmd" ] && printf '%s' "$cmd"
  return 0
}

strip_block() { # print file $1 without the managed block
  awk -v b="$BEGIN" -v e="$END" '$0==b{skip=1} !skip{print} $0==e{skip=0}' "$1"
}

install_block() {
  local script=$1 tmp
  tmp=$(mktemp)
  strip_block "$script" | awk -v b="$BEGIN" -v e="$END" -v bin="$CLI" '
    function block() {
      print b
      print "if compgen -G \"${CC_PROGRESS_DIR:-$HOME/.claude/progress}/*/*.json\" >/dev/null 2>&1 && [ -x \"" bin "\" ]; then"
      print "  __ccp=\"$(printf '"'"'%s'"'"' \"${input:-}\" | /usr/bin/timeout 2 \"" bin "\" render 2>/dev/null)\""
      print "  if [ -n \"$__ccp\" ]; then printf '"'"'%s\\n'"'"' \"$__ccp\"; fi"
      print "fi"
      print e
      done = 1
    }
    { print }
    !done && /^input=\$\(cat\)/ { block() }
    END { if (!done) { print "if [ -z \"${input+x}\" ]; then input=$(cat); fi"; block() } }
  ' > "$tmp"
  if ! cmp -s "$tmp" "$script"; then backup "$script"; cat "$tmp" > "$script"; echo "status line: block written to $script"
  else echo "status line: block already current"; fi
  rm -f "$tmp"
}

settings_without_hooks='
  .hooks //= {}
  | .hooks |= with_entries(.value |= map(select((.hooks // []) | any(.command // "" | test("cc-progress\"? hook")) | not)))
  | .hooks |= with_entries(select(.value | length > 0))
'

write_settings() { # $1 = jq filter
  local tmp; tmp=$(mktemp)
  jq --arg cmd "\"$CLI\" hook" "$1" "$SETTINGS" > "$tmp"
  if ! cmp -s "$tmp" "$SETTINGS"; then backup "$SETTINGS"; cat "$tmp" > "$SETTINGS"; echo "settings: hooks updated"
  else echo "settings: hooks already current"; fi
  rm -f "$tmp"
}

if [ "$MODE" = uninstall ]; then
  script=$(statusline_script)
  if [ -n "$script" ] && grep -qF "$BEGIN" "$script"; then
    backup "$script"; tmp=$(mktemp); strip_block "$script" > "$tmp"; cat "$tmp" > "$script"; rm -f "$tmp"
    echo "status line: block removed"
  fi
  [ -f "$SETTINGS" ] && write_settings "$settings_without_hooks"
  [ -L "$SKILL_LINK" ] && rm -f "$SKILL_LINK"
  [ -L "$RULE_LINK" ] && rm -f "$RULE_LINK"
  [ -L "$BIN_DIR/cc-progress" ] && [ "$(readlink "$BIN_DIR/cc-progress")" = "$CLI" ] && rm -f "$BIN_DIR/cc-progress"
  echo "cc-progress removed (state under $CLAUDE_DIR/progress left in place)"
  exit 0
fi

mkdir -p "$CLAUDE_DIR/skills" "$CLAUDE_DIR/rules"
chmod +x "$CLI"
if [ "${CC_PROGRESS_NO_SYMLINK:-0}" = 1 ]; then
  echo "cli: $(command -v cc-progress 2>/dev/null || echo cc-progress) (installed package); status line and hooks use $CLI"
elif [ -e "$BIN_DIR/cc-progress" ] && [ ! -L "$BIN_DIR/cc-progress" ]; then
  echo "cli: $BIN_DIR/cc-progress exists and is not a symlink (a package install?) — left alone; status line and hooks use $CLI"
else
  mkdir -p "$BIN_DIR"
  ln -sfn "$CLI" "$BIN_DIR/cc-progress"
  echo "cli: $BIN_DIR/cc-progress -> $CLI"
  case ":$PATH:" in *":$BIN_DIR:"*) ;; *) echo "note: $BIN_DIR is not on PATH; add it or call $CLI" >&2 ;; esac
fi
ln -sfn "$REPO/skill" "$SKILL_LINK"
ln -sfn "$REPO/rules/progress-bar.md" "$RULE_LINK"
echo "skill: $SKILL_LINK -> $REPO/skill"
echo "rule: $RULE_LINK -> $REPO/rules/progress-bar.md"

[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
script=$(statusline_script)
if [ -z "$script" ] && [ "$CREATE_STATUSLINE" = 1 ]; then
  script="$CLAUDE_DIR/statusline-command.sh"
  if [ ! -e "$script" ]; then
    cat > "$script" <<'SL'
#!/usr/bin/env bash
# Minimal Claude Code status line, written by cc-progress install --create-statusline.
# Claude Code pipes a JSON object in; anything printed is the status line.
input=$(cat)
printf '%s' "$input" | jq -r '[.model.display_name, (.workspace.current_dir // .cwd // "" | split("/") | last)] | map(select(. != null and . != "")) | join(" · ")'
SL
    chmod +x "$script"
    echo "status line: wrote a minimal $script"
  fi
  tmp=$(mktemp)
  jq --arg cmd "$script" '.statusLine = {type: "command", command: $cmd, refreshInterval: 1}' "$SETTINGS" > "$tmp"
  backup "$SETTINGS"; cat "$tmp" > "$SETTINGS"; rm -f "$tmp"
  echo "settings: statusLine set to $script"
fi
if [ -n "$script" ]; then
  install_block "$script"
else
  echo "status line: Claude Code has no statusLine command script. Re-run with --create-statusline to write a minimal one, or set one up first (/statusline in Claude Code), then re-run." >&2
fi

write_settings "$settings_without_hooks"'
  | .hooks.PostToolUse   = ((.hooks.PostToolUse   // []) + [{matcher: "TaskCreate|TaskUpdate|TodoWrite", hooks: [{type: "command", command: $cmd, timeout: 5}]}])
  | .hooks.TaskCreated   = ((.hooks.TaskCreated   // []) + [{hooks: [{type: "command", command: $cmd, timeout: 5}]}])
  | .hooks.TaskCompleted = ((.hooks.TaskCompleted // []) + [{hooks: [{type: "command", command: $cmd, timeout: 5}]}])
  | .hooks.SubagentStart = ((.hooks.SubagentStart // []) + [{hooks: [{type: "command", command: $cmd, timeout: 5}]}])
  | .hooks.SubagentStop  = ((.hooks.SubagentStop  // []) + [{hooks: [{type: "command", command: $cmd, timeout: 5}]}])
  | .hooks.SessionEnd    = ((.hooks.SessionEnd    // []) + [{hooks: [{type: "command", command: $cmd, timeout: 5}]}])
  | if .statusLine.refreshInterval == null and .statusLine.command != null then .statusLine.refreshInterval = 1 else . end
'

interval=$(jq -r '.statusLine.refreshInterval // empty' "$SETTINGS")
if [ -z "$interval" ]; then
  echo "note: statusLine.refreshInterval is not set (no statusLine command?) — without it the bar only redraws when a message arrives." >&2
elif [ "$interval" -gt 1 ] 2>/dev/null; then
  echo "note: statusLine.refreshInterval is ${interval}s; 1 s gives a smooth spinner and a live countdown (cc-progress render itself takes ~10 ms)." >&2
fi
echo "done. Try: cc-progress start --total 10 --label Demo && cc-progress tick 3"

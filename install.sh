#!/usr/bin/env bash
# Install (or with --uninstall, remove) cc-progress for Claude Code:
#   - the CLI          -> ~/.local/bin/cc-progress            (symlink)
#   - the skill        -> ~/.claude/skills/progress-bar       (symlink)
#   - the rule         -> ~/.claude/rules/progress-bar.md     (symlink, loaded every session)
#   - a managed block  -> the statusLine command script
#   - two hooks        -> ~/.claude/settings.json (PostToolUse task tools, SessionEnd)
# Idempotent. settings.json and the status line script are backed up before any change.
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
MODE=install
[ "${1:-}" = "--uninstall" ] && MODE=uninstall

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
  strip_block "$script" | awk -v b="$BEGIN" -v e="$END" -v bin="$BIN_DIR/cc-progress" '
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
  jq --arg cmd "\"$BIN_DIR/cc-progress\" hook" "$1" "$SETTINGS" > "$tmp"
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
  [ -L "$BIN_DIR/cc-progress" ] && rm -f "$BIN_DIR/cc-progress"
  echo "cc-progress removed (state under $CLAUDE_DIR/progress left in place)"
  exit 0
fi

mkdir -p "$BIN_DIR" "$CLAUDE_DIR/skills" "$CLAUDE_DIR/rules"
chmod +x "$REPO/bin/cc-progress"
ln -sfn "$REPO/bin/cc-progress" "$BIN_DIR/cc-progress"
ln -sfn "$REPO/skill" "$SKILL_LINK"
echo "cli: $BIN_DIR/cc-progress -> $REPO/bin/cc-progress"
ln -sfn "$REPO/rules/progress-bar.md" "$RULE_LINK"
echo "skill: $SKILL_LINK -> $REPO/skill"
echo "rule: $RULE_LINK -> $REPO/rules/progress-bar.md"

[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
script=$(statusline_script)
if [ -n "$script" ]; then
  install_block "$script"
else
  echo "status line: no statusLine command script found in $SETTINGS — add one, then re-run" >&2
fi

write_settings "$settings_without_hooks"'
  | .hooks.PostToolUse = ((.hooks.PostToolUse // []) + [{matcher: "TaskCreate|TaskUpdate|TodoWrite", hooks: [{type: "command", command: $cmd, timeout: 5}]}])
  | .hooks.SessionEnd  = ((.hooks.SessionEnd  // []) + [{hooks: [{type: "command", command: $cmd, timeout: 5}]}])
'

interval=$(jq -r '.statusLine.refreshInterval // empty' "$SETTINGS")
if [ -z "$interval" ]; then
  echo "note: statusLine.refreshInterval is not set — without it the bar only redraws when a message arrives. Set it to 1–5 seconds." >&2
fi
echo "done. Try: cc-progress start --total 10 --label Demo && cc-progress tick 3"

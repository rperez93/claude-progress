# claude-progress

Progress bars with count, elapsed time and ETA in the Claude Code status line.

```
▶ Converting ██████▌░░░░░░░░░░░░░ 13/40 files 32% · 1m18s · ETA ~2m42s · avg 6s · report-q3.pdf
✔ Tests 240/240 tests 100% · done in 4m02s · avg 1s
```

## How it works

- **Writers** call `cc-progress` (`start`, `tick`, `set`, `pipe`, `done` …). Each bar is one
  JSON file at `~/.claude/progress/<session_id>/<bar>.json`, written under `flock` and
  replaced atomically, so parallel workers and a polling reader never see a torn file.
- **The status line** runs `cc-progress render` from a managed block in the status line
  script. With `statusLine.refreshInterval` set, Claude Code re-runs it on a timer, and
  elapsed time and ETA are computed at render time — the bar moves during one long command
  with no messages in flight.
- **The session** comes from `$CLAUDE_CODE_SESSION_ID` on the write side and `session_id`
  in the status line's stdin on the read side. Subagents share the parent's id. Each
  session shows only its own bars.
- **A hook** keeps a `--tasks` bar in step with Claude's task list (PostToolUse on
  `TaskCreate|TaskUpdate|TodoWrite`) and removes a session's bars on `SessionEnd`.
- **A skill** (`progress-bar`) and a one-paragraph rule in `~/.claude/rules/` (loaded every
  session) tell Claude when and how to use it: count first, tick as a
  side effect of the work, always finish.

## Install

```bash
./install.sh              # idempotent; backs up settings.json and the status line script
./install.sh --uninstall
tests/run.sh
```

Requires `jq`, `flock`, bash, and a `statusLine` of type `command` pointing at a script.
Set `statusLine.refreshInterval` (1–5 s) or the bar only redraws when a message arrives.

## Usage

```bash
cc-progress start --total "$(wc -l < files.txt)" --label Converting --unit files
while IFS= read -r f; do convert "$f"; cc-progress tick --note "$f"; done < files.txt
cc-progress done

pytest -v | cc-progress pipe --total 240 --label Tests --match 'PASSED|FAILED'
```

`cc-progress help` lists every command; `skill/SKILL.md` has the patterns.

## Behaviour worth knowing

- ETA is `remaining ÷ rate` over roughly the last 30 samples, counted down between
  updates. No ETA is shown without a total, before the first unit completes, or before
  one second of data exists.
- A bar reaching its total is shown as finished. Finished bars stay 60 s
  (`CC_PROGRESS_KEEP_DONE`). A running bar with no update for 2 minutes (or three average
  intervals, whichever is longer) is flagged `no update for …`, and hidden after 2 h
  (`CC_PROGRESS_STALE_HIDE`).
- Updating commands exit 0 on operational errors so that progress reporting cannot break
  the job it reports on.
- `cc-progress doctor` checks the installation and reports when the status line last polled.
- `CC_PROGRESS_HOOK_LOG=/path` in Claude Code's environment appends every hook payload there.

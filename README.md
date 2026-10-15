# claude-progress

Progress bars with count, elapsed time and ETA in the Claude Code status line.

```
⠸ Converting ██████▌░░░░░░░░░░░░░ 13/40 files 32%  1m18s · ETA ~2m35s at 12:39 · 5.9s/file  › report-q3.pdf
⠸ Sweep      ████████████████▌░░░ 19/23 files 82%  13m01s · ETA ≥2m03s at 14:09  › test_rules_sweep.py 11m30s
⠸ Scanning   ░░░░░▓▓▓░░░░░░░░░░░░ 1200 rows  40s
✔ Tests      ████████████████████ 240/240 tests 100%  done in 4m02s · 1s/test
✘ Deploy     ██████▋░░░░░░░░░░░░░ 2/6 steps 33%  failed after 12s  › step 3: migrate
```

One line per bar, read left to right in the order the questions come: is it alive (the
spinner advances once per second), how far (the gauge, the only coloured block), the count,
then the quiet figures: elapsed, ETA, rate, and after `›` what is being worked on now.
`ETA ~` is on schedule; `ETA ≥` means the current item is already past the average, the
figure is a floor, and the time spent on that item follows its name in amber. The finish
time of day appears once the ETA reaches a minute. A bar without a total shows a block
sweeping back and forth instead of a fill.

A rule as wide as the widest bar closes the block, so the rows above read as progress and
the rows below as the ordinary status line; it exists only while a bar is shown.

Colours are the terminal's own ANSI roles (green, cyan, yellow, red, bright black, bold),
never fixed RGB values, so the bar follows whatever theme the terminal uses. Set
`CC_PROGRESS_MUTED=2` if the theme's bright black is unreadable (faint is used instead),
`CC_PROGRESS_ASCII=1` for fonts without braille or block glyphs, or `NO_COLOR=1` for plain
text. Notes and labels are stripped of control characters and escape sequences before
they reach the terminal.

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
- **Hooks** keep a `--tasks` bar in step with Claude's task list (PostToolUse on
  `TaskCreate|TaskUpdate|TodoWrite`, plus the `TaskCreated`/`TaskCompleted` events), keep an
  `--agents` bar in step with subagents (`SubagentStart`/`SubagentStop`: total = agents
  started, done = agents finished, note = the types still running), and remove a session's
  bars on `SessionEnd`. Each hook is a few milliseconds of jq on a local file; nothing is
  sent to the model and nothing interrupts the conversation.
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
`statusLine.refreshInterval` is set to 1 s when unset; without it the bar only redraws when
a message arrives, and at 1 s the spinner and the countdown move every second. The whole
render is about 10 ms.

## Usage

```bash
cc-progress start --total "$(wc -l < files.txt)" --label Converting --unit files
while IFS= read -r f; do convert "$f"; cc-progress tick --note "$f"; done < files.txt
cc-progress done

pytest -v | cc-progress pipe --total 240 --label Tests --match 'PASSED|FAILED'
```

### Count work, not items

The ETA is only as good as the unit. Files, tasks or steps of very unequal size make the
bar lie: a test sweep with 22 quick files and one of 32 minutes shows 95 % for most of the
run. Pick the smallest countable thing of roughly even cost (tests, rows, pages), or keep
the coarse unit for the count and give the bar the cost of each item:

```bash
for f in tests/test_*.py; do echo "$(grep -c 'def test_' "$f") $f"; done > weights.txt
cc-progress start --label "Tests" --unit files --weights weights.txt
for f in tests/test_*.py; do
  cc-progress note "$f"                 # the ETA now expects this file's cost
  pytest -q "$f"; cc-progress tick --item "$f"
done
cc-progress done
```

The count still reads `3/23 files`; the gauge, the percentage and the ETA are on tests.
`--weights` takes `WEIGHT NAME` lines (the shape `wc -l` prints) or a JSON object.

### On request

Ask Claude to *update the progress bar*, *refresh the ETA*, *what is left*, or *clear the
bars*: the skill reads the bars (`cc-progress show`), checks the source of truth (the log,
the file list, the queue), corrects them (`set`, `total`, `note`, `done`, `fail`) and reports
in one line. `cc-progress prune` removes finished, failed and stale bars; `prune --all`
removes every bar of the session. Finished bars also leave on their own after a minute.

### Agents and tasks, hands free

```bash
cc-progress start --agents --label "Reviewers"   # then launch the agents
cc-progress start --tasks  --label "Refactor"    # then create the tasks
```

`cc-progress help` lists every command; `skill/SKILL.md` has the patterns.

## Behaviour worth knowing

- **ETA.** The rate is units completed *while the bar was watching* over the time between
  the first and the last completion (at most the last 30 completions). The next unit is
  expected one average interval after the last one, so the ETA counts down between
  updates. Once the current unit is overdue the average starts counting the unit in
  flight, the ETA is shown as `≥` and grows with it: a workload of unequal items pushes
  the estimate out instead of pretending. No ETA is shown without a total, before the
  first unit completes under observation, or before one second of data exists.
- **Work done before the bar started** is a baseline, not progress: `start --done N`, or a
  `set` that jumps more than one unit within two seconds of `start`, shows the count
  without feeding the rate. Only completions the bar actually observed produce an ETA.
- **Heartbeats are not progress.** `updated_at` moves on every write (that is what the
  `no update for …` stall check reads); the ETA anchor and the rate only move when `done`
  changes. A polling loop that re-`set`s the same value every few seconds is harmless.
- Several bars in one session have their labels aligned; give them labels that differ
  in what the user cares about (`--label "Tests · main"` / `--label "Tests · v118"`).
- A bar reaching its total is shown as finished. Finished bars stay 60 s
  (`CC_PROGRESS_KEEP_DONE`). A running bar with no update for 2 minutes (or three average
  intervals, whichever is longer) is flagged `no update for …`, and hidden after 2 h
  (`CC_PROGRESS_STALE_HIDE`).
- Updating commands exit 0 on operational errors so that progress reporting cannot break
  the job it reports on.
- A running bar that only hooks write (`--tasks`, `--agents`) is never flagged stalled and
  never pruned as stale: silence there means nothing happened, not that the writer died.
- `cc-progress doctor` checks the installation and reports when the status line last polled.
- `CC_PROGRESS_HOOK_LOG=/path` in Claude Code's environment appends every hook payload there.

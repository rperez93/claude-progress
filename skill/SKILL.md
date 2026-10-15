---
name: progress-bar
description: Show a live progress bar with count, elapsed time and ETA in the Claude Code status line, using the `cc-progress` CLI. TRIGGER whenever the user asks for a progress bar, progress indicator, ETA, time remaining, "how many are left", "show progress", "keep me posted on progress", or wants to be able to estimate how long a batch, loop, download, migration, test run or multi-step task will take — in any language ("barra de progreso", "cuánto falta", "muéstrame el avance"). Also use it unprompted-by-name when the user has asked for progress reporting earlier in the session and a new countable job starts.
---

# Progress bars in the status line

`cc-progress` writes a small state file per bar; the status line re-reads it every
couple of seconds and computes elapsed time and ETA itself. So the bar moves and
the ETA counts down even while one long Bash command is running and no messages
are being exchanged. The session is picked up from `$CLAUDE_CODE_SESSION_ID`
(subagents share it), so no id needs passing.

The rule that makes it reliable: **the update must be a side effect of the work,
not something you remember to do between steps.** Put the tick inside the loop,
pipe the output through `pipe`, or let the task hook count for you. Do not rely on
running `cc-progress set` by hand after each step unless the steps are genuinely
separate tool calls.

## 1. Count first

An ETA needs a total. Before starting, measure it (`ls | wc -l`, `wc -l < list`,
`jq length`, number of test files, rows to migrate). If it truly cannot be known,
start without `--total`: the bar shows count, elapsed and rate, and no ETA —
which is the honest display. Correct it later with `cc-progress total N`.

## 2. Pick the channel

**A loop you write** — tick inside it:

```bash
cc-progress start --total "$(wc -l < files.txt)" --label "Converting" --unit files
while IFS= read -r f; do
  cc-progress note "$f"
  convert "$f" || failed=1
  cc-progress tick
done < files.txt
[ -z "${failed:-}" ] && cc-progress done || cc-progress fail --note "some conversions failed"
```

Parallel workers are safe (updates are locked): `xargs -P 8 -I{} sh -c 'work {} ; cc-progress tick'`.

**A command that prints one line per item** — pipe it:

```bash
cc-progress start --total 240 --label "Tests" --unit tests
pytest -v 2>&1 | cc-progress pipe --match 'PASSED|FAILED|ERROR'
cc-progress done
```

`pipe` passes stdin through unchanged and ticks once per line (or per line
matching `--match`). Given `--total`/`--label` itself, it starts and finishes
the bar on its own: `rsync -av src/ dst/ | cc-progress pipe --total "$n" --label Sync --quiet`.

**A tool that reports its own figure** (bytes, percent, epoch) — set the absolute value from its callback or a polling loop:

```bash
cc-progress start --total 100 --label "Training" --unit %
# ... wherever the figure is available:
cc-progress set "$pct" --note "epoch $e loss $loss"
```

**Multi-step work you do yourself across tool calls** — two options:

- With the task list: `cc-progress start --tasks --label "Refactor"` *before*
  creating the tasks. A hook then counts TaskCreate / TaskUpdate (or TodoWrite)
  calls: total = tasks created, done = tasks completed. Nothing to remember.
- Without it: `cc-progress start --total 6 --label "Migration" --unit steps`,
  then chain the tick onto the command that completes each step
  (`... && cc-progress tick --note "step 3: backfill"`), so it cannot be skipped.

Steps of very unequal length make a poor ETA; say so rather than presenting the
figure as reliable. The bar itself marks the situation: `ETA ≥` with the time spent
on the current item means that item is already past the average and the figure is
a floor.

**Work already partly done when the bar starts** — pass it as a baseline, so it
is displayed but not counted into the rate: `cc-progress start --total 23 --done 19`.
(A `set` right after `start` is treated the same way.) Only completions observed
by the bar produce an ETA, which is why a bar started late over a mostly finished
job honestly shows `ETA …` until the next item completes.

## 3. Always finish

End with `cc-progress done` (stays visible for a minute, then disappears) or
`cc-progress fail --note "why"`. A bar that reaches its total is treated as done
automatically; one abandoned mid-way shows "no update for …" until cleared with
`cc-progress clear`. Run the finish command even on the failure path.

## Several bars

Name them: `--id download`, `--id build`. Each renders on its own row with the
labels aligned, so give each a label that says what differs
(`--label "Tests · main"` / `--label "Tests · v118"`). Every command takes `--id`;
the default is `main`.

## Reference

```
cc-progress start [--total N] [--done N] [--label TEXT] [--unit WORD] [--note TEXT] [--tasks]
cc-progress tick  [N] [--note TEXT]
cc-progress set   DONE [--total N] [--note TEXT]
cc-progress total N
cc-progress note  TEXT
cc-progress done | fail [--note TEXT]
cc-progress clear [--all]
cc-progress pipe  [--total N] [--label TEXT] [--match REGEX] [--quiet]
cc-progress show            # print the bars as text — use it to check, or to report in chat
```

- Updating commands never break the job: on an operational error they warn on
  stderr and exit 0. If you see `no such bar`, the `start` was missed.
- The ETA is `remaining ÷ observed rate` over the last 30 completions, counted
  down between updates; `≥` marks an overdue current item. It is an estimate; the
  elapsed time next to it is a measurement. Re-`set`ting the same value is a
  harmless heartbeat and does not disturb it.
- Background jobs keep updating the bar after your turn ends — that is intended.
- If the bar does not appear, run `cc-progress show`. Text there but nothing in
  the status line means the status line block is missing: re-run `install.sh`
  from the claude-progress repo.

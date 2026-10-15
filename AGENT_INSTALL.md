# cc-progress — agent install

Instructions for a coding agent. Run these in order. No prose, no options you do
not need.

## 0. Rules

- Never `pip install` into the system Python: use `pipx`, `uv tool`, or a virtual
  environment.
- `cc-progress install` edits the user's Claude Code `settings.json` and status line
  script. It backs both up first and only adds its own marked block and hooks, but it
  is the user's configuration: if they did not ask for cc-progress themselves, say what
  it will touch before running it.
- Linux and macOS. On Windows, run everything inside WSL: the tool locks its state
  files with `flock`, which Windows does not have.

## 1. Install

**Prefer the package.** One command, no clone, upgrades itself:

```bash
pipx install cc-progress        # or: uv tool install cc-progress
cc-progress install
```

If pipx reports that no matching distribution was found, the package is not on PyPI
yet: install from source instead, exactly as below, and carry on with step 2.

**Install from source otherwise only if the user is working on cc-progress itself**, or
asked for an unreleased revision:

```bash
git clone https://github.com/rperez93/claude-progress.git
cd claude-progress
./install.sh
```

Both need `jq` and `flock` (util-linux) on PATH. If the installer stops because one is
missing, tell the user which package to install (`jq`, `util-linux`) and do not work
around it.

If it says Claude Code has no status line script, re-run with `--create-statusline`
(`cc-progress install --create-statusline`, or `./install.sh --create-statusline`). That
writes a minimal one showing the model and the directory, and cc-progress adds itself
above it.

## 2. Verify

```bash
cc-progress doctor
```

Every line must read `ok`. `note` lines are information. A `FAIL` names what to fix and
usually says "run install" again.

Then tell the user to **restart Claude Code**: hooks and the status line are read when
a session starts, and a running session keeps the old ones.

## 3. Use it

The skill installed with it (`progress-bar`, loaded through `~/.claude/rules/`) tells
Claude when and how to use the bar. From the user's side there is nothing to learn: ask
for "a progress bar", "an ETA" or "how many are left" on any countable job, and ask to
"update the progress bar" or "clear the finished bars" at any time.

From the agent's side, inside a Claude Code session:

```bash
cc-progress start --total "$(wc -l < files.txt)" --label Converting --unit files
while IFS= read -r f; do convert "$f"; cc-progress tick --note "$f"; done < files.txt
cc-progress done
```

`cc-progress help` lists every command. The rule that makes it reliable: the update is a
side effect of the work (a `tick` inside the loop, a `| cc-progress pipe`, or a hook
counting tasks and agents), never something to remember between steps.

## 4. Update

```bash
pipx upgrade cc-progress && cc-progress install        # package
cd claude-progress && git pull && ./install.sh          # source
```

Safe to re-run; the installer is idempotent. Restart Claude Code afterwards.

## 5. Uninstall

```bash
cc-progress uninstall && pipx uninstall cc-progress     # package
./install.sh --uninstall                                 # source
```

Removes the status line block, the hooks, the skill and the rule, and leaves the state
directory (`~/.claude/progress/`) in place.

## 6. If something is wrong

- Nothing in the status line but `cc-progress show` prints bars: the status line block is
  missing or the session was started before the install. `cc-progress doctor`, then
  restart Claude Code.
- `no session id`: not inside Claude Code. Pass `--session ID` or set
  `CLAUDE_CODE_SESSION_ID`.
- `no such bar`: the `start` was missed. Start it, then continue.
- The bar only moves when a message arrives: `statusLine.refreshInterval` is unset.
  `cc-progress install` sets it to 1 s when unset; `doctor` reports it.

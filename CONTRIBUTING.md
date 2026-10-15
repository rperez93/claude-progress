# Contributing

Thanks for taking a look. This is a small tool with a sharp purpose: show what a
coding agent is doing, how far it is and when it will finish, in the status line, with
figures that are honest.

## Getting set up

```bash
git clone https://github.com/rperez93/claude-progress.git
cd claude-progress
./install.sh          # symlinks the CLI, the skill and the rule into this checkout
tests/run.sh          # the whole check, a few seconds
```

Requires bash, `jq` and `flock`. Nothing is installed globally, and `install.sh` never
uses `sudo`.

`tests/run.sh` is self-contained: it runs against a temporary state directory, feeds the
hook handler the payload shapes captured from real Claude Code sessions, and fakes time
by editing the JSON state files. Run it before every commit. A few expectations are
second-granular, so a rare failure exactly on a second boundary is a rerun, not a bug.

## Layout

```
cc_progress/
  bin/cc-progress     the tool: bash + jq, one file, every command
  install.sh          wires the status line block, the hooks, the skill and the rule
  skill/SKILL.md      what Claude reads when it decides to use the bar
  rules/progress-bar.md
                      the one-paragraph rule loaded in every session
  __init__.py         the PyPI entry point: hands every command to bin/cc-progress
install.sh            source-checkout shim for cc_progress/install.sh
tests/run.sh          the check
assets/make-demo.py   renders real CLI output into the README screenshots
```

The status line and the hooks always run `bin/cc-progress` directly, never the Python
wrapper, so a poll costs about ten milliseconds.

## Changing the rendering

Edit a copy, run `bash -n` and `tests/run.sh` against it, then move it into place in one
`mv`: on a machine where it is installed from source, the status line runs the checked-out
script every second. Re-render a real session afterwards and look at it. If the look
changed, regenerate the screenshots with `python3 assets/make-demo.py` (needs Pillow and
DejaVu Sans Mono).

Colours are ANSI roles only (green, yellow, red, cyan, bright black, bold). Never add a
fixed RGB value: the terminal theme decides what the bar looks like.

## Commits and pull requests

Commit subjects are sentences about the change, not conventional-commit prefixes; look at
`git log` before writing one. No attribution trailers. Every change to the CLI's flags
is mirrored in `usage()`, `README.md`, `AGENT_INSTALL.md` and `skill/SKILL.md` in the
same commit. `main` requires a pull request with one review.

## Releasing

Versions follow [semantic versioning](https://semver.org): a patch for a fix, a minor
for a new command, flag or rendering change, a major for anything that changes the state
file format or the meaning of an existing flag.

1. Bump the version in the three places that carry it, which the test suite holds equal:
   `VERSION=` in `cc_progress/bin/cc-progress`, `version` in `pyproject.toml`, and
   `__version__` in `cc_progress/__init__.py`.
2. Commit, tag `vX.Y.Z` on `main`, push the tag.
3. Create a GitHub release from the tag. Publishing it runs `python-publish.yml`, which
   checks that the tag equals the version, builds the package and uploads it to PyPI
   through trusted publishing (no token).

Do **not** move a tag that has already been published: cut the next patch version
instead.

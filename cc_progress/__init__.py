"""cc-progress: progress bars with ETA for the Claude Code status line.

The tool is a bash script (bin/cc-progress) so that the status line can run it in a
few milliseconds. This module is the PyPI entry point: it hands every command to that
script, and `install` / `uninstall` to the installer that wires the status line and the
hooks. Requires bash, jq and flock on PATH.
"""
import os
import shutil
import sys
from pathlib import Path

__version__ = "0.5.0"

PKG = Path(__file__).resolve().parent
SCRIPT = PKG / "bin" / "cc-progress"
INSTALLER = PKG / "install.sh"


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    bash = shutil.which("bash")
    if not bash:
        sys.stderr.write("cc-progress: bash is required\n")
        return 2
    if argv and argv[0] in ("install", "uninstall"):
        env = dict(os.environ, CC_PROGRESS_NO_SYMLINK="1")   # the package already put cc-progress on PATH
        args = (["--uninstall"] if argv[0] == "uninstall" else []) + argv[1:]
        os.execve(bash, [bash, str(INSTALLER), *args], env)
    os.execv(bash, [bash, str(SCRIPT), *argv])


if __name__ == "__main__":
    sys.exit(main())

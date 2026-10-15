#!/usr/bin/env bash
# Source checkout entry point: the installer lives with the package.
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/cc_progress/install.sh" "$@"

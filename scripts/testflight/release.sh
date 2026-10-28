#!/bin/bash
# Thin bootstrap wrapper: release.py needs pyjwt + cryptography for ES256-signed App Store
# Connect API requests, which macOS's system Python refuses to install globally (PEP 668) — so
# this keeps a small dedicated venv instead, created on first run and reused after that.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VENV_DIR="$REPO_ROOT/.venv-testflight"

if [ ! -d "$VENV_DIR" ]; then
    echo "Setting up TestFlight release venv (first run only)..."
    python3 -m venv "$VENV_DIR"
fi

"$VENV_DIR/bin/pip" install --quiet --upgrade pip
"$VENV_DIR/bin/pip" install --quiet pyjwt cryptography

exec "$VENV_DIR/bin/python3" "$SCRIPT_DIR/release.py" "$@"

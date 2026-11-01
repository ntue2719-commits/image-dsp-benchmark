#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

command -v gcc >/dev/null 2>&1 || { echo "ERROR: gcc is required." >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 is required." >&2; exit 1; }

if [ ! -x "$ROOT/.venv/bin/python" ]; then
    if ! python3 -m venv "$ROOT/.venv"; then
        echo "ERROR: python3 venv support is required (typically python3-venv)." >&2
        exit 1
    fi
fi

"$ROOT/.venv/bin/pip" install -r "$ROOT/requirements.txt"
gcc -O3 -std=c11 -Wall -Wextra "$ROOT/common/cpu_dsp.c" -o "$ROOT/orangepi/cpu_dsp"

echo "Orange Pi benchmark install complete."
echo "Run: cd $ROOT && .venv/bin/python orangepi/app.py"
echo "Default URL: http://<ORANGE-PI-IP>:8080"

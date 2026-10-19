#!/usr/bin/env bash
# Explicit opt-in to a FINITE autonomous diagnostic worker (not AI DLL execution).
# Always enroll/check first, schedule second. No RunAtLoad, no game during install.
set -euo pipefail

fail() { printf 'OPENLRR WORKER INSTALL STOP: %s\n' "$*" >&2; exit 2; }
repo="$HOME/OpenLRR-Agent"
python="$HOME/.local/share/openlrr-agent/venv/bin/python"
worker="$repo/scripts/macos/approved-diagnostic-worker.py"
config="$HOME/.config/openlrr-benchmark"
logs="$HOME/.local/share/openlrr-agent/logs"
plist="$HOME/Library/LaunchAgents/com.maultzlabs.openlrr-approved-diagnostic.plist"

[ "$#" -eq 1 ] && [ "$1" = "--explicitly-enroll-fixed-diagnostic" ] ||
  fail "Explicit flag required: --explicitly-enroll-fixed-diagnostic"
[ -x "$python" ] || fail "Dedicated Python environment missing"
[ -s "$worker" ] || fail "Lab checkout missing approved finite worker"
[ ! -e "$plist" ] || fail "LaunchAgent already installed; do not replace"
[ ! -e "$config/STOP" ] || fail "STOP active"
[ ! -e "$config/PAUSE" ] || fail "PAUSE active"
[ ! -e "$config/supervisor.lock" ] || fail "Supervisor lock active"
[ ! -e "$HOME/.local/share/openlrr-agent/approved-diagnostic-worker.lock" ] ||
  fail "Existing worker lock requires inspection"
command -v gh >/dev/null 2>&1 || fail "GitHub CLI missing"
gh auth status >/dev/null 2>&1 || fail "GitHub CLI not authenticated"

# Owner explicitly authorizes only two repetitions of the exact already-tested
# DLL SHA, in the isolated TEST game, for at most seven days. This invocation
# does NOT run Wine and does NOT permit new AI-authored candidate binaries.
"$python" "$worker" --enroll-known-diagnostic
"$python" "$worker"

mkdir -p "$logs" "$HOME/Library/LaunchAgents"
chmod 700 "$logs"
OPENLRR_PYTHON="$python" OPENLRR_WORKER="$worker" OPENLRR_LOGS="$logs" \
OPENLRR_PLIST="$plist" "$python" - <<'PY'
import os
from pathlib import Path
import plistlib

target = Path(os.environ["OPENLRR_PLIST"])
if target.exists() or target.is_symlink():
    raise SystemExit("Existing plist cannot be overwritten")
entry = {
    "Label": "com.maultzlabs.openlrr-approved-diagnostic",
    "ProgramArguments": [
        os.environ["OPENLRR_PYTHON"],
        os.environ["OPENLRR_WORKER"],
        "--run",
    ],
    "RunAtLoad": False,
    "StartInterval": 86400,
    "StandardOutPath": str(Path(os.environ["OPENLRR_LOGS"]) / "approved-diagnostic.log"),
    "StandardErrorPath": str(Path(os.environ["OPENLRR_LOGS"]) / "approved-diagnostic-errors.log"),
}
with target.open("xb") as stream:
    plistlib.dump(entry, stream)
target.chmod(0o600)
PY

if launchctl bootstrap "gui/$(id -u)" "$plist"; then
  printf '%s\n' 'Finite TEST diagnostic scheduled (one attempt/day, max two attempts, seven-day approval).'
  printf '%s\n' 'No new AI-authored DLL can run; STOP/PAUSE and stale locks block execution.'
  printf '%s\n' 'STOP: touch "$HOME/.config/openlrr-benchmark/STOP"'
else
  rm -f "$plist"
  fail "launchd registration failed; approval file retained but worker not installed"
fi

#!/usr/bin/env bash
# One-time opt-in to automatic *quarantine only* GitHub candidate discovery.
# Never runs a game, installs a DLL, merges code, or requests an API key.
set -euo pipefail

repo="$HOME/OpenLRR-Agent"
python="$HOME/.local/share/openlrr-agent/venv/bin/python"
scan="$repo/scripts/macos/candidate-inbox-scan.py"
config="$HOME/.config/openlrr-benchmark"
logs="$HOME/.local/share/openlrr-agent/logs"
plist="$HOME/Library/LaunchAgents/com.maultzlabs.openlrr-candidate-inbox.plist"

[ -x "$python" ] || { echo 'Dedicated Python environment unavailable'; exit 2; }
[ -s "$scan" ] || { echo 'Update the OpenLRR-Agent checkout first'; exit 2; }
[ ! -e "$config/STOP" ] || { echo 'STOP flag active'; exit 2; }
[ ! -e "$plist" ] || { echo 'Existing agent detected; refusing replacement'; exit 2; }
command -v gh >/dev/null || { echo 'GitHub CLI missing'; exit 2; }
gh auth status >/dev/null 2>&1 || { echo 'GitHub account not authenticated'; exit 2; }
"$python" "$scan"  # safe cloud-only dry-run preflight, no DLL download
mkdir -p "$logs" "$HOME/Library/LaunchAgents"
chmod 700 "$logs"

OPENLRR_PLIST="$plist" OPENLRR_PYTHON="$python" OPENLRR_SCAN="$scan" \
OPENLRR_LOGS="$logs" "$python" - <<'PY'
import os
import plistlib
from pathlib import Path
plist = {
    "Label": "com.maultzlabs.openlrr-candidate-inbox",
    "ProgramArguments": [os.environ["OPENLRR_PYTHON"], os.environ["OPENLRR_SCAN"],
                         "--quarantine"],
    "RunAtLoad": False,
    "StartInterval": 900,
    "StandardOutPath": str(Path(os.environ["OPENLRR_LOGS"]) / "candidate-inbox.log"),
    "StandardErrorPath": str(Path(os.environ["OPENLRR_LOGS"]) / "candidate-inbox-errors.log"),
}
with open(os.environ["OPENLRR_PLIST"], "wb") as handle:
    plistlib.dump(plist, handle)
PY

if launchctl bootstrap "gui/$(id -u)" "$plist"; then
  echo 'Quarantine-only GitHub candidate polling enabled (every 15 minutes).'
  echo 'No game execution, binary installation or source modifications authorized.'
else
  rm -f "$plist"
  echo 'LaunchAgent could not be enabled; plist rolled back.'
  exit 2
fi

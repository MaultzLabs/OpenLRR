#!/bin/bash
# Unattended OpenLRR menu performance baseline, TEST APP ONLY.
set -euo pipefail
APP="$HOME/Applications/Sikarugir/OpenLRR Menu Test.app"
GAME="$APP/Contents/SharedSupport/prefix/drive_c/Program Files/Rock Raiders OpenLRR"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZIP="${OPENLRR_BENCH_ZIP:-$HOME/Downloads/OpenLRR-autobenchmark-x86.zip}"
SECONDS_TO_RUN="${OPENLRR_BENCH_SECONDS:-210}"
RESULTS="$HOME/Downloads/OpenLRR Benchmark Runs"
# Read only a repository name, never execute arbitrary commands from a config file.
UPLOAD_CONFIG="$HOME/.config/openlrr-benchmark/private-results-repo"
if [[ -z "${OPENLRR_REPORT_REPO:-}" && -f "$UPLOAD_CONFIG" ]]; then
  IFS= read -r OPENLRR_REPORT_REPO < "$UPLOAD_CONFIG" || true
  export OPENLRR_REPORT_REPO
fi

if [[ ! -d "$APP" || ! -f "$GAME/openlrr.dll" || ! -f "$GAME/LegoRR.exe" ]]; then
  echo "ERROR: Expected TEST APP missing. No changes were made." >&2
  exit 1
fi
if [[ ! -f "$SCRIPT_DIR/openlrr.dll" && ! -f "$ZIP" ]]; then
  echo "ERROR: Cannot find openlrr.dll beside this script or benchmark DLL ZIP: $ZIP" >&2
  exit 1
fi
if [[ ! "$SECONDS_TO_RUN" =~ ^[0-9]+$ ]] || (( SECONDS_TO_RUN < 15 || SECONDS_TO_RUN > 600 )); then
  echo "ERROR: Benchmark duration must be 15..600 seconds." >&2
  exit 1
fi
for name in menuperf.gdi menuperf.nowait menuperf.optimize menuperf.autotest; do
  if [[ -e "$GAME/$name" ]]; then
    echo "ERROR: $name is already active. Stop that experiment first." >&2
    exit 1
  fi
done

STAMP="$(date +%Y-%m-%d_%H-%M-%S)"
RUN="$RESULTS/autobenchmark-$STAMP"
mkdir -p "$RUN"
if [[ -f "$SCRIPT_DIR/openlrr.dll" ]]; then
  cp "$SCRIPT_DIR/openlrr.dll" "$RUN/benchmark-openlrr.dll"
else
  unzip -p "$ZIP" openlrr.dll > "$RUN/benchmark-openlrr.dll"
fi
if [[ ! -s "$RUN/benchmark-openlrr.dll" ]]; then
  echo "ERROR: No DLL was found inside the ZIP." >&2
  exit 1
fi
if [[ "$(dd if="$RUN/benchmark-openlrr.dll" bs=1 count=2 2>/dev/null)" != "MZ" ]]; then
  echo "ERROR: Invalid Windows DLL in ZIP." >&2
  exit 1
fi

cp -p "$GAME/openlrr.dll" "$RUN/previous-openlrr.dll"
if [[ -f "$GAME/menuperf.csv" ]]; then
  cp -p "$GAME/menuperf.csv" "$RUN/previous-menuperf.csv"
fi
had_enable=0
if [[ -e "$GAME/menuperf.enable" ]]; then had_enable=1; fi

cleanup() {
  set +e
  rm -f "$GAME/menuperf.autotest" "$GAME/menuperf.finished" "$GAME/menuperf.enable"
  if (( had_enable )); then touch "$GAME/menuperf.enable"; fi
  if [[ -f "$RUN/previous-openlrr.dll" ]]; then
    cp -p "$RUN/previous-openlrr.dll" "$GAME/openlrr.dll"
  fi
}
trap cleanup EXIT

rm -f "$GAME/menuperf.csv" "$GAME/menuperf.finished"
cp "$RUN/benchmark-openlrr.dll" "$GAME/openlrr.dll"
printf '%s\n' "$SECONDS_TO_RUN" > "$GAME/menuperf.autotest"
touch "$GAME/menuperf.enable"

echo "Running OpenLRR Menu Test.app with automatic mode selection and shutdown."
echo "Benchmark duration: $SECONDS_TO_RUN seconds after first rendered frame."
echo "Logs: $RUN"
open "$APP"

started_at=$(date +%s)
deadline=$(( started_at + SECONDS_TO_RUN + 300 ))
last_status=0
finished=0
while (( $(date +%s) < deadline )); do
  if [[ -f "$GAME/menuperf.finished" ]]; then
    finished=1
    break
  fi
  now=$(date +%s)
  if (( now - last_status >= 20 )); then
    last_status=$now
    if [[ -f "$GAME/menuperf.csv" && $(wc -l < "$GAME/menuperf.csv") -gt 10 ]]; then
      phase="performance data is being recorded"
    else
      phase="waiting for initial frames"
    fi
    echo "[elapsed $((now - started_at))s, watchdog limit $((deadline - now))s remaining] $phase"
  fi
  sleep 2
done
sleep 3
if [[ -f "$GAME/menuperf.csv" ]]; then cp -p "$GAME/menuperf.csv" "$RUN/menuperf.csv"; fi
if [[ -f "$GAME/menuperf.finished" ]]; then cp -p "$GAME/menuperf.finished" "$RUN/menuperf.finished"; fi


if [[ ! -f "$RUN/menuperf.csv" ]]; then
  echo "ERROR: Game produced no new menuperf.csv; no upload performed." >&2
  exit 2
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: Python 3 is needed for portable performance reporting; no upload performed." >&2
  exit 2
fi
if [[ ! -f "$SCRIPT_DIR/analyze-benchmark.py" ]]; then
  echo "ERROR: analyze-benchmark.py must be beside this script; no upload performed." >&2
  exit 2
fi
baseline_args=()
DEFAULT_BASELINE="$RESULTS/autobenchmark-2026-10-18_01-40-16/menuperf.csv"
if [[ -n "${OPENLRR_BASELINE_CSV:-}" ]]; then
  if [[ ! -f "$OPENLRR_BASELINE_CSV" ]]; then
    echo "ERROR: Explicit baseline CSV missing: $OPENLRR_BASELINE_CSV" >&2
    exit 2
  fi
  baseline_args=(--baseline "$OPENLRR_BASELINE_CSV")
elif [[ -f "$DEFAULT_BASELINE" && "$DEFAULT_BASELINE" != "$RUN/menuperf.csv" ]]; then
  baseline_args=(--baseline "$DEFAULT_BASELINE")
fi
python3 "$SCRIPT_DIR/analyze-benchmark.py" "$RUN" "${baseline_args[@]}"

# Optional private GitHub reporting. Never send data without explicit configuration,
# and never publish to a public repository (uploader checks visibility).
if [[ -n "${OPENLRR_REPORT_REPO:-}" ]]; then
  if [[ -f "$SCRIPT_DIR/publish-benchmark.sh" ]]; then
    if bash "$SCRIPT_DIR/publish-benchmark.sh" "$RUN"; then
      echo "GitHub benchmark upload completed."
    else
      echo "WARNING: private GitHub upload failed. Local logs remain in $RUN" >&2
    fi
  else
    echo "WARNING: private GitHub uploader script not found; local results preserved." >&2
  fi
fi

if [[ -f "$RUN/menuperf.csv" ]]; then open -R "$RUN/menuperf.csv"; else open "$RUN"; fi
if (( ! finished )); then
  echo "Benchmark timeout: close the TEST game manually if still running." >&2
  echo "No process was forcibly killed." >&2
  exit 2
fi
echo "Complete; the prior test DLL and marker configuration will be restored."

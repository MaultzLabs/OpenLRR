#!/bin/bash
# Unattended OpenLRR menu performance baseline, TEST APP ONLY.
set -euo pipefail
APP="$HOME/Applications/Sikarugir/OpenLRR Menu Test.app"
GAME="$APP/Contents/SharedSupport/prefix/drive_c/Program Files/Rock Raiders OpenLRR"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZIP="${OPENLRR_BENCH_ZIP:-$HOME/Downloads/OpenLRR-autobenchmark-x86.zip}"
SECONDS_TO_RUN="${OPENLRR_BENCH_SECONDS:-210}"
BENCH_MODE="${OPENLRR_BENCH_MODE:-baseline}"
SUPERVISED="${OPENLRR_SUPERVISED:-0}"
VISUAL_TIMELINE="${OPENLRR_VISUAL_TIMELINE:-0}"
if [[ "$VISUAL_TIMELINE" != "0" && "$VISUAL_TIMELINE" != "1" ]]; then
  echo "ERROR: Invalid visual-timing switch." >&2; exit 2
fi
if [[ "$VISUAL_TIMELINE" == "1" ]]; then
  if [[ "$SUPERVISED" != "1" || ! -f "$SCRIPT_DIR/visual_timeline.py" ]]; then
    echo "ERROR: Visual timing requires supervised TEST runner and helper." >&2; exit 2
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: Python 3 required for TEST timing markers." >&2; exit 2
  fi
fi
SWITCH_DIR="$HOME/.config/openlrr-benchmark"
if [[ "$SUPERVISED" != "0" && "$SUPERVISED" != "1" ]]; then
  echo "ERROR: Invalid supervision flag." >&2; exit 2
fi
# Only one graphics variable may change in a run. Keep all variants opt-in.
# The nonblocking DirectDraw flag can skip presentation; frame counts alone
# cannot prove that every frame reached the display.
case "$BENCH_MODE" in
  baseline) MODE_MARKER="" ;;
  nowait) MODE_MARKER="menuperf.nowait" ;;
  gdi) MODE_MARKER="menuperf.gdi" ;;
  *) echo "ERROR: Unsupported benchmark mode: $BENCH_MODE (use baseline, nowait or gdi)." >&2; exit 2 ;;
esac
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
if [[ "$SUPERVISED" == "1" ]]; then
  if [[ -e "$SWITCH_DIR/STOP" || -e "$SWITCH_DIR/PAUSE" ]]; then
    echo "ERROR: Controller is stopped or paused." >&2; exit 2
  fi
  if ! command -v lsof >/dev/null 2>&1; then
    echo "ERROR: lsof required for supervised lifecycle checks." >&2; exit 2
  fi
  if [[ -n "$(lsof -nP -t +D "$GAME" 2>/dev/null || true)" ]]; then
    echo "ERROR: TEST game has open file handles; refuse to overwrite its DLL." >&2; exit 2
  fi
fi
for name in menuperf.gdi menuperf.nowait menuperf.optimize menuperf.autotest menuperf.stop; do
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
restore_safe=0
launched=0
launcher_pid=""
stop_requested=0

cleanup() {
  set +e
  if [[ "$SUPERVISED" == "1" && "$launched" == "1" && "$restore_safe" != "1" ]]; then
    echo "SAFETY HOLD: TEST process exit not verified. Backup kept in $RUN." >&2
    echo "No DLL restoration attempted while Wine may still be running." >&2
    echo "Close ONLY OpenLRR Menu Test.app, verify Wine is gone, then request manual recovery." >&2
    return
  fi
  rm -f "$GAME/menuperf.autotest" "$GAME/menuperf.finished" "$GAME/menuperf.enable" "$GAME/menuperf.stop"
  if [[ -n "$MODE_MARKER" ]]; then rm -f "$GAME/$MODE_MARKER"; fi
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
if [[ -n "$MODE_MARKER" ]]; then touch "$GAME/$MODE_MARKER"; fi

# Explicit opt-in only. Record start immediately before the dedicated TEST
# app launch. Never start the game when timing provenance cannot be written.
if [[ "$VISUAL_TIMELINE" == "1" ]]; then
  visual_approved_sha="$(shasum -a 256 "$RUN/benchmark-openlrr.dll" | awk '{print $1}')"
  python3 "$SCRIPT_DIR/visual_timeline.py" start \
    --run "$RUN" --dll-sha "$visual_approved_sha" --mode "$BENCH_MODE"
fi

echo "Running OpenLRR Menu Test.app with automatic mode selection and shutdown."
echo "Graphics experiment: $BENCH_MODE"
echo "Benchmark duration: $SECONDS_TO_RUN seconds after first rendered frame."
echo "Logs: $RUN"
if [[ "$SUPERVISED" == "1" ]]; then
  launched=1
  open -W "$APP" &
  launcher_pid=$!
else
  open "$APP"
fi

started_at=$(date +%s)
deadline=$(( started_at + SECONDS_TO_RUN + 300 ))
last_status=0
finished=0
while (( $(date +%s) < deadline )); do
  if [[ "$SUPERVISED" == "1" && -e "$SWITCH_DIR/STOP" ]]; then
    if (( ! stop_requested )); then
      stop_requested=1
      echo "STOP received: requesting graceful shutdown of the TEST game."
      touch "$GAME/menuperf.stop"
      deadline=$(( $(date +%s) + 40 ))
    fi
  fi
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
if [[ "$SUPERVISED" == "1" ]]; then
  if (( ! finished )); then
    echo "ERROR: No close-request receipt from TEST game; fail closed." >&2
    exit 2
  fi
  # 'open -W' is an application lifecycle signal. It must exit, and no
  # file handles may remain inside the isolated TEST game directory.
  wait_deadline=$(( $(date +%s) + 45 ))
  while kill -0 "$launcher_pid" 2>/dev/null; do
    if (( $(date +%s) >= wait_deadline )); then
      echo "ERROR: macOS wrapper did not exit in time." >&2
      exit 2
    fi
    sleep 1
  done
  if ! wait "$launcher_pid"; then
    echo "ERROR: macOS wrapper returned a launch/exit failure." >&2
    exit 2
  fi
  sleep 2
  if [[ -n "$(lsof -nP -t +D "$GAME" 2>/dev/null || true)" ]]; then
    echo "ERROR: TEST prefix still has open file handles." >&2
    exit 2
  fi
  restore_safe=1
  printf 'wrapper_wait_exited=yes\ntest_game_handles=none\n' > "$RUN/lifecycle.verified"
  if [[ "$VISUAL_TIMELINE" == "1" ]]; then
    python3 "$SCRIPT_DIR/visual_timeline.py" finish --run "$RUN"
  fi
  if (( stop_requested )); then
    echo "STOP completed gracefully. Test intentionally not scored or uploaded."
    exit 130
  fi
fi
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

if [[ "$SUPERVISED" != "1" ]]; then
  if [[ -f "$RUN/menuperf.csv" ]]; then open -R "$RUN/menuperf.csv"; else open "$RUN"; fi
fi
if (( ! finished )); then
  echo "Benchmark timeout: close the TEST game manually if still running." >&2
  echo "No process was forcibly killed." >&2
  exit 2
fi
echo "Complete; the prior test DLL and marker configuration will be restored."

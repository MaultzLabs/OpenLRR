#!/bin/bash
# Unattended OpenLRR menu performance baseline, TEST APP ONLY.
set -euo pipefail
APP="$HOME/Applications/Sikarugir/OpenLRR Menu Test.app"
GAME="$APP/Contents/SharedSupport/prefix/drive_c/Program Files/Rock Raiders OpenLRR"
ZIP="${OPENLRR_BENCH_ZIP:-$HOME/Downloads/OpenLRR-autobenchmark-x86.zip}"
SECONDS_TO_RUN="${OPENLRR_BENCH_SECONDS:-210}"
RESULTS="$HOME/Downloads/OpenLRR Benchmark Runs"

if [[ ! -d "$APP" || ! -f "$GAME/openlrr.dll" || ! -f "$GAME/LegoRR.exe" ]]; then
  echo "ERROR: Expected TEST APP missing. No changes were made." >&2
  exit 1
fi
if [[ ! -f "$ZIP" ]]; then
  echo "ERROR: Missing benchmark DLL ZIP: $ZIP" >&2
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
unzip -p "$ZIP" openlrr.dll > "$RUN/benchmark-openlrr.dll"
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

deadline=$(( $(date +%s) + SECONDS_TO_RUN + 300 ))
finished=0
while (( $(date +%s) < deadline )); do
  if [[ -f "$GAME/menuperf.finished" ]]; then
    finished=1
    break
  fi
  sleep 2
done
sleep 3
if [[ -f "$GAME/menuperf.csv" ]]; then cp -p "$GAME/menuperf.csv" "$RUN/menuperf.csv"; fi
if [[ -f "$GAME/menuperf.finished" ]]; then cp -p "$GAME/menuperf.finished" "$RUN/menuperf.finished"; fi

{
  echo "OpenLRR unattended benchmark"
  echo "Run: $STAMP"
  echo "Requested duration: $SECONDS_TO_RUN s"
  if (( finished )); then echo "In-game close requested"; else echo "Timed out before close marker"; fi
  if [[ -f "$RUN/menuperf.csv" ]]; then
    awk -F, '
      NR == 1 { for (i=1; i<=NF; i++) col[$i]=i; next }
      $(col["operation"])=="frame_flip" {
        total_secs += $(col["seconds"]); flips += $(col["calls"])
      }
      $(col["operation"])=="window_present_blt" {
        presents += $(col["calls"]); present_ms += $(col["total_ms"])
        if ($(col["max_ms"])>1000) slow_intervals++
        if ($(col["max_ms"])>max_ms) max_ms=$(col["max_ms"])
      }
      END {
        printf "Logged duration (s): %.1f\n", total_secs
        printf "Frames presented: %.0f\n", flips
        printf "Present calls: %.0f\n", presents
        printf "Time inside present (s): %.3f\n", present_ms/1000
        printf "Intervals with >1s present call: %d\n", slow_intervals
        printf "Worst present call (ms): %.3f\n", max_ms
      }
    ' "$RUN/menuperf.csv"
  else
    echo "No new performance CSV was written."
  fi
} | tee "$RUN/report.txt"

if [[ -f "$RUN/menuperf.csv" ]]; then open -R "$RUN/menuperf.csv"; else open "$RUN"; fi
if (( ! finished )); then
  echo "Benchmark timeout: close the TEST game manually if still running." >&2
  echo "No process was forcibly killed." >&2
  exit 2
fi
echo "Complete; the prior test DLL and marker configuration will be restored."

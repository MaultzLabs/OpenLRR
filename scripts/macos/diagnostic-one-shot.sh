#!/usr/bin/env bash
# One-shot, supervised *diagnostic* benchmark. Not a background daemon.
# Usage: bash diagnostic-one-shot.sh RUN_ID COMMIT_SHA40
# Download only a successful, explicitly pinned Win32 workflow artifact.
set -euo pipefail

fail() { printf 'DIAGNOSTIC STOP: %s\n' "$*" >&2; exit 2; }
if [ "$#" -ne 2 ]; then
  fail "Expected GitHub run ID and reviewed full commit SHA"
fi
run_id="$1"
commit_sha="$2"
# Optional, trusted session orchestration. Default is unchanged.
plan="${OPENLRR_DIAGNOSTIC_PLAN:-baseline,baseline}"
case "$plan" in
  baseline|baseline,baseline|baseline,nowait,baseline,nowait|baseline,gdi,baseline,gdi) ;;
  *) fail "Unsupported graphics experiment plan; refusing arbitrary modes" ;;
esac
reviewed_sha="${OPENLRR_DIAGNOSTIC_REVIEWED_SHA256:-}"
if [ -n "$reviewed_sha" ]; then
  [[ "$reviewed_sha" =~ ^[a-f0-9]{64}$ ]] || fail "Invalid owner-reviewed DLL SHA256"
fi
[[ "$run_id" =~ ^[0-9]{8,14}$ ]] || fail "Invalid workflow run ID"
[[ "$commit_sha" =~ ^[a-f0-9]{40}$ ]] || fail "Expected lowercase, full 40-character commit SHA"

for command in gh shasum lsof; do
  command -v "$command" >/dev/null 2>&1 || fail "Required command missing: $command"
done
game="$HOME/Applications/Sikarugir/OpenLRR Menu Test.app/Contents/SharedSupport/prefix/drive_c/Program Files/Rock Raiders OpenLRR"
config="$HOME/.config/openlrr-benchmark"
downloads="$HOME/Downloads"
supervisor="$HOME/OpenLRR-Agent/scripts/macos/lab-supervisor.py"
python="$HOME/.local/share/openlrr-agent/venv/bin/python"

[ -f "$game/LegoRR.exe" ] || fail "Isolated OpenLRR Menu Test.app not found"
[ -f "$supervisor" ] || fail "Approved Mac supervisor missing"
[ -x "$python" ] || fail "Dedicated AI lab virtualenv missing"
[ ! -e "$config/STOP" ] || fail "STOP flag active; do not override it"
[ ! -e "$config/PAUSE" ] || fail "PAUSE flag active; do not override it"
[ ! -e "$config/supervisor.lock" ] || fail "Supervisor lock active; inspect test process before continuing"
open_handles="$(lsof -nP -t +D "$game" 2>/dev/null || true)"
if [ -n "$open_handles" ]; then
  fail "TEST game has open file handles; close it before attempting diagnosis"
fi

run_sha="$(gh run view "$run_id" --repo MaultzLabs/OpenLRR --json headSha --jq '.headSha')"
run_state="$(gh run view "$run_id" --repo MaultzLabs/OpenLRR --json conclusion --jq '.conclusion')"
run_workflow="$(gh run view "$run_id" --repo MaultzLabs/OpenLRR --json workflowName --jq '.workflowName')"
[ "$run_sha" = "$commit_sha" ] || fail "Workflow commit is not the reviewed commit"
[ "$run_state" = "success" ] || fail "Workflow is not a completed success"
[ "$run_workflow" = "OpenLRR Menu Diagnostics Win32" ] || fail "Unexpected workflow source"

tmp="$(mktemp -d -t openlrr-diagnostics.XXXXXXXX)"
[ -d "$tmp" ] || fail "Cannot allocate diagnostic staging directory"
mkdir -p "$tmp/previous" "$tmp/artifact"
staged=0
cleanup() {
  status="$?"
  trap - EXIT
  if [ "$staged" -eq 1 ]; then
    for f in openlrr.dll run-autobenchmark.sh publish-benchmark.sh privacy-validate-benchmark.py analyze-benchmark.py; do
      if [ -f "$tmp/previous/$f" ]; then
        cp -p "$tmp/previous/$f" "$downloads/$f"
      else
        rm -f "$downloads/$f"
      fi
    done
  fi
  rm -rf "$tmp"
  exit "$status"
}
trap cleanup EXIT

gh run download "$run_id" --repo MaultzLabs/OpenLRR \
  --name OpenLRR-menu-diagnostics-x86 --dir "$tmp/artifact"
for f in openlrr.dll SHA256.txt run-autobenchmark.sh publish-benchmark.sh privacy-validate-benchmark.py analyze-benchmark.py; do
  [ -s "$tmp/artifact/$f" ] || fail "Expected artifact missing: $f"
done
expected="$(tr -d '\r\n[:space:]' < "$tmp/artifact/SHA256.txt" | tr '[:upper:]' '[:lower:]')"
[[ "$expected" =~ ^[a-f0-9]{64}$ ]] || fail "Invalid published SHA256 format"
actual="$(shasum -a 256 "$tmp/artifact/openlrr.dll" | awk '{print $1}')"
[ "$actual" = "$expected" ] || fail "DLL SHA256 did not match CI artifact"
if [ -n "$reviewed_sha" ]; then
  [ "$actual" = "$reviewed_sha" ] || fail "Cloud DLL differs from owner-reviewed TEST binary"
fi

mkdir -p "$downloads"
for f in openlrr.dll run-autobenchmark.sh publish-benchmark.sh privacy-validate-benchmark.py analyze-benchmark.py; do
  if [ -e "$downloads/$f" ]; then cp -p "$downloads/$f" "$tmp/previous/$f"; fi
done
staged=1
for f in openlrr.dll run-autobenchmark.sh publish-benchmark.sh privacy-validate-benchmark.py analyze-benchmark.py; do
  cp -p "$tmp/artifact/$f" "$downloads/$f"
done
printf 'Verified diagnostic DLL SHA256: %s\n' "$actual"
printf 'Target: isolated OpenLRR Menu Test.app only\n'
printf 'Plan: %s, 60 seconds each; STOP/PAUSE respected\n' "$plan"
"$python" "$supervisor" --approved-sha "$actual" --plan "$plan" --seconds 60 --run
printf 'All supervised diagnostic runs verified and uploaded to the private results repo.\n'
printf 'Only the reviewed SHA-pinned TEST DLL was executed. Local download files restored on exit.\n'

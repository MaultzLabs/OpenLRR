#!/bin/bash
# Upload only selected OpenLRR benchmark telemetry to a PRIVATE GitHub repository.
# Usage: OPENLRR_REPORT_REPO=MaultzLabs/OpenLRR-Test-Results bash publish-benchmark.sh "path-to-run-directory"
set -euo pipefail

RUN_DIR="${1:?Usage: publish-benchmark.sh /path/to/benchmark-run-directory}"
REPORT_REPO="${OPENLRR_REPORT_REPO:-}"
UPLOAD_CONFIG="$HOME/.config/openlrr-benchmark/private-results-repo"
# Allow standalone uploads and the unattended runner to use the same trusted
# repository-name setting. Never source the configuration as shell commands.
if [[ -z "$REPORT_REPO" && -f "$UPLOAD_CONFIG" ]]; then
  IFS= read -r REPORT_REPO < "$UPLOAD_CONFIG" || true
fi
if [[ -z "$REPORT_REPO" ]]; then
  echo "Upload not configured. Set OPENLRR_REPORT_REPO or private-results-repo." >&2
  exit 2
fi
if [[ ! "$REPORT_REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "Invalid repository name. Expected owner/repo." >&2
  exit 2
fi
if [[ ! -d "$RUN_DIR" || ! -f "$RUN_DIR/menuperf.csv" ]]; then
  echo "Missing benchmark directory or CSV; no upload performed." >&2
  exit 2
fi
if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI (gh) is not installed. See docs/autobenchmark.md." >&2
  exit 2
fi
if ! command -v git >/dev/null 2>&1; then
  echo "Git is required to verify previously uploaded content." >&2
  exit 2
fi
if ! gh auth status -h github.com >/dev/null 2>&1; then
  echo "GitHub CLI is not authenticated. Run: gh auth login" >&2
  exit 2
fi
visibility="$(gh repo view "$REPORT_REPO" --json visibility --jq '.visibility' 2>/dev/null || true)"
if [[ "$visibility" != "PRIVATE" ]]; then
  echo "Refusing to upload: destination must exist and be PRIVATE." >&2
  exit 2
fi

run_name="$(basename "$RUN_DIR")"
if [[ ! "$run_name" =~ ^autobenchmark-[A-Za-z0-9._-]+$ ]]; then
  echo "Unexpected run directory name, refusing upload." >&2
  exit 2
fi

# Only the current format of counters CSV is permitted. Never upload Wine
# configuration, game assets, executables, environment variables or Mac paths.
expected="seconds,optimization,nowait,gdi,operation,calls,total_ms,max_ms"
header="$(head -n 1 "$RUN_DIR/menuperf.csv" | tr -d '\r')"
if [[ "$header" != "$expected" ]]; then
  echo "CSV schema is unexpected; refusing upload." >&2
  exit 2
fi
if [[ $(wc -c < "$RUN_DIR/menuperf.csv") -gt 2000000 ]]; then
  echo "CSV exceeds 2MB size limit; refusing upload." >&2
  exit 2
fi

# Check directory existence through successful GitHub directory listings.
# Do not interpret a 404's JSON "null" .sha as an existing file.
if ! run_directories="$(gh api --method GET "repos/$REPORT_REPO/contents/runs" --jq '.[].name')"; then
  echo "Cannot read the private results directory; no upload performed." >&2
  exit 2
fi

remote_files=""
if printf '%s\n' "$run_directories" | grep -Fxq -- "$run_name"; then
  if ! remote_files="$(gh api --method GET "repos/$REPORT_REPO/contents/runs/$run_name" --jq '.[] | [.name, .sha] | @tsv')"; then
    echo "Cannot read the existing run directory; no upload performed." >&2
    exit 2
  fi
fi

get_remote_sha() {
  local sought="$1" filename sha
  while IFS=$'\t' read -r filename sha; do
    if [[ "$filename" == "$sought" ]]; then
      if [[ ! "$sha" =~ ^[0-9a-fA-F]{40}$ ]]; then
        echo "Invalid SHA returned for existing $sought; refusing upload." >&2
        return 2
      fi
      printf '%s' "$sha"
      return 0
    fi
  done <<< "$remote_files"
  return 0
}

# Existing files remain immutable; retries only fill missing files.
upload() {
  local name="$1"
  local path="$2"
  local payload remote_sha local_sha
  local_sha="$(git hash-object --no-filters "$path")"
  if [[ ! "$local_sha" =~ ^[0-9a-fA-F]{40}$ ]]; then
    echo "Could not calculate valid Git SHA for $name." >&2
    return 1
  fi
  if ! remote_sha="$(get_remote_sha "$name")"; then return 1; fi
  if [[ -n "$remote_sha" ]]; then
    if [[ "$remote_sha" == "$local_sha" ]]; then
      echo "Already uploaded and unchanged: $name"
      return 0
    fi
    if [[ "$name" == "menuperf.csv" ]]; then
      echo "Existing raw CSV is DIFFERENT (remote=$remote_sha local=$local_sha)." >&2
      echo "Refusing to overwrite: runs/$run_name/$name" >&2
      return 1
    fi
    echo "Preserving existing $name; its content differs from current local file."
    return 0
  fi

  payload="$(mktemp)"
  {
    printf '{"message":"Record isolated OpenLRR benchmark: %s (%s)","content":"' "$run_name" "$name"
    base64 < "$path" | tr -d '\r\n'
    printf '"}'
  } > "$payload"
  if ! gh api --method PUT "repos/$REPORT_REPO/contents/runs/$run_name/$name" \
       --input "$payload" >/dev/null; then
    rm -f "$payload"
    echo "GitHub upload failed for $name. No existing file was overwritten." >&2
    return 1
  fi
  rm -f "$payload"
  echo "Uploaded new file: $name"
}

# Supervised runs have a fixed, locally verified process-exit receipt.
# Publish it only after confirming its EXACT expected two-line content.
# Unsupervised/legacy runs do not assert process exit this way.
if [[ "${OPENLRR_SUPERVISED:-0}" == "1" ]]; then
  receipt="$RUN_DIR/lifecycle.verified"
  if [[ ! -f "$receipt" ]] ||
     [[ "$(cat "$receipt")" != 
if [[ -f "$RUN_DIR/report.txt" && $(wc -c < "$RUN_DIR/report.txt") -le 65536 ]]; then
  if ! grep -Eiq '/Users/|/home/|Token|Authorization|password|gho_|ghp_|github_pat_' "$RUN_DIR/report.txt"; then
    upload "report.txt" "$RUN_DIR/report.txt"
  fi
fi
if [[ -f "$RUN_DIR/summary.json" && $(wc -c < "$RUN_DIR/summary.json") -le 65536 ]]; then
  if grep -Fq '"schema_version": 1' "$RUN_DIR/summary.json" &&
     ! grep -Eiq '/Users/|/home/|Token|Authorization|password|gho_|ghp_|github_pat_' "$RUN_DIR/summary.json"; then
    upload "summary.json" "$RUN_DIR/summary.json"
  fi
fi

echo "Uploaded this benchmark to the PRIVATE repository: https://github.com/$REPORT_REPO/tree/main/runs/$run_name"
wrapper_wait_exited=yes\ntest_game_handles=none' ]]; then
    echo "Missing or invalid verified lifecycle receipt; refusing supervised upload." >&2
    exit 2
  fi
fi

# Store only counter samples, a minimal supervisor receipt, and validated reports.
upload "menuperf.csv" "$RUN_DIR/menuperf.csv"
if [[ "${OPENLRR_SUPERVISED:-0}" == "1" ]]; then
  upload "lifecycle.verified" "$receipt"
fi
if [[ -f "$RUN_DIR/report.txt" && $(wc -c < "$RUN_DIR/report.txt") -le 65536 ]]; then
  if ! grep -Eiq '/Users/|/home/|Token|Authorization|password|gho_|ghp_|github_pat_' "$RUN_DIR/report.txt"; then
    upload "report.txt" "$RUN_DIR/report.txt"
  fi
fi
if [[ -f "$RUN_DIR/summary.json" && $(wc -c < "$RUN_DIR/summary.json") -le 65536 ]]; then
  if grep -Fq '"schema_version": 1' "$RUN_DIR/summary.json" &&
     ! grep -Eiq '/Users/|/home/|Token|Authorization|password|gho_|ghp_|github_pat_' "$RUN_DIR/summary.json"; then
    upload "summary.json" "$RUN_DIR/summary.json"
  fi
fi

echo "Uploaded this benchmark to the PRIVATE repository: https://github.com/$REPORT_REPO/tree/main/runs/$run_name"

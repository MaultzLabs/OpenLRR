# OpenLRR verified visual QA → private review bridge

Review integration branch: lab-visual-review-bridge-v1. This bridge is
read-only and fully isolated from the working Rock Raiders installation.
The visual QA engine compares existing media offline, and the bridge
independently revalidates the capture hashes, benchmark run receipts and
pixel/video scores immediately before preparing a private review request.

## Review eligibility

Review readiness requires ALL of the following:

- Verified benchmark policy says candidate_for_review with at least five
  independently validated paired TEST runs, and the policy action is hold_for_review.
- Bound screenshot/video evidence is from a declared benchmark pair, with
  consistent TEST run timing. Un-timed results are blocked for publication.
- The visual result is pass or review; regression/inconclusive results BLOCK
  publication and return a local explanation.
- STOP/PAUSE is not active and no reviewed evidence has changed since collection.
- The report carries explicit prohibitions on execution or deployment.

Importantly, the visual report currently evaluates **one pair only**
and reports visual trial coverage as 1/N. It does not claim that all benchmark
runs were visually checked. A perfect pixel score does not certify rendered
FPS, gameplay correctness, or provenance from a trusted recording process.

## Automatic offline linkage to QA pipeline

The existing one-shot scripts/visual_qa/pipeline.py now writes
`review-packet.json` next to `research-decision.json` and the verified visual
report. The packet is metadata-only. A blocked packet explains absent/unsafe
evidence; a reviewable packet includes visual scores, coverage and a concrete
human inspection checklist based on the validated finding codes. This happens
locally without any GitHub issue creation or network traffic.
## Build a read-only local packet

After collecting *real* verified TEST evidence, and only after the
Mac/Wine TEST-window adapter is independently approved:

```sh
python scripts/agent/visual_review_bridge.py \
  --manifest /private/experiments/paired_test.json \
  --runs-dir /private/benchmark-runs \
  --visual-captures /private/qa-results/captures.json \
  --visual-report /private/qa-results/analysis/report.json \
  --out /private/qa-results/new-review-packet.json
```

This produces only JSON metadata and invokes no GitHub action or model.
Existing files are never overwritten. It may return state=blocked with
explicit reason codes. This is an expected safe outcome, not an error to bypass.

## Connect to the existing review queue (explicit manual action only)

```sh
python scripts/agent/visual_review_bridge.py \
  --manifest /private/experiments/paired_test.json \
  --runs-dir /private/benchmark-runs \
  --visual-captures /private/qa-results/captures.json \
  --visual-report /private/qa-results/analysis/report.json \
  --publish --confirm-private-review
```

Only an eligible, freshly reverified result may create a private GitHub issue
in MaultzLabs/OpenLRR-Test-Results. The bridge asks GitHub to independently
confirm the target repository is PRIVATE. It deduplicates by experiment ID,
reuses the existing review issue format, and only publishes metrics, finding
codes, coverage warnings and SHA256 fingerprints — NO PNGs, video, frame
paths, recordings, tokens, or private game files.

The existing reviewer-command protocol still applies:

- /lab good: human-checked render observations
- /lab continue: describe the unresolved issue
- /lab reject: stop this hypothesis

These comments affect research priorities ONLY. None authorizes the assistant,
runner or an AI agent to install, run, merge or deploy binaries.

## CI

Synthetic TEST receipt fixtures, generated PNG comparisons and mock GitHub
calls test the ready/blocked decision gates, fail-closed score recomputation,
strict timing, public repository refusal, no-network dry-run, deduplication,
and metadata-only issue creation. CI does not access the private review
repository or operate an actual Mac.

## One-hour review system follow-up

The bridge is committed as development code; it is NOT autonomously
installed or activated. A separate scheduled execution or integration task
requires an available task slot. The preexisting hourly lab review watch is
unchanged, and no private issue is posted without the explicit publish flags.

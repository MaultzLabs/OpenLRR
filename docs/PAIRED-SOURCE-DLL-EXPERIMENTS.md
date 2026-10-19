# Two-DLL OpenLRR source-change experiments

## Why this exists

Earlier baseline/nowait and baseline/GDI experiments varied graphics settings
on **one binary**. They cannot prove that an AI-generated C++ change improves
the game. The new isolated trial orchestrator can compare TWO distinct
source-built DLLs with separate SHA256 identities and a fixed graphics mode.

The laboratory already has read-only research, restricted patch generation,
Windows x86 compilation, candidate artifact quarantine, a Mac test supervisor,
a statistical evidence gate and a deterministic research controller. This
two-DLL component links those pieces for genuine code-change experiments.

## Strict boundaries

- Only the dedicated isolated OpenLRR Menu Test.app is ever passed to the
  trusted local supervisor. The working game is not discovered or modified.
- Nothing runs merely because a candidate is uploaded or quarantined.
- Every test requires a deliberate --run, full baseline SHA256, full candidate
  SHA256 and exact successful GitHub candidate workflow run ID.
- The baseline comes from a separately verified GitHub x86 diagnostic artifact
  staged via prepare-approved-baseline.py; it will never be overwritten.
- Candidate provenance is rechecked in the local quarantine directory, and its
  review-required flag stays false for automatic execution.
- A/B order alternates across paired runs to mitigate a simple time-order bias.
- Per-run duration must be 30..180 seconds; maximum five pairs (ten game
  launches) per explicit invocation. No model chooses the run count.
- Supervisor STOP, PAUSE, lock, clean process-exit receipt, upload checks and
  target-DLL restoration remain authoritative.
- The Downloads DLL is backed up and restored even after a failed trial.
  A failed test leaves a paired-eval.lock to prevent further unattended work.
- No new binary is installed in the production game, and a statistically
  promising result cannot be automatically merged or promoted.
- Success or failure is never inferred from logical flips as visible FPS.

## One-time future Mac setup

This is NOT installed by a GitHub merge. After checking out the updated trusted
laboratory branch on your Mac:

1. Download a trusted Windows x86 baseline artifact from GitHub Actions.
   Run prepare-approved-baseline.py with the exact successful workflow run ID,
   40-character source commit SHA, and reviewed 64-character DLL SHA256.
   It dry-runs by default. Add --prepare to write the approved baseline
   under ~/.local/share/openlrr-agent/approved-baselines/.
2. When a candidate was compiled, validated and quarantined by the lab,
   inspect its source patch and artifact. Do not approve unknown code.
3. Run paired-dll-eval.py with --baseline-sha, --candidate-sha, the candidate's
   --candidate-run-id, --pairs 1 and --seconds 60. It dry-runs by default.
4. Only after explicitly approving the displayed identities, add --run to
   start the isolated TEST app using the existing supervised runner.
5. If one pair is inconclusive, and the experiment remains scientifically
   appropriate, a subsequent explicitly authorized run can request up to
   five complete matched pairs.

A simplified command template (SHA values must be real and reviewed):

    python3 scripts/macos/paired-dll-eval.py \
      --baseline-sha FULL64_BASELINE_HASH \
      --candidate-sha FULL64_CANDIDATE_HASH \
      --candidate-run-id VERIFIED_RUN_ID \
      --pairs 1 --seconds 60

Default preflight must show execution_requires_explicit_run_flag=true. The
candidate is NOT automatically promoted on successful statistical evidence.

## Evidence pipeline

For each run, the trusted supervisor checks that the isolated Wine wrapper
has exited and that no test game handles remain; it confirms a matching DLL
SHA256 and uploads benchmark results to the private results repository.

After all requested pairs, this worker stores a genuine A/B experiment
manifest under the local lab experiments directory and invokes
experiment_controller.py. That revalidates the original run receipts and
observations, applies the fixed statistical policy, and deduplicates the next
research or review decision. Five pairs are required before a result can
qualify for human review.

The current worker is intentionally *manually opt-in*, not a daemon. A future
autonomous executor will require isolated signer/approval controls, an
attested source-to-binary manifest, periodic STOP checking, time and API
spending caps, and visual QA before it can safely pick candidates itself.

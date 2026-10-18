# OpenLRR verified experiment controller

The AI lab now has a deterministic decision boundary between supervised benchmarking and new research requests: scripts/agent/experiment_controller.py.

## Capabilities

- Reads bounded experiment manifests naming actual local benchmark run directories.
- Revalidates the underlying local evidence via evidence_gate.decision: lifecycle receipt, DLL hash, graphics mode, controlled scene, duration and guardrails.
- Uses lab_policy.decide to choose the next research category. A promising candidate requires separate visual review.
- Computes a stable evidence-plus-feedback fingerprint to prevent repeated requests for unchanged results.
- Allows at most three recorded research decisions per UTC day. This is NOT an enforceable cloud API billing cap.
- Writes a decision atomically to a local JSON ledger only when the caller chooses --commit. By default it reads without modifying files.

## Example CLI

    python3 scripts/agent/experiment_controller.py \
      --manifest /path/to/experiment.json \
      --runs-dir "$HOME/Downloads/OpenLRR Benchmark Runs"

A manifest names an explicitly reviewed experiment and its paired baseline/candidate run directories. It must include schema_version=1, experiment_id, a specific hypothesis, controlled_scene=menu_boot_autotest_v1, and pairs listing baseline and candidate run IDs. It cannot authorize an executable.

The controller will refuse any duplicate experiment, unverifiable receipt, contradictory graphics mode, invalid experiment metadata, STOP/PAUSE state, tampered ledger or stale lock.

## What this does not do

- No GitHub Actions dispatch.
- No model invocation, token spending, or compilation.
- No execution of an unreviewed Windows DLL, modification to a working game, or unattended process management.
- No independent visual confirmation of actual displayed frames.
- No cryptographic attestation of who created local receipt files.

Additional work is required to connect this policy controller to the Mac's trusted test worker, private reviewer comment retrieval, and bounded cloud research jobs. The fixed daily research-request budget is a planning guardrail; it must be independently enforced at the actual API-calling boundary before unattended billing.

## Feedback and security

When feedback is supplied, its experiment_id must match the verified report, and automatic_deploy_allowed must be false. Local JSON feedback is not a substitute for authenticated GitHub issue comments. In the future, validated review_queue comments must be wired into the coordinator.

Every decision has may_install_or_run_candidate=false, may_touch_working_game=false, may_deploy_automatically=false. Successful model research, x86 compilation, or benchmark improvements never imply safe installation.

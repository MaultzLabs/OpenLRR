# Adaptive OpenLRR Laboratory — evidence and human feedback contract

## Objective

Run an evidence-driven *research cycle*, not a clock-driven sequence of arbitrary source patches.

1. AI identifies a bottleneck and writes a hypothesis, a falsifying observation, a reversible modification, the metrics it expects to change, and stop conditions.
2. Controller checks the proposed test against prior attempts. Repeated unchanged failures are not permitted simply because time elapsed.
3. GitHub statically checks and compiles the draft. A compiled binary is **not** automatically trusted.
4. The isolated Mac worker may benchmark **only an explicitly approved, SHA256-pinned build**. The existing working game remains untouched. Successful tests require shutdown confirmation and separate test logs.
5. Evidence gate uses multiple comparable baseline/candidate pairs rather than the most recent two measurements.
6. A deterministic state machine selects an investigative direction. The AI may propose a new hypothesis within that direction but may not override the evidence gate.
7. Only a credible candidate earns a private human-review issue. A human can mark it good, request more work and specify why, or reject the approach. This feedback becomes research context for the next hypothesis; it is never a shell command.
8. An approval is NOT a game deployment or automatic merge.

## Current implemented modules (development branch lab-evidence-review-v1)

- scripts/agent/evidence_gate.py: reads local Mac supervisor summary.json and lifecycle.verified receipts; rejects incomplete/unverified samples, non-matching durations, inconsistent DLLs/modes, or insufficient samples.
- scripts/agent/lab_policy.py: converts outcomes into targeted next research steps; does not execute anything.
- scripts/agent/review_queue.py: creates a private, deduplicated GitHub review issue **only** for candidate_for_review reports. Supports reviewer feedback commands, reads only approved GitHub author MaultzLabs, and optionally shows a Mac notification if the workflow executes on the Mac.
- scripts/agent/tests/test_evidence_gate.py, test_lab_policy.py, test_review_queue.py: offline tests run in CI, including accidental automatic deployment and unauthenticated review attempts.

**Not yet integrated:** automatically generating a hypothesis from the recorded research ledger, constructing and verifying five real matched pairs for a new candidate, transferring an AI-generated build from GitHub into a separately secured Windows/Mac test environment, invoking the gate and issue queue in a long-running service, and feeding reviewer comments into the next coding request. This branch is a safe component prototype, not a background service.

## Evidence policy (initial screening thresholds, adjustable after calibration)

- Minimum **5 comparable paired baseline/candidate trials**, same declared workload, consistent build within each arm, plausible durations, successful isolated-test shutdown, and no errors, busy rejects or serious FPS regressions.
- Candidate must show at least a **10% median reduction in presentation time** and a paired-bootstrap 95th-percentile upper bound better than a **5% reduction** to qualify for a **human review request**. This is a *promising numerical signal*, not a claim of statistically proven visual improvement.
- Regressions and no-improvement results are archived and steer the next hypothesis. Uncertainty should lead to instrumenting the questionable stage, not endless restarts of the same experiment.
- All measured frame-flip rates are proxies. Actual visible FPS, image quality, game behavior and stutter require independent instrumentation or a human acceptance test.

## Notification and review

A credible result can create an issue **only in the PRIVATE** MaultzLabs/OpenLRR-Test-Results repository, with a concise comparison and visual-check instructions. This avoids publishing private benchmark data to the public game repository.

Review directly on the issue by commenting exactly one of the following:

- /lab good: The test menu now looks smooth and controls respond
- /lab continue: Still freezes badly when the cursor moves over the menu
- /lab reject: The renderer corrupts colors; try a different approach

The /lab continue comment provides the explanation that the next research plan must address; /lab reject stops that experiment family. The /lab good command requests the **separate manual acceptance/security step**, not a commit or installation.

The private issue is a durable inbox. When the Mac posts it, a local Notification Center alert is attempted. **GitHub email is not guaranteed** for actions made by the same logged-in account, and depends on user notification settings. A reliable background email sender requires a separate authorized email delivery integration; it is not yet configured.

## Safety boundaries

- No executing AI-authored shell commands or unreviewed binaries on the personal Mac.
- No automatic file changes to the working game.
- No uncontrolled loops: explicit process identity, STOP/PAUSE, bounded duration, compute, API budget, and disk usage.
- Each experiment has an ID, hypothesis, source hash, measured results, reason for termination and review status.
- No duplicate review notifications for the same experiment ID.
- Any unverified outcome fails closed; the model's confidence alone cannot mark a candidate ready.
- Automated cloud *daily blind patch generation* has been disabled in main, leaving manual dispatch until the evidence-driven planner exists.

## Next engineering milestone

Connect the existing Mac supervised runner, an isolated build execution gate, the research ledger, evidence_gate, lab_policy and review_queue into one bounded orchestration service. Validate one five-pair experiment and a human feedback round trip before leaving unattended. Then implement notification delivery by the preferred channel (verified email integration or GitHub + desktop).

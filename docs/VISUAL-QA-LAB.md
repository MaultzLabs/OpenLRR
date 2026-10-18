# OpenLRR Visual QA laboratory (v1)

This is an **offline, read-only media analyzer**, developed on the isolated
`lab-visual-qa-v1` branch. It accepts already recorded captures. It never
starts OpenLRR, compiles C++, patches a DLL, accesses the working game
installation, fetches personal game assets, deploys builds, or invokes an AI
model. No screenshot/video collection has been installed on a Mac.

## What it measures

- Screenshot agreement using normalized RGB mean absolute difference,
  changed-pixel percentage and **local structural similarity** (tile SSIM).
- Sampled video agreement using the same frame metrics at a deterministic
  frame sampling rate (default 2 samples/second, up to 48 samples).
- Targeted heuristics for black screens, likely frozen presentation (candidate
  static while reference moves), unusual luminance flicker, geometry mismatches
  and unequal sample counts.
- A 0–100 **agreement** score and a `pass`, `review`, `regression`, or
  `inconclusive` classification. This is not objective image beauty, a claim
  of verified visible FPS, or a guarantee of correct gameplay.

The comparison is pixel-spatial, not semantic. Animations, camera differences,
rendering settings, display scaling, compression, frame timing offsets and
gamma changes can cause false positives. Capture the *same scene, scale, aspect
ratio, time window and settings* for both arms. The video sample index is
aligned by timestamp from each file's start; it is not motion-synchronized.
Use a white-on-black exclusion mask PNG (white = ignore) to exclude clocks,
cursors or reliably nondeterministic areas. Masks must match full frame size
and cannot hide every pixel. Review artifacts before interpreting scores.

## Offline local setup

Requires Python 3.11+, NumPy, Pillow, and (video only) ffmpeg/ffprobe.
Install dependencies into a fresh isolated environment; do **not** install into
a game folder:

```sh
python3 -m venv .venv-visual-qa
. .venv-visual-qa/bin/activate
python -m pip install 'numpy==2.2.6' 'Pillow==11.3.0'
```

Single screenshot pair:

```sh
python scripts/visual_qa/qa.py \
  --reference /private/captures/reference.png \
  --candidate /private/captures/candidate.png \
  --experiment-id graphics_test_001 \
  --scene menu_boot_autotest_v1 \
  --out /private/qa-results/graphics_test_001 \
  --fail-on-regression
```

For captured videos, supply `.mp4` (or `.mov`, `.mkv`, `.webm`, `.avi`)
instead of images and optionally add `--fps 2`. Supply `--mask file.png`
for exclusion areas. The output directory must be new or empty, **not** the
same directory holding input captures. Preexisting output files are refused
instead of overwritten. Video decodes into disposable temporary storage.

Exit codes: 0 = successful analysis (when `--fail-on-regression` is absent,
regressions are reported in JSON but do not fail the command), 3 = non-pass
with `--fail-on-regression`, 2 = failed/incomplete processing. See
`out/report.json` and `out/diff-*.png` (red indicates different pixels).

## Research-controller handoff

After a *separate* A/B benchmark has already produced genuine, verified
`summary.json` and `lifecycle.verified` evidence, the controller can
consume the visual report **as an advisory, additional research input**:

```sh
python scripts/agent/experiment_controller.py \
  --manifest /private/experiments/graphics_test_001.json \
  --runs-dir /private/benchmark-runs \
  --visual-report /private/qa-results/graphics_test_001/report.json \
  --ledger /private/experiments/controller-ledger.json
```

This does not need `--commit`; without it the ledger is not changed.
A `--visual-report` is accepted only when the experiment ID matches the
verified benchmark manifest and safety fields explicitly prohibit automatic
execution/deployment. The visual evidence fingerprint is included in the
controller's deduplication identity.

Research policy mapping:

| Visual QA | Policy effect |
|---|---|
| regression | `isolate_regression`: diagnose blocking visual differences |
| inconclusive | `improve_instrumentation`: correct captures and alignment |
| review, performance candidate for review | `hold_for_review`: human check required |
| review, other performance result | preserve original performance policy |
| pass | preserve original performance policy; does **not** approve deployment |

The controller still independently validates paired Mac test receipts. A
visual report is not proof that the captures actually came from the controlled
run. Capture integrity is represented by SHA256 to help correlate files; it
does not authenticate the person or process that recorded them. Do not upload
private game footage to a public GitHub issue/PR or CI. Only synthetic images
are included in this branch's tests and proof artifacts.

## Offline test and synthetic proof

```sh
python -m unittest discover -s scripts/visual_qa/tests -p 'test_*.py' -v
python scripts/visual_qa/demo.py
```

The GitHub Actions workflow
`.github/workflows/lab-visual-qa-tests.yml` performs the same checks
on a runner and uploads **synthetic-only** PNGs and JSON. It uses a read-only
checkout token, no repository secrets and no user Mac. Tests include RGB
changes, excluded areas, resolution mismatches, black screens, freeze/flicker,
video decoding and controller boundary behavior.

## V1 limitations and next safeguards

- No capture agent, no authenticated capture-to-run receipt binding, no
  scene landmark registration or optical flow, no OCR, and no model-based
  semantic inspection. These require separate reviewed research.
- Video brightness/freeze heuristics require movement in the reference and
  may report false positives for scene transitions. A high score alone
  cannot validate user interaction, frame pacing, sound or gameplay.
- The optional research-controller integration **does not** dispatch a new
  candidate, run a game, merge a PR or bypass the existing human gates.
- Keep captures and diagnostics in the isolated test results location, never
  in a live game installation or public Git repository.

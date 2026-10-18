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
  frame sampling rate (default 2 samples/second, up to 24 samples, spread across the entire clip).
- Targeted heuristics for black screens, likely frozen presentation (candidate
  static while reference moves), unusual luminance flicker, geometry mismatches
  and unequal sample counts.
- A 0–100 **agreement** score and a `pass`, `review`, `regression`, or
  `inconclusive` classification. This is not objective image beauty, a claim
  of verified visible FPS, or a guarantee of correct gameplay.

The comparison is pixel-spatial, not semantic. Animations, camera differences,
rendering settings, display scaling, compression, frame timing offsets and
gamma changes can cause false positives. Capture the *same scene, scale, aspect
ratio, time window and settings* for both arms. Videos longer than the frame budget are sampled evenly through their full duration. The video sample index is
aligned by approximate timestamp from each file's start; it is not motion-synchronized.
Clips with more than 2% duration mismatch fail closed as inconclusive.
Source captures larger than 2.5 million pixels per frame are refused to bound memory.
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
instead of overwritten. The tool rejects output paths using symlinks and
output paths inside a folder containing the original `LegoRR.exe` game.
Video decodes into disposable temporary storage.

Exit codes: 0 = successful analysis (when `--fail-on-regression` is absent,
regressions are reported in JSON but do not fail the command), 3 = non-pass
with `--fail-on-regression`, 2 = failed/incomplete processing. See
`out/report.json` and `out/diff-*.png` (red indicates different pixels).

## Bound capture-to-benchmark handoff (TEST results only)

Standalone `qa.py` diagnostics are **not** enough to alter controller research decisions.
The controller now requires captures bound to an existing verified baseline/candidate
benchmark pair, with hashes of the exact media and independently verified run summaries.
Media belong in each matching private `runs/<run_id>/visual/` directory, never in a game folder.

Register hashes only after the TEST run finishes and the captures already exist:

```sh
python scripts/visual_qa/bound_pair.py register \
  --experiment /private/experiments/graphics_test_001.json \
  --runs-dir /private/benchmark-runs \
  --pair-index 0 --baseline-file visual/menu.png \
  --candidate-file visual/menu.png \
  --out /private/experiments/graphics_test_001-captures.json
```

Analyze those already-registered captures without running the game:

```sh
python scripts/visual_qa/bound_pair.py analyze \
  --experiment /private/experiments/graphics_test_001.json \
  --runs-dir /private/benchmark-runs \
  --captures /private/experiments/graphics_test_001-captures.json \
  --out /private/qa-results/graphics_test_001
```

Then route evidence into the existing research controller:

```sh
python scripts/agent/experiment_controller.py \
  --manifest /private/experiments/graphics_test_001.json \
  --runs-dir /private/benchmark-runs \
  --visual-captures /private/experiments/graphics_test_001-captures.json \
  --visual-report /private/qa-results/graphics_test_001/report.json \
  --ledger /private/experiments/controller-ledger.json
```

The controller **rechecks lifecycle receipts, experiment pairing, summary hashes,
capture hashes and the full visual score independently from pixels/frames**.
A missing binding, forged classification or modified file fails closed. The ledger
is not written unless `--commit` is supplied. No code, DLL or game is executed.

This is **file/run consistency**, NOT authenticated capture origin: the tools
cannot prove the images were actually taken from the TEST game at run time.
The report records `capture_origin_authenticated=false`. A separate reviewed
TEST-window-only recorder would be required for authenticated origin. Do not
upload private original game assets or screen recordings into public CI.
Research policy mapping:

| Visual QA | Policy effect |
|---|---|
| regression | `isolate_regression`: diagnose blocking visual differences |
| inconclusive | `improve_instrumentation`: correct captures and alignment |
| review, performance candidate for review | `hold_for_review`: human check required |
| review, other performance result | preserve original performance policy |
| pass | preserve original performance policy; does **not** approve deployment |

The controller validates genuine run receipt files and recomputes captured media
scores, but this still does not authenticate who captured each screenshot. Do not upload
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

- No capture agent or authenticated capture origin, no
  scene landmark registration or optical flow, no OCR, and no model-based
  semantic inspection. These require separate reviewed research.
- Video brightness/freeze heuristics require movement in the reference and
  may report false positives for scene transitions. A high score alone
  cannot validate user interaction, frame pacing, sound or gameplay.
- The optional research-controller integration **does not** dispatch a new
  candidate, run a game, merge a PR or bypass the existing human gates.
- Keep captures and diagnostics in the isolated test results location, never
  in a live game installation or public Git repository.

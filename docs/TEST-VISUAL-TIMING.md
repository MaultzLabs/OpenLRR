# OpenLRR: TEST-only visual time-correlation gate

**Status: development only.** Code is on `lab-visual-temporal-provenance-v1`,
not merged into the working game. Linux CI exercises synthetic benchmark
receipts and mocked macOS screenshots. No real Mac, Wine window, or personal
game installation has been accessed.

## Purpose and limits

The Visual QA engine already verifies baseline/candidate run IDs, source media
SHA256, completion receipts and recomputed pixel/video scores. This phase adds
an **optional stricter temporal gate**: marker timestamps for TEST runner
start/clean exit and a screenshot interval from the same host boot. Both
monotonic and UTC clock deltas must agree, with at most two seconds drift.

These markers detect mismatched, late, reboot-crossing, modified and
out-of-window captures. They are UNSIGNED local evidence, **not** proof
the screenshot originated from OpenLRR. A compromised host or forged
local files can fabricate timestamps. `capture_origin_authenticated=false`
and all automatic installation/merge/deployment permissions remain false.

## Explicit opt-in sequence (DO NOT RUN until supervised TEST acceptance review)

1. Review code and update only the separate isolated `OpenLRR Menu Test.app`
   benchmark scripts. The existing WORKING game and wrapper must not be used.
2. Ensure the trusted `visual_timeline.py` resides beside
   `run-autobenchmark.sh`. The TEST-only supervisor does not timestamp runs
   unless `--record-visual-timing` is explicitly selected.
3. On the dedicated TEST installation, after reviewing the DLL SHA and
   normal `--approved-sha` supervisor preflight, a supervised TEST plan
   could be explicitly invoked with `--run --record-visual-timing`.
   That merely creates `run-timing.start.json` and `run-timing.end.json`
   in each *already-created TEST benchmark run directory*. It does not
   authorize capture, install any candidate or touch the working game.
4. While a timed TEST benchmark is actually running, the operator may use
   `capture-test-window.py --list-eligible` and the explicit window ID
   preflight. Recording itself still needs the separate operator flags
   `--capture --confirm-test-only --record-timing` and Mac Screen Recording
   permission. Recording is NEVER initiated automatically by this change.
   The image and `visual/menu.capture.json` are written into that TEST
   run's `visual/` folder. No desktop/fullscreen fallback or upload occurs.
5. After BOTH baseline and candidate TEST runs are completely closed,
   offline visual QA can require full temporal consistency:

```sh
python scripts/visual_qa/pipeline.py \
  --experiment /private/experiments/paired_test.json \
  --runs-dir /private/benchmark-runs \
  --out /private/qa-results/new-visual-proof \
  --require-timing
```

The optional lower-level tools `bound_pair.py register`,
`bound_pair.py analyze`, and `experiment_controller.py` also accept
`--require-timing`. If either arm is missing any of its three
timing files, is out of the correct benchmark window or has altered
content, the strict mode fails closed. Partial timing evidence is rejected
even in legacy mode; it never silently downgrades one timed arm.

## What is checked

- Exact experiment ID, pair index, baseline/candidate run identifiers and
  SHA256 of each screenshot and benchmark summary.
- DLL SHA and graphics mode match the independent completed TEST run receipt.
- Immutable start marker, matching clean-exit end marker and window-only
  capture receipt, all in the expected TEST-run directory.
- Capture monotonic interval is strictly between start and clean exit.
- Same boot identity; reject wall-clock steps above two seconds.
- Original window-ID, owning PID, approved test DLL and fail-closed flags
  are present in the capture receipt. These are claims recorded locally;
  real macOS/Wine process matching remains untested.
- The controller independently recomputes image scores before accepting
  any visual research-policy finding. It never authorizes binary execution.

## Known constraints

- On an actual Mac, a `screencapture -l` Wine window may be a different
  owning process than expected. Refusal is the safe result; never disable
  owner checks or fall back to full-desktop capture to make it pass.
- Manual capture while a test is active is required. Existing closed-run
  footage without timing receipts cannot be retroactively attested.
- `--record-visual-timing` is not an instruction to schedule a test or
  collect images: it must remain user-authorized on the separate TEST app.
- The new timing markers are not uploaded to public GitHub; only synthetic
  test fixtures belong in public CI. Do not publish private game assets.
- Hard limits: TEST run at most 1200 seconds, screenshot capture at most
  60 seconds, reasonable file sizes, no symlink traversal and no overwrites.

## CI evidence

- `lab-visual-qa-tests.yml` tests strict temporal gates using synthetic
  receipts and scores, plus existing visual and controller checks.
- `lab-test-capture-preflight.yml` exercises mocked Quartz/window capture,
  immutable timing marker tests and `bash -n` syntax on the TEST runner.
- No GitHub workflow invokes a real game, screen recorder, model,
  OpenAI API, candidate executor or user Mac.

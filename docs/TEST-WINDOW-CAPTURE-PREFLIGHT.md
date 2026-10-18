# OpenLRR TEST window capture — preliminary, opt-in macOS adapter

This is a **draft, unverified-on-Mac** component. Its safety unit tests are run
only against fake Quartz window records and fake screenshot commands on Linux.
Do not install/run it on a personal Mac or use a working Rock Raiders install
without independent code review and an explicit TEST-app-only acceptance test.

## What it does

- Does NOT launch, install, pause, update, merge, patch or stop a game.
- Refuses non-macOS hosts, invalid/unknown window IDs, desktop-layer windows,
  and windows whose owner does not have the exact dedicated TEST game files open.
- Checks the dedicated `OpenLRR Menu Test.app` and the approved benchmark DLL
  against a 64-character SHA256 before capturing.
- Requires a currently existing benchmark run folder, an explicit window ID,
  `--capture` and `--confirm-test-only` before invoking **window-only**
  macOS `screencapture -l WINDOW_ID`. There is no fullscreen fallback.
- Refuses existing screenshot paths and keeps outputs exclusively in
  `~/Downloads/OpenLRR Benchmark Runs/<run>/visual/menu.png`.
- Honors lab STOP and PAUSE and refuses changed window ownership.
- Does not upload images. Its receipt explicitly says
  `capture_origin_authenticated=false`; window/process checks are helpful
  local guards, not cryptographic provenance or proof of frame alignment.

## Hypothetical commands AFTER code review on the dedicated TEST Mac

Requires Screen Recording permission for the Python process and PyObjC Quartz
installed in a separate Python environment. A failure to match a Wine window
is a **safe refusal**, not permission to loosen matching or capture the desktop.

First list candidate TEST-backed window IDs with no recording:

```sh
python scripts/macos/capture-test-window.py \
  --approved-sha REVIEWED_64_CHARACTER_SHA256 \
  --run-id autobenchmark-YYYY-MM-DD_HH-MM-SS --list-eligible
```

Select a specific returned window and run dry preflight (still no capture):

```sh
python scripts/macos/capture-test-window.py \
  --approved-sha REVIEWED_64_CHARACTER_SHA256 \
  --run-id autobenchmark-YYYY-MM-DD_HH-MM-SS --window-id 301
```

Only if the dry preflight matches the dedicated TEST window, an explicitly
approved operator may use `--capture --confirm-test-only`. **This is not
scheduled or activated automatically by the AI lab.**

After a verified baseline/candidate pair has capture files and completed
run receipts, the offline `scripts/visual_qa/pipeline.py` can process them
with SHA256 checks and independent visual-score recomputation.

## Limitations and unresolved verification

- Not validated with actual Sikarugir/Wine Quartz window metadata or
  `screencapture` behavior in the user's installed macOS version.
- Not wired into supervisor timing. A screenshot is not proof of capture
  at the same menu transition timestamp as the benchmark summary.
- No continuous video capture, desktop capture, semantic gameplay analysis
  or automatic candidate execution.
- Future integration must confirm selection, privacy boundaries and
  reliable association of capture timestamps to trusted TEST run periods.

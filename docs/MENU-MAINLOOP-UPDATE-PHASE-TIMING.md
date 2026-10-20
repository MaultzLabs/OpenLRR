# Passive main-loop vs Direct3DRM update instrumentation

## Reason for this test

A Mac TEST run on October 19 (21:50–21:53 local) found the baseline DirectDraw
front-surface blit has repeated approximately 1.25-second stalls. The
experimental CPU DIB branch had a black screen and slower timing; the costly
operation moved to the DirectDraw **backbuffer Lock** (~1.27 seconds), while
StretchDIBits copy time was less than 0.2 ms.

This branch is based on the **original working visible renderer**, **not** the
failed DIB branch. No presentation or draw flags change.

## New measurements

- `game_mainloop`: duration of `currState.MainLoop(_mainDeltaTime)`, includes
  any work it invokes.
- `d3drm_device_update`: duration of the actual Direct3DRM device `Update()`.
- Existing `window_present_blt`, `frame_flip`, `movie_update`, and CPU-vs-wall
  measurements remain.

This lets us separate game update from Direct3DRM submission from front
presentation in the same TEST-only 60-second trace. It does NOT expose the
underlying GPU driver, visible FPS, audio, or click responsiveness.

The established CSV remains eight columns and every data group ends with
`window_blt_slow_low_cpu` **but** this branch appends two metrics after that
operation. Consumers that rely on a fixed last-operation flush marker must
be updated for this new artifact. The older approved baseline DLL is
unchanged.

## One-shot plan

A single `baseline` mode is newly allowed by
`scripts/macos/diagnostic-one-shot.sh`. Existing STOP, PAUSE, SHA pin,
Wine app handle checks, source-commit pin, original TEST DLL restore and
private upload remain. The caller must pin a CI-proven SHA-256 and a
successful Win32 workflow run built from the matching source commit.

No Mac test has been conducted with this new DLL. Screenshot/video QA is
still a separate requirement.

## October 19 Mac run: analyzer rejection corrected

Run `autobenchmark-2026-10-19_22-51-41` reached the benchmark
analyzer, which rejected the CSV with `No completed game main-loop timing
samples`. The analyzer had assumed that all menu frames execute
`currState.MainLoop()`. OpenLRR also has a nested menu path:
`Main_LoopUpdate2()`, which can call `Graphics_Finalise3D()` and
`DirectDraw_Flip()` without entering `currState.MainLoop()`.

The analysis-only fix accepts a fully instrumented but zero-call
`game_mainloop` metric, reports `state_mainloop_not_observed`, and
preserves real measured `d3drm_device_update` and presentation counts.
It does not infer missing timing values or declare the render path proven
from this alone.

The existing run's `menuperf.csv` and `lifecycle.verified` should be
inspected **locally** before considering any repeat. The supervisor retained
its safety lock because the analyzer exited nonzero; do not remove that lock
until the TEST game has independently exited and the previous TEST DLL is
verified restored. The original working installation is not in scope.

This revision changes **only reporting code, tests, and documentation**.
The previously built Windows DLL and instrumentation are unchanged, and no
Mac run is initiated.

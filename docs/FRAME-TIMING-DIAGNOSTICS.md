# OpenLRR frame-timing diagnostics (isolated test build)

## Objective

Determine whether slow 1999 main-menu frame pacing comes from synchronous DirectDraw presentation or time **between** calls into `DirectDraw_Flip`. This is a diagnostic experiment, not a speed optimization. Existing DirectDraw/GDI rendering choices and flags remain unchanged.

## Added read-only telemetry

The `menuperf.enable` marker must be present in the isolated TEST game's working directory. Existing `menuperf.csv` format is preserved; rows are added for new operation names:

| CSV operation | Meaning |
| --- | --- |
| `frame_start_gap` | Elapsed time from prior `DirectDraw_Flip` entry to current entry. This is flip call cadence, not visible FPS. |
| `frame_outside_flip` | Time from prior `DirectDraw_Flip` return to next entry; includes game logic, waits, scheduling and possible timing overhead. |
| `window_blt_over_100ms`, `window_blt_over_1000ms` | Counts **individual windowed DirectDraw blits**, not sampling windows, that exceeded 100/1000 ms. |
| `frame_outside_over_100ms`, `frame_outside_over_1000ms` | Counts individual periods outside `DirectDraw_Flip` above 100/1000 ms. |

Timing measurements accumulate in process memory and flush with the existing once-per-second telemetry. No screen scraping, screenshots, OS privilege changes, or new dependencies.

Both `frame_outside_flip` and `window_present_blt` are only *sampled CPU-side call durations*. They do not identify root cause inside Wine/driver or guarantee presented frames reached the display. A large `frame_start_gap` is not necessarily entirely CPU work: it includes time spent in the previous `DirectDraw_Flip` as well.

## Evidence for the research agent

The analyzer writes additional numerical fields into `summary.json`. It accepts older CSV files without these metrics, reporting absent diagnostic values as `null`. Partial new diagnostic records are rejected. The read-only AI analyst accepts the new fields but cannot execute code or the game.

An appropriate first experiment is one 60–90 second *baseline-only* run using the isolated `OpenLRR Menu Test.app` and an SHA256-pinned Windows x86 DLL from a successful CI build. The runner already handles graceful shutdown and verifies lifecycle and uploaded results. Keep the working game untouched.

## Interpretation

- High mean DirectDraw blit duration and high individual blit-stall counts, with low outside-Flip periods: focus subsequent research on synchronous DirectDraw presentation and Wine-side rendering.
- High outside-Flip time or stalls, with low DirectDraw blit duration: profile game-side work or scheduler/sleep behavior before changing the present path.
- Both high: investigate both, perhaps with a finer per-frame event trace.
- Neither high but apparently choppy visuals: screen/video capture and display latency analysis would be needed; these timers cannot certify smoothness.

## Safety

The diagnostic branch is not production. A green build only establishes compilation and offline test success. Running an unreviewed binary on the user's Mac is blocked. The Mac supervisor's STOP, PAUSE, process exit receipts, limited runtime and SHA256 checks remain required. No automated promotion or code modification is authorized by a benchmark.


# Rock Raiders Gameplay Capture Lab — macOS


## Automatic code/input indexing **while recording**

The live recorder now finalizes one H.264 MP4 every **90 seconds** by
default. When a segment is finalized, it immediately creates a private
matching `part-0001.evidence.json` file **while the next segment is being
recorded**. The evidence file records the clip's approximate timeline
offset, supported mouse/key events, available Wine API observations,
and source-code entry-point references for OpenLRR commands and NERPs
functions. The program never uploads files or calls a paid API.

Example folder contents *before* OpenLRR is closed:

~~~text
clips/
  part-0001.mp4
  part-0001.evidence.json
  part-0002.mp4
  part-0002.evidence.json
  part-0003.mp4        (still recording; NOT upload ready yet)
~~~

Evidence is produced only after the previous MP4 is finalized. Each
file is marked `upload_ready_size_only` if under 180 MiB. This verifies
the local file size, not that a ChatGPT client supports video upload
or that a model has already inspected frames. Raw Wine logs are never
included in sidecars. If no Wine/NERPs instrumentation was enabled,
those records are correctly marked missing. Full event history always
remains available in `timeline.jsonl`. The per-clip preview includes up
to 20,000 sanitized events, with an overflow count. The index is a
source-reference guide, not executable recovery of the Windows code.

After you quit, the existing full session index is also generated.
The older 557-MB file can be split **without changing the source** using
`recover-existing.py`, which now creates matching evidence files for
the recovered clips too. This is offline retroactive indexing; it cannot
reconstruct Wine or NERPs telemetry that was not captured.

## Interruption recovery and first-tutorial capture (October 21)

The earlier single-file recorder successfully wrote **557 MB / ~10m30s**
of capture data, but the owner's in-game Quit caused ScreenCaptureKit to
report a stream failure before it finalized the MP4. The source remains
on the Mac under \`Movies/OpenLRR Gameplay Captures\`. A large MP4 can lack
its final movie index; file size alone **does not prove it is playable**.

Try to open that file in QuickTime. If QuickTime plays it, the safe recovery
script can split it into small MP4 files **without modifying the original**:

~~~bash
python3 native/macos-menu/tools/gameplay-capture/recover-existing.py \
"$HOME/Movies/OpenLRR Gameplay Captures/rock-raiders-20261021-231925-00/game-window-master.mp4"
~~~

If the MP4 is missing its index and Apple's built-in AVFoundation cannot
read it, the recovery tool reports failure without deleting or changing
the original. This tool is not a low-level repair for a missing \`moov\`
atom. Keep the file for possible forensic reconstruction.

For the *next* full recording use:

~~~bash
python3 native/macos-menu/tools/gameplay-capture/first-level-video.py --session full
~~~

The default \`--segment-seconds 90\` produces *separately finalized clips
during recording*. The last seconds can still fail to finalize when Wine
closes its window, but earlier successful segments are retained and
packaged normally. **No footage from the prior interrupted file is
invented or silently discarded.** Clipping and NERPs telemetry are
independent: plain Wine capture does not give internal NERPs calls without
the explicitly isolated instrumented TEST build.


## Preferred: continuous video + synchronized game controls

**This is now a real 30-FPS ScreenCaptureKit H.264 video recorder, NOT periodic screenshots.**
It records *only the identified original Rock Raiders game window* for the full
session. Mouse buttons, wheel events, selected gameplay keycodes (no typed
characters) and optional existing Wine/NERPs traces go into the same timeline.

Run the one-command `first-level-video.py` launcher from the checked-out video
branch. It locates/opens the real Wine/OpenLRR app, waits for a single verified
game window, then records until that window closes. **This recovery branch
finalizes short H.264 segments every 90 seconds while gameplay is active.**
This protects earlier clips if the Wine window closes before the final clip
can be finalized (as observed in a 557 MB interrupted October 21 capture).
The finished clips and a separate synchronized timeline review ZIP remain
private on your Mac. Each individual segment is checked for size before
offering it for upload. Finder opens the clip
folder. No screenshots, desktop captures, microphone recording, or automatic
uploads. **Game audio is requested by default** with ScreenCaptureKit and the
recorded MP4 is checked for an audio track. macOS filters audio at the owning
application level, not by individual window: other sounds from the *same Wine
application* may be present; audio produced by other Wine processes may be
missing. `manifest.json` reports `audio_track_present` rather than claiming
sound was captured if no track exists. Screen Recording and optionally Input
Monitoring permission are needed.

~~~bash
python3 native/macos-menu/tools/gameplay-capture/first-level-video.py
~~~

You can attach the small MP4 clips and the separate timeline ZIP to ChatGPT.
The timestamps in the timeline are host observations; the video clip
`start_s` offsets are relative to the video, not perfect frame-accurate
game timestamps. Wine API summaries require an *already-running* opt-in Wine
debug log, and internal NERPs functions require separately instrumented game
code. Do not mistake missing NERPs calls for no script execution.

The older `first-level.py` and `capture.py record` commands
**still run the deprecated sampled-PNG experiment**. Use
`first-level-video.py` for the actual video-based workflow.


**Strict privacy boundary: the original LEGO Rock Raiders game WINDOW only.**

The user requested that screen captures never include the desktop or another
application and that **all recording stops automatically when that game window
is closed**. These are mandatory operating rules, not optional features.

## One-paste first-level capture

The native one-shot launcher `first-level.py` locates and opens the *normal*
Wine `OpenLRR.app` where available (never `OpenLRR Menu Test.app`), waits for
the original game window, and records it while you play the first level.
When you quit that original game window, it automatically stops, saves a
private review ZIP containing only game-window frames and safe synchronized
events, and reveals that ZIP in Finder. It never uploads files on its own.

From an existing checkout of this development branch:

```bash
python3 native/macos-menu/tools/gameplay-capture/first-level.py
```

If no recognizable game app exists in Applications, open your normal Wine
game app manually while the launcher waits. Ambiguous game windows are
refused rather than allowing another app or desktop to be recorded.

The basic session captures sampled frames and supported game controls.
Wine API summaries require an *existing* debug log provided with `--wine-log`.
Original 1999 NERPs function calls require a separately instrumented DLL;
this recorder does not infer internal calls from screenshots or inject code.
The ZIP never includes raw Wine logs, whole-desktop screenshots, or other
apps. Review the ZIP before sharing in ChatGPT or a private research repo.
macOS might request Screen Recording and Input Monitoring permissions.

## Run the first capture

Launch the original Windows Rock Raiders/OpenLRR game in your existing Wine
wrapper normally. Once its game window is visible, on your Mac run:

```sh
cd ~/Downloads/OpenLRR-Native-Live
git pull --ff-only
python3 native/macos-menu/tools/gameplay-capture/capture.py list
python3 native/macos-menu/tools/gameplay-capture/capture.py record --fps 4
```

The capture script compiles the tiny Swift window probe using **Apple's Xcode
Command Line Tools**, finds exactly one identifiable game window, then saves
a private session under `~/Movies/OpenLRR Gameplay Captures/`.

If the window list includes several Rock Raiders windows, use
`record --window-id <ID>` using the **specific ID returned by list**.
It refuses ambiguous windows; it never guesses another application or starts
the game on its own.

Grant macOS **Screen & System Audio Recording** access to Terminal when
requested for window screenshots. The optional input listener may separately
require **Input Monitoring** access for Terminal or the Swift helper. A
missing input permission does **not** authorize recording keystrokes outside
the game; screenshots can continue with input capture unavailable.

### Precisely what gets captured

- PNG frame samples at the requested cadence (1–10 screenshots per second).
  Every screenshot is taken through `screencapture -l WINDOW_ID`, never with
  a full-display or desktop selection switch.
- Relative cursor clicks, drags, movement and scroll-wheel deltas from that
  **same window** while its owner application is in front.
- Only recognized **game-control keycodes** (W/A/S/D, arrows, R, space,
  return, escape, +/-); never text typed, chat, clipboard or other apps.
- Monotonic and UTC timestamps in `timeline.jsonl`, suitable for correlating
  commands with individual game frames.

The recorder validates window ID **and owner PID** both before and after each
screenshot. If the window vanishes, capture stops, including the input helper,
and the last PNG is discarded if the identity disappeared mid-capture. It
never switches to another window or starts recording the desktop. A minimized
window pauses screenshot capture; close the game to stop the whole session.
Ctrl-C also stops manually. A separate four-hour safety ceiling exists even
if the game remains running; default ceiling is two hours.

### Wine and NERPs data

**Optional / passive:** supply `--wine-log /existing/active/wine-trace.log`
to record new Wine log bytes *only while the game window is alive*. For example,
Wine's `WINEDEBUG=+timestamp,+ddraw,+d3drm,+relay` can produce graphics/API
logs, but relay tracing is extremely verbose and can slow the game. Do not
enable broad relay tracing during normal gameplay unless specifically testing
that overhead. The capture tool does not change the Wine configuration or
inject any code; Wine logging must already be enabled by the runner.

```sh
python3 native/macos-menu/tools/gameplay-capture/capture.py record --fps 4 \
  --wine-log "/path/to/an/existing/wine-trace.log"
```

`--nerps-log /existing/structured/nerps-events.jsonl` also supports an
**instrumented** NERPs event source, provided a custom Windows OpenLRR DLL
has been built to emit it. Vanilla LegoRR.exe does **not** emit detailed NERPs
function-call traces. This tool only follows an existing source, filters
function name/numeric arguments and correlates them with capture timestamps;
it never claims to infer invisible internal game calls from screenshots.

### Recording lifecycle and privacy

- All capture products are private (`0700` directories, `0600` files).
- Raw Wine traces remain `wine_raw.local.log` in the local session, never
  included in the sanitized research package. Wine relay often includes
  machine paths and other sensitive data.
- **No automatic GitHub upload.** Export is separately reviewed and initiated
  manually:

```sh
python3 native/macos-menu/tools/gameplay-capture/capture.py package \
  "/path/to/rock-raiders-SESSION" "/path/to/review.zip" --include-frames
```

This package contains a manifest, filtered event timeline and optionally the
**game-window-only** frames. Inspect its contents before uploading to a
**private** GitHub research repository. Never publish raw screen recordings
or Wine traces into the public source repository. The package command makes
no network requests.

For a local MP4 made from **only those window frames** (optional, requires
FFmpeg):

```sh
ffmpeg -framerate 4 -i frames/frame-%06d.png -c:v libx264 \
  -pix_fmt yuv420p gameplay-window-only.mp4
```

This produces a sampled-time video, not a continuous 60 FPS recording. The
original Windows game's high-frequency visual or audio activity cannot be
inferred from the PNG samples alone. A later ScreenCaptureKit-only-window
streaming backend may capture native video and audio if testing needs it.

## What this lab is / is not

This is **phase 1** of a synchronized research recorder that can collect
visible gameplay and passive diagnostic streams without touching the original
game. It can coexist with the older `lab-menu-phase-forensics-v1` CPU/menu
profiling tools; it does not launch the approved diagnostic worker or modify
that lab's test configuration.

It does **not** yet automatically instrument Windows NERPs execution,
reconstruct every game command, reproduce mouse input or upload any capture.
Internal NERPs calls require a separate instrumented DLL or debugger; using
Wine alone cannot reveal arbitrary intra-executable function calls.

## CI and safety regression coverage

Linux unit tests use synthetic windows and fake screenshot executors. They
assert that `screencapture -l` is always present; desktop capture switches
never appear; closure stops recording; racing closure discards images; and
packaging excludes private Wine logs. Native macOS CI also compiles the Swift
window probe but cannot confirm Screen Recording permissions or actual Wine
window rendering without running on the user's Mac.

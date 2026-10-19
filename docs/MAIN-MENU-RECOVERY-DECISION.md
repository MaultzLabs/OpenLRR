# OpenLRR Main Menu: Engineering Decision and Experimental Stop Rules

**Status:** Track A is primary. Track B is a small feasibility audit only.
**Target:** original, functional main menu with sound, keyboard/mouse
interaction, faithful imagery and >=60 independently observed visible updates
per second on the owner's Apple Silicon Mac. No existing run proves success.

This document deliberately **does not authorize** installing a DLL, merging
any diagnostic branch, deploying Wine changes, opening a GitHub review issue
or launching a native rewrite.

## 1. Verified baseline and limits

Two real, safely completed and privately uploaded TEST runs on 2026-10-18:

| | autobenchmark-2026-10-18_22-47-08 | autobenchmark-2026-10-18_22-48-35 |
|---|---:|---:|
| DLL SHA256 | 11793230…b4ff | 11793230…b4ff |
| Same graphics flags | 0/0/0 | 0/0/0 |
| Duration (s) | 63.538 | 62.983 |
| Logical flips/s | 3.5884 | 4.0805 |
| Window Blt mean (ms) | 219.1327 | 194.3747 |
| Time inside presentation (s) | 50.1814 | 50.1487 |
| Blts >1s | 31 | 31 |
| Time outside Flip mean (ms) | 47.9204 | 40.9328 |
| Slow Blts with CPU samples | 31 | 31 |
| Slow samples classified low CPU | 0 | 1 |

Presentation accounts for approximately 79% and 80% of the logged test
durations. That is the principal measured bottleneck. **Logical frame flips
are not display-present acknowledgements**. No verified visible-FPS trace,
input-response latency trace or audio-path trace yet accompanies these runs.

Crucial calibration warning: reported slow-calling-thread CPU average was
1267.0968ms in the first run, while its longest Blt wall sample was
1260.8062ms. A single thread's CPU time cannot physically exceed
the duration of its enclosing interval by this amount without clock or
accounting disagreement. The old diagnostic permitted +50% CPU
over wall duration; it is too permissive to support a confident CPU-bound
conclusion. The second run reported 1224.8387ms average slow CPU, also
close to its 1260.821ms longest Blt. Thus **active-CPU presentation is a
leading but unproven hypothesis**, not a proven bottleneck attribution.

Earlier flags-only probes found GDI slower in a limited trial and
nonblocking Blt inconclusive. Do not recommend those as verified fixes.

## 2. Cause hypotheses and discriminating observations

**H1 — expensive DirectDraw/Wine CPU presentation path** (leading):
A sampled TEST Wine game process has repeated stacks in DirectDraw
surface conversion, blit, pixel-format/geometry, clipping, or equivalent
Wine layers during verified long Blts. Proposed fix: narrowly adjust
conversion/presenter after identifying hot functions.

**H2 — scheduling, compositor or driver presentation waits:**
The per-Blt CPU probe's clock accounting is inaccurate; a native sample
shows little executing work or time in wait primitives, and visual-frame
delivery is blocked. Proposed fix: adjust Wine presentation backend,
surface/event scheduling or compositing, not game simulation.

**H3 — other menu work or timing pathology:**
External stack samples attribute load to decode/movie, shared engine work,
or a timer rather than DirectDraw, and Blt scope is misleading.
Proposed fix: instrument that actual work rather than rewriting the renderer.

The evidence does not distinguish these yet. Only H1 currently enjoys
support from *nominal* CPU probes, which require calibration.

## 3. Next experiment — ONE bounded diagnostic before patches

1. Work ONLY in `OpenLRR Menu Test.app`. Confirm process exit and TEST
   binary SHA before and after. Keep current exact DLL as control.
2. Use the already-developed, opt-in, **local-only** Mac sampling helper
   `wine-cpu-sample.py` as a bounded attachment while the existing
   supervised benchmark is running. Its supervisor integration lives in a
   separate experimental branch and requires review/testing before use.
3. In parallel, use calibrated in-game CPU/wall counters from the
   **isolated calibration branch**. New `window_blt_cpu_inconsistent`
   values flag CPU deltas more than 4ms above enclosing wall time.
   Such samples count as unavailable, not proof of a busy thread.
4. Compare one *baseline vs diagnostic-instrumented identical-behavior* pair
   to quantify profiler overhead. Re-use **identical** window geometry,
   screen scale, audio state, app assets and capture conditions.
5. Do not upload raw macOS sample traces (they may contain private paths).
   Inspect named hot functions locally. A sanitized summary may be used
   only as a hypothesis, not a performance pass.
6. Advance to a source-level candidate **only if** an identifiable hot path
   is reproducible. Inconclusive profile: stop and request precise missing
   measurement. No blind parameter sweeps.

Do not automatically run unreviewed DLLs. The sample helper itself cannot
prove macOS sandbox containment; the Wine link audit is NOT a VM.

## 4. Main-menu acceptance gates

Functional gate **before** FPS optimization:
- Authentic menu assets rendered and screen transitions matched to reference.
- Mouse movement, hover, click and keyboard navigation correctly reach menu
  options; no focus capture, black screen, hang or crashes.
- Main menu music and selectable SFX audible and stable; no permanently
  missing sound or audible distortions.
- Complete supervised TEST game exit with exact lifecycle receipt; no stale
  Wine processes.

Performance gate:
- Binary provenance, SHA256, exact flags and TEST-only app version recorded.
- >=5 matched A/B pairs when making a substantive improvement claim;
  no actual improvement accepted from synthetic/mock cloud runs.
- Logical frame timing and time spent in the precise presentation path.
- Independent visual capture with frame timestamps, >=60 Hz acquisition and
  an animated or externally driven stimulus; do **not** count duplicate
  screenshots or unchanged pixels as unique displayed frames.
- Separate timing for actual observed updates plus input-event response
  latency. Record display refresh capability. At a 60Hz panel, 60 distinct
  updates/sec is the maximum; avoid claiming >60 visible without a faster panel.
- Visual regression/image fidelity check plus audio regression check.
- No regression in latency, crashes, audio or menu behavior.
- Any 60+ visible-FPS statement must link to real captured evidence.

## 5. Native feasibility audit (research only, no port authorized)

Verified directly from the OpenLRR source and its own README:
- OpenLRR is an *incremental reimplementation* and deliberately relies on
  the original LEGO Rock Raiders executable and assets.
- `src/openlrr-makeexe/README.md` describes patching the legacy PE's
  `WinMain` entrypoint to call `openlrr.dll!StartOpenLRR`.
- `src/openlrr/interop.cpp` contains extensive hardcoded 0x004... code
  hook references. `src/openlrr/game/front/FrontEnd.cpp` has multiple
  menu-global references into original EXE memory, e.g. save-menu and
  frontend globals. This is *not* merely a portable SDL3 frontend.
- Main and DirectDraw reference original EXE global memory and legacy
  DirectDraw/Direct3D Retained Mode APIs.
- Audio still depends on DirectSound / WinMM/MCI; input on DirectInput and
  Win32 cursor APIs. Menu code also uses AVI/movie, images/fonts and the
  original asset/config formats.
- The upstream engine README states its Gods98-derived code may **not
  be shareable under the same project-wide license as game code**. No
  compatible legal basis for a native release has yet been established.

A native menu would need replacement asset/config resolution, owning all
formerly EXE-backed menu state, timer/input/events, authentic menu state
machine, sprite/movie playback, fonts/text, sound effects/music and audio
synchronization. Future game levels additionally require map/render/world
logic. This is substantial new work.

For a narrow *eventual* feasibility PoC:
- SDL3 window, event pump and Metal-backed 2D renderer are plausible for
  a **real menu slice**, with platform-native audio as needed.
- The PoC must load an **authentic original asset** from an authorized
  user's game installation, implement a real menu state transition and
  at least one working input/button action plus representative audio.
- Confirm actual presented frames from the physical Mac and reference
  visuals. A colored rectangle, static screenshot, or artificial 60fps
  rectangle animation is **not** an authentic menu PoC.
- Do not start a full port until separately justified and approved.

Technical feasibility: plausible. Near-term efficiency relative to targeted
Wine diagnosis: currently poor. Switch evidence would require repeated
Track A failures localizing unfixable Wine compatibility constraints AND a
working asset-driven native menu proof that preserves behavior.

## 6. Portfolio decision

**~90% Track A, ~10% Track B audit only.** Do not expand the game composer or
map generator until the menu is functional and a verified FPS trajectory
exists. Preserve all existing branches/artifacts; do not merge into the
working game or trigger review issues.

Work only on the next discriminating test, evaluate its evidence and either:
(A) propose one narrowly scoped DirectDraw/Wine fix for controlled A/B; or
(B) stop and identify the precise missing evidence. Never confuse a more
elaborate autonomous-lab infrastructure milestone with gameplay progress.

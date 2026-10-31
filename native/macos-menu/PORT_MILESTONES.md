# Native port acceptance ledger

Updated 2026-10-28. The earlier 80% completion estimate is withdrawn: there was no complete denominator or full-game acceptance run. Do not assign a completion percentage from source volume, passing parser tests, or a successful compile.

| Area | Evidence and status | Required acceptance |
| --- | --- | --- |
| Original menu | Native implementation exists | Original assets, transitions, input, exit and sustained visible frame timing on Mac |
| Terrain texture regression | PR #61 fixes Textures::Rock reference resolution; portable tests and ARM64 compile pass | Rock, Ice and Lava missions visibly use their correct textures |
| Menu/mission audio | PR #61 separates players and stops menu restart in missions; compile passes | Audible transitions with original audio; OGG conversion currently required |
| Movement and wall clearance | PR #61 exact destinations and swept footprint tests pass | Repeated in-level moves, wall/corner tests and mid-move retargeting on Mac |
| Raider models | Original AE/LWS/LWOB stand/walk integration in development | Original geometry, materials, hierarchy, pivots, heading and animation timing verified against retail |
| First-person | Isolated prototype: F toggles selected original OL Raider's tracked camera; held W/S and A/D (or arrows) use swept static-wall clearance, return with F/Esc. PR #65 candidate adds live swept collision with other OL Raiders to both first-person and clicked movement (provisional capsule radii). | Retail input mapping, head-frame placement, original speed/turn timing, real-asset in-level testing, original building/unit collision shapes |
| Excavation | Separate prototype PRs; not full retail behavior | Strength/timing, reveal, rubble, resources, sound and animation |
| Building/economy | Incomplete | Construction, power, ore/crystals, upgrades, dependencies |
| Vehicles and AI | Incomplete | Original models, boarding, navigation, tasks and collision |
| Mission scripts/objectives | Partial callback implementation | All mission and tutorial scripts plus completion/failure behavior |
| Saving/loading gameplay | Original save inspection exists; full native persistence incomplete | Round-trip a played mission without state loss |
| Full-game performance and fidelity | Not established | End-to-end campaign sessions and sustained Mac performance |

Next selected milestone: test the first-person tracked-camera/control prototype on a real original level and match the original Raider head camera frame, speed, and turn timing; then add dynamic object/building collision. Original model material mapping and walk animation remain separate unverified tasks.

Daily reporting must name commits, tests actually run, user-visible results, remaining failures and the next chosen task. A day without validated advancement must be reported as such; no automatic 5% credit or five-day completion promise.


## Model materials and terrain follow-up — PR #66

Implemented original LWOB TIMG/TSIZ/TCTR/TFLG bitmap projection and UView v2
per-corner coordinates, preserving texture seams. Original BMPs resolve from
the component directory and configured shared texture directory. Dry exposed
terrain uses floor material; wall sides retain rock/seam material. Floor UVs
are aligned to map tiles on odd-sized levels.

Added an RRU ZIP music importer: audio-only Track00–98 extraction, local M4A
conversion, no Windows DLL installation, no overwrite of existing tracks.
Four local FFmpeg integration tests pass, including corrupt-track rollback,
path confinement and duplicate rejection. Swift regression/ARM64 CI remains
the authority for build status. No original asset visual/audio validation yet.
The user approved the RRU terms, installed the converted soundtrack package, and the native build now bundles those locally installed tracks. Audible in-mission playback remains unverified.
Next: real-asset material review and first-person camera/control.


## Reuse of scheduled development — 2026-10-26

The six-run hourly native task has ended (disabled). The daily native task is
active. All commits from the hourly native branch through b5bf188 are ancestors
of the combined PR #66 build. Its WAD/CFG, NERPs and input work is retained.
PRs #63–65 provide first-person, mission messages and live Raider collision;
they are integrated through d91a164. The Wine benchmark and visual-lab branches
remain separate: their metrics are not native gameplay acceptance evidence.

Next integration reuses the session excavation state and regression fixtures
from PRs #58/#59 (748b454), adapting them to continuous clearance-aware movement,
live Raider collision, original bitmap caching, and first-person navigation.
Right-side Drill/Back controls issue actual excavation orders and feed the
original NERPs Dig/Back counters (0x40/0x41 and 0x3d/0x3e). Configured original
icon BMPs are used when available; native text controls are the fallback, and
full surround layout remains provisional. Hard rock is not hand-drillable.

Remaining: retail drill duration and animation, rubble/resource drops, hidden
cavern reveal, task assignment without a selected Raider, construction/spawning,
and local visual/gameplay checks. No new completion percentage is assigned.

## Original Raider first-person camera-null integration — 2026-10-28

Preserve the names of LWS AddNullObject frames, resolve the AE CameraNullName/
CameraNullFrames reference using the original Creature_GetCameraNull and
Container_FormatPartName conventions, and position the native first-person
camera at the live animated named LWS null, when available. The former fixed
0.68-unit eye offset remains a visibly provisional fallback for missing or
unsupported frames. Synthetic parser, AE-bound and SceneKit animation/scale
regressions cover the new path. Original camera orientation/CameraFlipDir,
real-asset visual placement, timing and first-person hands remain unverified;
this is not a retail gameplay acceptance claim.

## First-person camera during drilling — 2026-10-29

First-person camera positioning now updates after every original LWS activity
animation tick, **before** the Activity_Drill/direct-input guard. Previously
the drill animation played but the separate native camera remained frozen at
its last pre-drill frame because the frame loop returned early. Following the
original Creature_GetCameraNull path from PR #69, this fix tracks the active
named null during Stand, Route and Drill; it also refreshes position after a
successful player move. Mac synthetic testing exposed a second issue: the
original Raider hierarchy is hidden during first-person play, so SceneKit's
presentation transform can be stale. The live original LWS model transform
(worldPosition), which Clip.update changes each frame, is used instead. A missing or nonfinite camera null retains the explicit
provisional eye height rather than creating a replacement model/camera offset.

New portable pose-priority/invalid-transform tests and hosted SceneKit synthetic
animated-null tests cover this path. They do not prove the appearance or head
orientation of the original retail Raider, and the original CameraFlipDir,
FPPoly/hands, first-person drill sound and gameplay timing remain unverified.

Next: validate camera orientation, original FPPoly/hand assets and drill tool
animation against actual user-owned models, then restore further task/economy
behaviors under full first-tutorial script control.

## First-person positional damping — 2026-10-30

Original Camera_Update in src/openlrr/game/world/Camera.cpp applies a
4/elapsedAbs first-person positional weight, teleports when over 100 original
world units away, and ignores displacement at or below 0.01 world unit.
Native previously snapped to the current original ACT/LWS camera null every
frame. It now applies this source-grounded damping exactly once per unpaused
frame after animation and input, including when drilling or tutorial input
returns early. First entry and large displacement snap; thresholds compare
the SceneKit tile coordinates using original configured BlockSize. Portable
synthetic regressions cover weighting, invalid inputs, pauses, teleports and
jitter; hosted SceneKit tests cover animated hidden-Raider camera nulls.

The original 25-Hz elapsed-to-ticks mapping and visual movement still require
on-device/retail comparison. Camera-null orientation, CameraFlipDir,
first-person FPPoly hands/tool geometry and drill sound remain unverified.
This is compiled-prototype progress, not real-asset gameplay acceptance.

Next: implement source-grounded first-person camera direction/CameraFlipDir
and original FPPoly tool geometry using authorized local assets, without
fabricating substitute models.

## First-person horizontal direction damping — 2026-10-31

Source: `Camera_Update` in `src/openlrr/game/world/Camera.cpp`
normalizes and weights old and requested first-person direction by
`4 / elapsedAbs` (25-Hz game ticks), skips changes at dot >= 0.99999,
and snaps camera direction **and position** when the facing dot is negative.
The native tracked camera now applies that source behavior to its current
controller-derived X/Z heading, rather than snapping rotation every frame.
Wraparound at +/-180 degrees, turn reversal, zero/invalid frame times and
sudden-position snapping have portable Swift regressions. SceneKit
animated-null tests also verify eased yaw and reversal position snap.

This is directional damping of the existing provisional horizontal heading:
`LegoObject_FP_GetPositionAndHeading` is still a binary-address declaration
in OpenLRR, so original LWS camera-null forward/up vectors and AE
`CameraFlipDir` interpretation are **not** asserted as implemented.
Original models, on-device visuals, scripted turns and first-person
FPPoly/drilling geometry/audio remain unverified.

Next: read the authenticated LWS camera-frame transform and the retail
`CameraFlipDir` setting without inventing a model-space convention, and
compare camera pitch/yaw against locally owned original gameplay evidence.

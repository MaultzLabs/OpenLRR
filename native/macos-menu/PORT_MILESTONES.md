# Native port acceptance ledger

Updated 2026-11-03. The earlier 80% completion estimate is withdrawn: there was no complete denominator or full-game acceptance run. Do not assign a completion percentage from source volume, passing parser tests, or a successful compile.

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

## Original LightWave model coordinate basis — 2026-11-01

OpenLRR's gameplay containers use the original map's X/Y horizontal plane and
world up `(0, 0, -1)` (`Camera.cpp::Camera_Update`); native SceneKit terrain
uses X/Z horizontal and `(0, 1, 0)` up. The native renderer was loading
original LWOB vertices and LWS motion keys unchanged, then placing their roots
into the SceneKit world with no coordinate-basis conversion. Stand/Route/Drill
Raider meshes, camera nulls, building scenes and ore/crystal meshes could
therefore be oriented incorrectly relative to the native terrain.

Apply one +90-degree rotation around model-root X, consistently for Raiders
and other original mission objects: `(x, y, z) -> (x, -z, y)`. Keep raw LWS
child matrices, mesh vertices, pivots, texture coordinates and original AE
scales unchanged. Synthetic portable axis-regression checks and hosted SceneKit
model hierarchy/camera-null tests cover this path; the camera-null test now
expects the converted original direction and height axes. This is a source-
grounded coordinate-system correction, **not** proof of visual retail parity.
Original meshes, pivot conventions, model faces, animated drill and player
camera pitch/flip still need in-game user-owned-asset validation on Mac.

Next: source-grounded animated camera-null forward/up extraction and AE
CameraFlipDir handling, followed by real-asset first-person drilling tools.

## Animated first-person camera-null facing — 2026-11-02

Native first-person previously followed the named original LWS camera-null
**position** but always ignored its animated orientation, instead using only
controller yaw (with horizontal 4:1 damping). This branch samples each original
Stand/Route/Drill null's live model world transform, converts its local +Z
Container_GetOrientation forward vector to SceneKit, and applies the original
Camera_Update 3-D normalized-vector blend (4/elapsedAbs, reversed-facing snap,
0.99999 jitter threshold) with converted +Y world up. CameraFlipDir is read
from AE using the original Config_GetBoolValue/Util_GetBoolFromString BoolTri
YES/TRUE/ON rule; only explicit true reverses source facing. Missing,
nonfinite, zero-length or near-vertical authored vectors continue to use the
provisional input-controller heading. No replacement asset is generated.

Portable tests cover original AE BoolTri and full 3-D damping, invalid poses,
vertical fallbacks, reversals and pitch. Hosted synthetic SceneKit tests cover
hidden animated camera-null heading, pitch and flip, and the original tests
still cover camera positioning/drill tracking. This is compiled-prototype
orientation work, **not** measured original-game visual parity: interpreting
the original camera null local +Z forward and CameraFlipDir as vector inversion
must be checked with legitimate original-game model frames. No user-owned
retail asset, Windows runner, Wine installation or save was read or changed.

Next: verify facing/pitch signs and first-person drill model and sound against
authorized original assets in a local Mac session, then implement first-person
FPPoly tool geometry and actual drill timing without substitute art.

## Original Pilot drill time and original Drilling WAV playback — 2026-11-03

The former native excavator used a **single LWS animation-cycle duration** (or
an arbitrary 0.75 seconds if that clip was missing) to destroy every mineable
wall. In the original engine, `Stats_Initialise` reads the level-zero Pilot
`LooseDrillTime`, `MedDrillTime` and `SeamDrillTime` CFG seconds, multiplies
them by `STANDARD_FRAMERATE`, and `Level_Block_Damage` accumulates game ticks.
The native scene now uses those original **unscaled seconds** as its drill
action duration for dirt (including original raw Soil remapped to Loose),
medium rock and ore/crystal seams, with explicit clip-duration fallback when
no supported valid stat exists. Hard rock remains intentionally non-drillable.

During that same native drill action, configured original `SFX_Drill` looping
and `SFX_DrillFade` completion/cancellation WAVs are resolved from the selected
user-owned WAD or existing loose game audio folder. The Pilot stats overrides
are supported when registered in original `Samples`. Volume is converted from
the original DirectSound attenuation setting. Audio pauses with the mission,
resumes, and is stopped on order replacement, cancellation or scene teardown.
No original audio is copied into the repository or source-only Mac package;
missing/unplayable samples remain silent, not substitute effects.

Portable synthetic regressions check original terrain-code mapping,
level-zero colon-delimited stats, invalid/missing durations, default and
registered/custom SFX names, and unregistered-name fallback. The normal hosted
ARM64 build checks AppKit/AVFoundation integration when available. This is
not yet a retail-asset audible gameplay acceptance: per-unit spatialized
3-D attenuation, original sample-group randomization, drill strength and
accumulated wall damage, upgrade levels, true FPPoly hands/tools, exact drill
animation pacing and real-original-file comparison remain unverified.

Next: read `Creature_Load`/ `LegoObject_LoadMeshLOD` FPPoly entries from the
owned original Pilot AE, attach real first-person meshes to each appropriate
camera-null frame, then verify drilling look/sound against retail gameplay on
Apple Silicon. No percentage of full-game completeness is asserted.


## Original Pilot physical collision radius — 2026-11-03

The native first-person controller and click-to-move previously hard-coded a
0.23-tile body radius and a 0.22-tile other-Raider radius irrespective of the
original Pilot configuration. Original `Stats_Initialise` in
`src/openlrr/game/object/Stats.cpp` reads `Stats::Pilot::CollRadius`
in game-world units; when it is zero, it reads `CollBox` width,height and
uses half the larger dimension. Original `BlockSize` converts that radius
to the tile coordinates used by native swept navigation.

The native scene now uses the converted original configured radius for its
continuous route planning, first-person wall checks, and moving-Raider disc
collision (both sides of the pair). Portable synthetic tests verify config
precedence, radius/box scaling, missing/invalid stats fallback and that a
larger body radius really changes swept obstruction detection.

The existing navigation algorithm cannot safely represent a radius >= 0.5
tile, so such values deliberately fall back to the old **provisional**
0.23-tile clearance rather than silently clamping the retail radius. This
does not prove original collision fidelity: original unit/object placement,
collider shapes, slope/step handling and on-device gameplay remain unverified.
No real game assets or saves are modified.

Next: load original `FPPoly` mesh-LOD references from Pilot AE and attach
the authorized original first-person hands/tools to the real camera activity,
then verify first-person drilling and collisions visually on the user's Mac.

## Original Pilot FPPoly first-person mesh-LOD — 2026-11-04

The original `Creature_Load` calls `LegoObject_LoadMeshLOD` for FPPoly with
`CameraNullFrames` sets; `Creature_SwapPolyFP` invokes
`MeshLOD_SwapTarget` for the requested camera set. The native Pilot loader
now parses `FPPoly::CameraN` tables from the original AE config, resolves
model-local genuine LWOB replacement parts read-only from owner files, and
keeps camera sets distinct. The existing LightWave renderer preserves UVs,
surface materials and original LWS animation transforms. During F-mode for
an eligible Raider, the first camera-set geometries are swapped only into
their configured matching LWS parts, including explicit `NULL_OBJECT` parts;
leaving first person restores precisely the previous regular meshes. Missing,
unsupported or mismatched assets keep the camera-only prototype and issue a
diagnostic, never fabricate replacement art or modify files.

Portable synthetic AE/LWOB/parser/unsafe-path tests and hosted SceneKit
mesh swap/restoration tests are now wired into the normal free CI. **Actual
retail asset behavior remains unverified**: the owned Pilot AE, precise
FPPoly naming/part binding, tool visibility and clipping, selected camera-frame
choice beyond Camera0, first-person hand/drill animation, and original in-game
sound/timing need observed comparison on the user's Apple Silicon Mac.
A successful compile cannot establish gameplay acceptance.

Next: verify the original Pilot's FPPoly table and mesh part naming with
authorized game assets, then implement multiple retail camera-frame selection,
test correct drilling hands/tool geometry against the first-tutorial mission,
and continue full-game campaign/economy acceptance. No completion percentage.


## Original FPPoly multiple-camera frame selection — 2026-11-05

Original `Creature_Load` uses `CameraNullFrames` as the MeshLOD FPPoly
set count, while `Creature_SwapPolyFP` passes the active `cameraNo` to
`MeshLOD_SwapTarget`. The November 4 native prototype loaded several
CameraN tables but always used Camera0 for every frame and always tracked
the Camera_00 null. This could show one camera's hand/tool geometry from
another viewpoint.

The native Raider now keeps the author-supplied FPPoly replacements for
each original camera frame, switches matching replacement geometry and the
animated `CameraNullName_0N` anchor together, restores untargeted geometry
when changing sets, rejects invalid frame indices, and restores all regular
model geometry when exiting F mode. `[` and `]` cycle the available original
camera frames while in F mode. This is a clearly provisional native
diagnostic key mapping, **not** a claim about the original game's controls.
An absent camera null retains the previously documented camera fallback;
nothing is generated or modified in the user's game data.

Synthetic portable fixtures now include Camera1-only original FPPoly and
camera-set rejection checks, and hosted SceneKit fixtures exercise
Camera0/Camera1 mesh, body restoration and animated-null selection.
The previous PR #77 exact-head Linux portable suite passed, while the
hosted Mac job on run 41837102942 ended **cancelled**: it is not a Mac
compile success. New branch CI is required to verify this change.
Original retail AE/WAD appearance, material placement, animation/tool
clipping, authentic camera switching input and actual playable drills
still require user-owned assets on an Apple Silicon Mac.

Next: verify Mac source compilation and synthetic SceneKit frame switching,
then confirm the retail Pilot's actual FPPoly camera sets and model bindings
through legal local assets. After that, test first-person wall destruction,
rubble, sound and tutorial objectives together. No full-game percentage.


## Original first-person mesh visibility across activities — 2026-11-06

Original `Creature_SwapPolyFP` and `MeshLOD_SwapTarget` bind genuine
FPPoly replacement parts by authored camera set, but each native ACT
activity has its own LWS part hierarchy. The native camera-frame selection
prototype applied genuine replacements to all available clips; its global
"some replacement exists" flag could nonetheless keep the entire Raider
body visible in first-person mode when the *active* Stand, Route, or Drill
clip had no matching original FPPoly part. That unmodified full-size body
can obscure the player's first-person view.

The native model now determines visible first-person replacements from the
current animated clip and selected CameraN set, not from other activities.
On every unpaused animation/input frame the view re-evaluates first-person
body visibility from the authenticated current activity while preserving
the original LWS camera-null transform tracking even when that body is
hidden. Exiting F mode still restores each original mesh. No temporary
hands, tools, synthetic artwork or retail data are shipped.

Hosted macOS SceneKit synthetic regression coverage now includes an original-
format Stand clip with an FPPoly hand and separate Route/Drill clips which
lack those target parts. It checks hiding on both transitions, restoration
on returning to Stand, camera attachment selection, camera-set transitions,
and original meshes restored upon F-mode exit.

**Acceptance boundaries:** passing synthetic tests and an ARM64 compile
would demonstrate implementation and buildability, not that the authentic
Pilot's exact FPPoly names/parts, hand position, Drilling tool motion,
original frame-switching input, live cave rendering, or tutorial objectives
match the retail game. The user-owned files still need local visual and
playable verification. The next gameplay milestone is authentic first-person
drilling hand/tool, sound and real wall destruction synchronized on the
first tutorial map, then rubble handling and objective completion. No
overall game-completion percentage is asserted.


## Accumulated original wall damage during interrupted drilling — 2026-11-07

OpenLRR's `Level_Block_Damage` accumulates damage on the wall rather than
treating every fresh drilling animation as a full undamaged wall. The native
prototype previously used a one-shot `SCNAction.wait` and erased all progress
on retarget/cancel. The native mission now credits normalized drill work per
**unpaused simulation frame** using original level-zero Pilot
`LooseDrillTime` / `MedDrillTime` / `SeamDrillTime` seconds where available.
Damage remains on that original mission-local wall across cancels, pauses,
view changes and later Raider orders, without editing the retail MAP/WAD.

Before charging any frame, the code revalidates cardinal adjacency, the
original non-hard mineable wall, the current exposed approach tile, the Raider
motion generation and finite positive duration. Unobserved frame stalls are
bounded to 0.25s. On threshold the existing original-map overlay adds floor
and rubble, reveals eligible connected hidden cavern, refreshes the real
terrain navigation, and exposes the new floor through `tutorialGroundValue`
for the original NERPs script. Timed sound and active Drill LWS activity stop
when the order completes or is cancelled; no wall can be finished by a stale
SceneKit action completion. Portable synthetic tests exercise partial damage,
interruption, illegal/remote/paused frames, threshold completion and unchanged
original map bytes.

**Acceptance boundary:** incremental damage and script-visible floor are
implemented in native code, not equivalent to visual retail gameplay on a Mac.
Full source-accurate `Level_Block_Damage` coefficients, upgraded tools,
multiple-object digging rates, crystals/ore drops, rubble *clearing*, sound
position/variant, input parity and actual owner-asset FPPoly drilling require
further implementation and comparison. No completion percent is claimed.

**Next playable milestone:** clear drilling rubble with the original Spade
task, validate NERPs tutorial handoffs and actual source-asset first-person
wall destruction, then integrate ore/crystal resource collection.


## Four-stage rubble removal using original Clear/Spade task — 2026-11-08

OpenLRR `GameCommon.h` defines `AITask_Type_Clear`, `Activity_Clear`,
`Interface_MenuItem_ClearRubble`, `LegoObject_ToolType_Spade` and
`LEGO_RUBBLELAYERCOUNT = 4`. The native mission overlay now recognizes
both pre-authored exposed rubble from the user's retail terrain MAP and
fresh rubble resulting from breaking a mineable wall. Its four layers
decrement only while a selected Raider is standing on the reachable rubble
tile and receiving positive, finite, **unpaused** simulation time. Invalid
remote attempts cannot advance the task; partial work on an individual
layer remains across stop/move/reissue, without altering original MAP data.

Clicking rubble exposes the original CFG `ClearRubble` icon in a dedicated
command panel. The selected Raider uses existing swept wall-clearance,
dynamic-Raider destination checking and command-generation cancellation to
reach that tile before starting. When an authentic Pilot `Activity_Clear`
LWS clip exists, the native model plays it and uses its animation-cycle
duration per layer. Missing or malformed animation duration has a
**provisional** 0.75-second fallback, not generated art or retail timing
parity. SceneKit terrain recomposes original Rock atlas textures
`TEXTURE_RUBBLE_FULL/HIGH/MEDIUM/LOW` (0x10–0x13) for successive
layers, then restores the original floor material; the exact 3-D rubble
pile shape is not yet reproduced.

Synthetic portable tests cover four layers, partial/cancelled work,
remote/invalid times, authored rubble, original MAP immutability and
stage-specific material selection. Hosted SceneKit tests exercise an
original-format Clear LWS activity and first-person body visibility.
No tests use or redistribute retail game files.

**Not yet retail-playably verified:** original level visual appearance,
correct per-Raider Spade possession and eligibility, exact clearing rate /
RubbleCoef and upgrades, physical rubble pile geometry, original tool
effects and sounds, multiple simultaneous clearing units, NERPs-driven
task completion, real first-tutorial objective completion, resource
collection/economy and full campaign. Build/test results are reported
separately from playable acceptance.

**Next milestone:** authorize clearing only for Raiders with the original
Spade and CanClearRubble stats, then wire resource drops and collection to
the wall → four-stage rubble → tutorial objective loop and test with the
owner's original assets on Apple Silicon. No completion percentage.

## Pilot CanClearRubble capability gate — 2026-11-09

OpenLRR `Stats.cpp::Stats_Initialise` sets
`STATS1_CANCLEARRUBBLE` only when the original
`Stats::Pilot::CanClearRubble` value is explicitly TRUE/YES/ON.
The November 8 native Clear prototype enabled the command for every
selected Raider, even if the original stat was false or missing.
The November 9 isolated branch now reads that original BoolTri setting
and disables the ClearRubble HUD command for incapable/missing Pilot
stats. Direct commands, asynchronous arrival callbacks and in-progress
simulation updates all independently re-check the capability; no
unqualified order can advance rubble work. Fractional clear-cycle time
is now carried across four-layer rubble texture transitions instead of
being discarded at each boundary, avoiding frame-alignment-dependent
clear times (while retaining the existing bounded per-frame work cap).
Synthetic portable tests cover true/false/missing/invalid stats,
command availability and sub-layer work carryover.

**This does not yet enforce possession of an original Spade.** Original
`Stats_AddToolTaskType(Spade, Clear)` maps the task to the tool, but the
native app does not yet simulate tool-store acquisition, per-unit tool
inventories or upgrades. Do not claim Spade possession or full retail
task assignment. Existing clear timing is based on authored
`Activity_Clear` clip duration when available, otherwise an explicitly
provisional fallback; source-defined `RubbleCoef` and effects require
verification before retail speed parity can be claimed.

**Acceptance:** Source implementation and synthetic tests are separate
from hosted ARM64 compilation and actual owner-asset gameplay. Verify
the exact final commit's CI before claiming a pass. The first tutorial
still needs ore/crystal drops and collection, actual Spade acquisition,
NERPs completion, original sound/mesh visual comparison, building/economy,
vehicles, save/load, and an end-to-end campaign run.

**Next chosen gameplay milestone:** original resource drops from CryOreMap
after a wall is drilled, with distinct collectible ore/crystal items and
NERPs counters. Validate against original C++ and locally owned assets,
without adding substitute artwork.


## Typed original CryOreMap drops after wall destruction — 2026-11-10

OpenLRR `GameCommon.h::Lego_CryOreType` maps retail CryOre codes 1–20 to
crystal/ore, level 0/1 and quantities 1, 3, 5, 10 or 25. A configured
`CryOreMap` is now loaded read-only beside the terrain MAP, with
the same dimensions required. Missing maps remain optional; code zero,
unsupported values and out-of-bounds cells do not invent resources.
A successful cardinal-adjacent mining completion creates exactly one
mission-local typed drop group at that source wall; invalid attempts and
repeated completion cannot manufacture extra drops. The original MAP/WAD
bytes never change, and no drop automatically increments picked-up or
stored ore/crystal counts.

The existing original-model loader is reused to render **only authentic**
owner-supplied `MiscObjects::Crystal` and `MiscObjects::Ore` LWOB geometry,
using the authored resource materials and color; if unavailable no stand-in
geometry is generated. Individual mesh instances reflect the decoded count.
Temporary regularized drop placement is **not original PTL tumble timing**,
and level-one resource visuals, carrying and task assignment are not
retail-verified.

Portable synthetic regressions cover all 20 supported codes, malformed
and absent CryOre maps, strict dimension checks, attempted remote/repeated
mining, drop persistence, and unchanged source map bytes. Hosted ARM64
compilation status must be established from CI for the final commit.
These are original-map-driven gameplay objects, **not** confirmed retail
appearance or a playable collection/economy loop.

**Next selected milestone:** Collect a dropped resource with the correct
original Raider task/animation, carry it to a valid Tool Store, and only
then update the relevant original counters/NERPs callbacks. Resolve the
source PTL resource generation timing and inspect real-asset placement on
the owner's Mac before claiming parity. Building, upgrades, vehicles,
script completion, native save/load and full campaign acceptance remain
incomplete. No completion percentage.

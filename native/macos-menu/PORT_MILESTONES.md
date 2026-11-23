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
| Saving/loading gameplay | Read-only original .sav inspection; NERPs victory unlocks original LevelLinks in-session, with explicit separate native JSON export/import (2026-11-20) | Complete original reward/save semantics, level unlock persistence and round-trip played state without modifying owners' existing saves |
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


## One-piece ore/crystal collection and Toolstation delivery — 2026-11-11

Original source `GameCommon.h` defines `AITask_Type_Collect`,
`AITask_Type_Deposit`, `Activity_Carry`, `Activity_CarryStand`, and the
Tool Store OL type `Toolstation`. The previous CryOreMap milestone spawned
authentic ore/crystal resource objects but could never remove one, carry it, or
deliver it. A selected Pilot can now click a visible dropped resource tile to
route using the existing continuous wall-clearance and moving-Raider checks,
then collect **exactly one** resource unit on confirmed arrival. The stack
decrements without rewriting original WAD/MAP data. A second pickup while
carrying is refused; route cancellations and stale arrivals cannot credit
an item. The native diagnostic click mapping is not represented as original
retail controls.

A carrying Raider uses the owner's original `Activity_Carry` and
`Activity_CarryStand` LightWave scenes if present. If absent, the existing
original Route/Stand animation remains; no replacement meshes or generated
tools are supplied. Delivery plans use a **pre-existing original** OL
`Toolstation`, block real building footprints, and choose reachable adjacent
tiles. The resource remains carried when no actual store is placed, routing
fails, or the order is cancelled. It is counted in *mission-local native
storedResources* only after physically reaching the planned store approach,
not upon wall destruction or first pickup.

Synthetic portable tests cover remote and repeated pickup rejection,
one-item inventory, 25 sequential collect/deposit trips, depleted stacks,
actual-store requirements, interrupted/wrong-Raider delivery, and original
CryOreMap immutability. Hosted synthetic SceneKit tests cover authentic
Carry/CarryStand activity and FPPoly visibility transitions. These tests and
Mac compilation must be reported from actual completed CI jobs, not assumed.

**Acceptance gaps:** Exact original Collect/Deposit animation timing,
handheld object attachment, task queues and auto-assignment, proper
Toolstation entry/storage footprint, construction of missing Tool Stores,
original pickup/drop SFX, original resource-tumble timing, script-visible
NERPs pickup/storage counters and objectives, original retail asset visuals
and owner-Mac gameplay are unverified or unported. The prototype neither
credits NERPs early nor invents a store. This is a bounded resource-economy
interaction milestone, not complete retail economy or a game-completion
percentage.

**Next milestone:** Read original `NERPsFunctions.cpp` pickup and storage
semantics, connect successful real deposit events to matching script-visible
crystal/ore counts, and finish original Collect/Deposit animations and
carried object attachment before live first-tutorial validation.

## Original NERPs physical-resource counters — 2026-11-12

OpenLRR `NERPsFunctions.cpp` exposes distinct NPL expressions:
`GetCrystalsPickedUp` (0x0C), `GetCrystalsCurrentlyStored` (0x0D),
`GetOrePickedUp` (0x60), and `GetOreCurrentlyStored` (0x61).
`Object.cpp` increments picked-up counters after GatherRock, whereas
`Game.cpp` stores ore and crystals separately. Native confirmed one-unit
Collect actions now increment the appropriate mission pickup counter; successful
physical Toolstation deposits independently increment stored inventory.
Original NPL queries read the mission overlay every tick and never consume
events. Wall destruction, a pending route, a duplicate pickup and a carried
resource without a store cannot satisfy a stored-resource goal.

Portable tests cover all four callback IDs, non-consuming reads, a synthetic
NPL banked-crystal condition, 25 sequential actual pickups and deposits and
missing Toolstation behavior. This is not original Collect animation completion
timing (native collection currently completes at verified arrival), nor full
retail economy. Initial stocks, power drain (included in the original crystal
stored query), ore refinery, genuine store entry, task AI, other resource sources,
construction spending, original held meshes, sound, visual owner-asset testing
and mission win/loss remain incomplete. Report exact CI conclusions separately.
No overall percentage is assigned.

**Next:** authentic GatherRock/Collect/Deposit timing and original handheld
resource geometry, then live first-tutorial original NPL completion handling.

## Original Pilot Collect/Deposit activity gating — 2026-11-13

OpenLRR `src/openlrr/game/object/Object.cpp` selects `Activity_Collect`
for `LIVEOBJ1_GATHERINGROCK` and `Activity_Deposit` for
`LIVEOBJ1_STORING`, then waits for activity completion before advancing the
object task. The native Pilot renderer now loads those named original AE/LWS
activities if present, animates them in the existing genuine LWOB hierarchy,
and switches back to Stand or CarryStand afterward. No alternative artwork
or animation is created.

After arriving at an original CryOreMap item, the native Raider now defers
**removing one drop, taking possession, and incrementing the NERPs pickup
counter** until its original `Activity_Collect` cycle completes. After
physical arrival beside an existing original OL Toolstation, it likewise
defers **stored resource credit and the removal of carried state** until its
`Activity_Deposit` cycle finishes. Both use the unpaused mission clock,
with each unobserved frame clamped to 0.25 seconds; interrupting a task or
changing movement invalidates its generation and cannot finish an obsolete
pickup or deposit. Arrival and source stack/real Toolstation are validated
again at completion. If the owner lacks a supported original LWS clip, the
older immediate-completion fallback is explicitly retained and does not
invent an animation. The original resources, saves, Wine and main are untouched.

Portable timing tests cover invalid duration/elapsed, pauses, frame-stall
capping, and exactly one animation-cycle completion. Hosted macOS synthetic
SceneKit tests exercise genuine-format original `Collect` and `Deposit`
scene selection and first-person geometry transitions. Their **actual CI
conclusions must be checked on the final commit**; compilation and original
owner-asset on-device appearance are not inferred from source or fixture tests.

**Acceptance gaps:** The original resource mesh is not yet attached to
`CarryNull`, original activity frame-rate overrides/throw-timing and sound
are not confirmed, and source-accurate automatic tasks, store entry/power,
resource spending, actual tutorial NPL completion and owner-Mac gameplay
remain incomplete. This is an incremental state-machine and animation
milestone, not a full-game completion percentage.

**Next:** attach the original carried ore/crystal LWOB to the animated Pilot
carry null without substitute geometry, then verify the entire drill →
collect → deliver → original NPL objective sequence using the owner's assets.


## Original carried-resource LWOB attachment — 2026-11-14

OpenLRR `Creature_GetCarryNull` in `src/openlrr/game/object/Creature.cpp`
reads `CarryNullName` from the original Pilot AE and resolves its frame-zero
LWS part through `Container_FormatPartName`. The native activity renderer now
uses that authored `*_00` null, if present, to parent **the same original
ore/crystal LWOB root removed from the opened CryOreMap stack** after a
successful Collect activity. This transfers an existing user-owned mesh
instead of creating a placeholder, and preserves its authentic original
materials/UVs. During Stand/CarryStand/Carry/Collect/Deposit animation
changes the mesh follows the active clip's corresponding animated null.
If an activity lacks the original null, the mesh is temporarily detached
rather than rendered at a stale/free-floating location; mission custody
remains intact. A successful completed Toolstation deposit detaches the
mesh and ends carrying; interrupted deliveries retain it.

The resource mesh is converted from standalone world rendering coordinates
to character-null local coordinates by removing the already-applied
world-to-SceneKit basis rotation and using inverse Pilot AE Scale. The
Pilot model root already supplies the original basis and
`AE Scale / BlockSize`, so the resource must not be scaled a second time
by `1 / BlockSize`. Source files are only read, never modified.

Synthetic tests cover original AE null-name lookup, authenticated LWOB
geometry retained through pickup, carrying-clip hand reparenting, no
double transform, and removal after deposit. The preceding PR #86 hosted
Mac compile was found to have failed due to Swift type-check exhaustion
in long optional-clip concatenation expressions, despite successful
portable tests. This branch replaces those expressions with one explicitly
typed activity collection. Its own CI result still determines whether
both corrections compile.

**Not yet verified:** actual retail Pilot null naming, hand alignment,
resource orientation, mesh scale and material appearance, animation/sound
synchronization and full first-tutorial victory on the owner's Mac.
Absent original files are never replaced with fabricated artwork.

**Next:** run a genuine user-owned first-level sequence from original
wall drilling through source-model pickup, visible carrying, Toolstation
deposit and NERPs storage objective. Then implement automatic Raider task
assignment and remaining first-tutorial completion behavior, with
original AI logic as reference. No completion percentage is asserted.

## Original NERPs mission completion/failure bridge — 2026-11-15

The original source `NERPsFunctions.cpp` calls `Objective_SetStatus` for
`SetLevelCompleted` / `SetLevelFail`, and `Objective.cpp` loads the
authored `Completion:` and `Failure:` sections from the same per-level
ObjectiveText file as the opening `Objective:` message. Native NPL 0x08
now latches a genuine scripted level-completed outcome; 0x09 and 0x0B
latch failure. The mission status is not manufactured from the wall being
drilled, an undelivered pickup, a new PR, or a numerical progress estimate.
Repeated end calls, a diagnostic pause, and callbacks while the initial
objective window remains open cannot prematurely or repeatedly end the level.
0x0A (`SetGameCompleted`) remains explicitly unsupported pending exact
reconciliation of its distinct original source behavior.

The existing owner-supplied bitmap panel, fonts, configured heading and
ObjectiveText pages are reused for native success and failure. The live
mission session stops further NPL ticks, player movement, and mission audio
after a script-set outcome, and gives the outcome overlay its own dismissal
path back to the original menu. No substitute art, campaign unlock or
writable save is introduced.

Synthetic tests exercise the original NPL banked-crystal predicate,
undelivered pickups, paused/briefing/finished states, failure action, and
the three independently parsed original status text sections and headings.
The standard hosted Linux portable and macOS-15 ARM64 actions must pass on
the final commit before calling this compiled/verified. Source-only test
fixtures are not an actual owner's-asset in-game tutorial playthrough.

**Not accepted:** Full tutorial NPL function coverage and its genuine
unmodified script reaching a success branch, retail timing/audio/animation
comparison, original outro teleport and rewards, win/loss persistence,
next-level unlocking, original WAD-visible UI fidelity, automatic AI task
assignment, construction, vehicles, campaign save/load and a full playthrough.
These require the owner's retail assets on Apple Silicon and separate
acceptance evidence; do not assign a full-game percentage.

**Next milestone:** Run the real first original mission script through the
complete drill, rubble, crystal pickup, carry, Toolstation deposit and
scripted completion path using owner-owned game assets. Resolve the first
missing original NPL callback or gameplay task encountered; then restore
retail outcome/reward/next-level persistence without touching existing saves.


## Source-grounded follow-up Collect/Deposit tasks — 2026-11-16

A completed original resource deposit now allows the **same Raider** to
continue the existing `AITask_Type_Collect` → `AITask_Type_Deposit`
sequence for remaining *physically exposed* CryOreMap units without requiring
one mouse click per crystal. `NativeExcavationState.planNextCollect` picks
a deterministically ordered shortest reachable route, respects original
building footprint occupancy, and refuses new pickups while the Raider
is carrying an item. The live 3D view re-plans and revalidates the task
on arrival, then waits for original Collect/Deposit activity completion
before moving the original LWOB model and changing NPL pickup/storage
counters. Exhausted stacks terminate naturally. User move/retarget
cancels pending actions through existing motion-generation checks; a
paused mission never progresses a pickup or storage credit.

This is a **follow-up task chain after a real deposit**, not the full
original idle-Raider AI scheduler or priority system. Starting the first
task still requires a player click. A blocked route or missing original
Toolstation leaves the actual resource uncredited; no magic items,
virtual buildings or replacement artwork are introduced. In first-person
mode the auto-follow-up is not started, pending a source-accurate policy.

Also reconciled original `NERPsFunctions.cpp::SetGameCompleted` (0x0A):
despite its name, before `GAME1_LEVELENDING` the retail function calls
`Objective_SetStatus(LEVELSTATUS_FAILED)`. Native NPL now **fails**
the active mission rather than inventing a successful completion; an
already-ended mission remains latched. Synthetic tests guard against
this misleading victory and verify reachable follow-up, footprint
exclusion, in-flight custody and eventual stack depletion.

**Still not accepted:** an actual retail-assets first-tutorial playthrough,
automatic idle-unit priorities, exact PTL tumble/drop placement, original
Raider tool acquisition and rubble-clearing rules, first-person full
carry/drill fidelity, resource SFX, original outro/rewards, save/load and
next-level unlock. All effects remain mission-local. Full-game acceptance
cannot be quantified by these source/test changes.

**Next milestone:** Test the owner-owned first tutorial end-to-end on
Apple Silicon and implement source-accurate idle-Raider task dispatch,
followed by original campaign progression/save semantics without
overwriting or migrating existing saves.


## First automatic idle-Raider resource dispatch — 2026-11-17

The mission-local native AI can now initiate its **first**
`AITask_Type_Collect` for an exposed original CryOreMap item without
requiring a player to select a Raider and click every resource. The
`NativeExcavationState.planIdleCollection` planner chooses a deterministic
shortest reachable pickup-plus-original-Toolstation trip from available
original OL Rock Raiders. It requires a genuine exposed drop, an eligible
free Raider, and an entrance to an original pre-placed Toolstation reachable
from the drop. It excludes original building footprints and makes no pickup,
storage, script, or geometry changes during task selection.

On an unpaused native gameplay frame, the view periodically checks for an
idle assignment. It does not interrupt ongoing movement, drilling, clearing,
Collect/Deposit animation, a carried item or an original vehicle driver.
An explicit player move, cancellation or first-person takeover suppresses
idle reassignment for that Raider until a subsequent player Drill, Clear or
Collect command. The assigned task reuses existing swept movement, original
LightWave Collect/Carry/Deposit, resource ownership and actual Toolstation
storage. One automatic job chain is started at a time; completed deposits
can continue collecting further exposed units using the prior milestone.

Source grounding: `src/openlrr/game/object/AITask.cpp` registers
`AITask_Type_Collect` and `AITask_Type_Deposit` and distinct
`AI_Priority_Crystal`, `AI_Priority_Ore` and `AI_Priority_DefaultCollect`.
The original binary's complete priority weighting, dynamic task reservation,
Tool Store construction and multi-worker scheduling are **not** claimed as
ported. The temporary shortest-route preference is intentionally not
described as original retail priority behavior.

Verification requires portable Linux gameplay regressions and standard
hosted macOS-15 ARM64 build on this branch; actual owner-owned first-level
drill/clear/collect/carry/deposit/NERPs outcome remains unplayed on Mac.
No source assets, existing Wine runner, game saves, main or sibling branches
are changed. No full-game completion percentage follows from this increment.

Next: complete a retail-asset first-tutorial acceptance pass on Apple Silicon,
then implement source-verified task priorities/reservations and actual
mission progression/save semantics without overwriting existing saves.


## Original initial Crystal/Ore priority and per-unit Collect ownership — 2026-11-18

The first native idle-worker resource planner previously chose the shortest
pickup-plus-Toolstation route regardless of the original engine's task
priorities. OpenLRR `AITask.cpp::AITask_Initialise` initializes all AI
priorities to 49, then sets `AI_Priority_Crystal` to 55;
`AI_Priority_Ore` and `AI_Priority_DefaultCollect` remain 49.
Both the native first idle assignment and after-deposit Collect follow-up
now prefer exposed crystal drops to ore, then shorter valid routes with
deterministic Raider/tile ties. Manually clicked orders still honor the
player's chosen item. Native does NOT yet implement changes to user-adjustable
AI priority values, disabling priorities, or the entire retail scheduler.

A source task owns one distinct resource object. The current mission
represents same-tile CryOreMap drops as counted stacks, so an explicit
per-Raider reservation now owns **one unit** instead of locking a whole
25-item tile. A task cannot reserve an already-owned last item; direct
Collect, follow-up and idle planning must respect units reserved for other
Raiders. Pickup and NERPs credit still occur only on verified Collect
completion. Cancelling, retargeting, taking direct first-person control,
an invalid path or a failed pickup releases that Raider's reservation.
Successful pickup consumes exactly one real item and releases ownership.
No user-owned MAP, WAD or saves are modified.

New synthetic regressions cover unequal original priority on mixed
crystal/ore drops, unchanged inventories during planning, two-worker
access to multi-item stacks, idempotent reservations, last-item
exclusivity, cancellation/reassignment, arrival revalidation and
one-time pickup credit. The standard portable tests and hosted Apple
Silicon compiler/SceneKit jobs must be evaluated on the **final head**
before build/test success can be claimed. No actual owner-asset gameplay
or original priority UI was visually verified.

Next: verify the complete original first-tutorial drill → rubble →
Collect/CarryNull → Toolstation → NERPs objective path using legal owner-owned
assets on Apple Silicon, then extend source-accurate per-object task dispatch
and full mission progression. No full-game percentage is inferred.


## Concurrent idle-Raider resource assignments — 2026-11-18

Before this increment, a global `automaticCollectRaider` blocked all other
idle workers whenever any Collector was moving, animating or carrying. The
November 18 per-unit reservation work now allows independent automatic
Collect jobs, so this branch removes that global single-worker gate. On each
bounded idle dispatch pass it excludes only Raiders already following manual
orders, drilling, clearing, walking, collecting, depositing, carrying, or
holding per-unit reservations. An eligible second original Pilot can take a
separate reachable drop while the first Raider is still completing its
Collect/Deposit chain. The source mission assets and resource counters are
not modified merely by scheduling.

The current native mover still targets the *centre* of each drop tile, rather
than reproducing original individual PTL item positions. Both idle dispatch and automated post-deposit follow-up planning
therefore exclude the pickup tile of any outstanding Collect reservation,
preventing two concurrently assigned Raiders from colliding at the same
single destination. Player-issued Collect orders retain the per-item stack
reservation rules introduced in PR #91. Excluding a target must never create
inventory or claim a false Toolstation delivery. Portable synthetic tests
cover a higher-priority crystal chosen for the first worker, an eligible ore
for a concurrent second worker when the crystal centre is occupied, no job
when all target centres are busy, and unchanged original drop counts and
NERPs counters during planning.

**Acceptance:** source implementation and synthetic portable tests are
separate from hosted ARM64 compilation and actual owner-asset visual/gameplay
verification. The first tutorial is not accepted until original drills,
rubble, carrying, Toolstation delivery and NERPs success are played on Apple
Silicon. Dynamic collision re-routing, true per-object resource positions,
retail AI priority UI and complete multi-unit scheduler remain unfinished.

Next chosen milestone: real first-tutorial end-to-end acceptance using the
owner's legitimate retail game assets, then original PTL per-object pickup
positions/collisions and source-accurate mission progression/save persistence.
No full-game percentage is inferred from this work.


## Retry real Toolstation delivery for idle carrying Raiders — 2026-11-18

A completed native Collect activity removes one original resource object
from the floor and attaches its LWOB to the original Pilot CarryNull. The
immediate follow-up Deposit can still fail when a Toolstation route is
unreachable or a moving Raider invalidates the continuous collision sweep.
Previously the carrying Raider would become permanently idle: automatic
Collect dispatch excludes carriers, and nothing could reappoint Deposit.

The native idle dispatcher now first considers *only free original Pilots
already carrying a physical CryOreMap item*. On a later bounded scan it
replans a route to a **real existing original Toolstation**, excludes
player-held/manual orders, first-person control, other active tasks,
building footprints and an occupied deposit approach, then uses the
existing original Deposit animation and movement validation. No extra
pickup is created. NERPs stored counts advance only after the actual
Deposit activity completes and the original building adjacency is
revalidated. A temporarily blocked or failed route can become eligible
again without losing the Raider's original resource mesh. This is a
bounded recovery step, not a claim that the retail full AI scheduler or
dynamic work-stealing has been ported.

Portable synthetic tests cover a carried crystal reappointment, busy
worker precedence, a blocked Toolstation approach, retry after clearance,
lack of a real store, and no duplicate storage after a completed deposit.
Standard hosted ARM64 compilation and portable test results must be
evaluated on this branch's final SHA. No visually/playably verified
owner-asset first-tutorial run has occurred; source-only fixtures do not
prove pickup placement, animated hand geometry, or mission completion.

Next: actual first-tutorial drill → rubble → original Collect/CarryNull →
Toolstation → NERPs completion validation on Apple Silicon using lawful
owner-owned assets; then original per-object PTL drop positioning and
original level-unlock/save semantics. Do not infer any game-completion
percentage from this code increment.


## Genuine NERPs victory unlocks linked missions in the current session — 2026-11-19

OpenLRR `Front_Levels_UpdateAvailable_Recursive` uses the source mission
catalogue's `setIndex` for original save flags. Its `LevelLinks` traversal
marks a completed mission and its immediate links available, but
`FrontEndOpen` merely enables a particular icon; it does not count as a
completed parent. The native menu had only read-only original save unlocks,
so even after a real NPL `SetLevelCompleted` the next linked mission remained
locked in the same running session.

The native `NativeMissionWorkspace` now reports the latched original NERPs
outcome to its existing menu coordinator. **Only** `.completed` from the
current active workspace records an eligible campaign mission identifier,
case-insensitively. A failed mission, duplicate result, unknown identifier,
or tutorial cannot unlock campaign content. The mission map recomputes its
original linked-icon availability from the union of **read-only original
save completed flags** and the session's verified completions, without
granting children of an uncompleted `FrontEndOpen` mission. Switching original
save slots or reloading a different WAD clears the temporary unlock overlay.
This is deliberately **in-memory, unsaved** progress: no PC save or user
game assets are written, and a relaunch reverts to the original save flags.

Pure Swift regression tests check baseline locks, real linked unlocks,
nonexistent/tutorial identifiers, idempotent victory, original saved
completion union, case normalization, `FrontEndOpen` behavior and session
reset. Hosted AppKit compilation verifies the actual outcome/menu callback
bridge. Both portable and Mac jobs require final-head CI confirmation.

**Not accepted:** Complete original save/reward serialization,
session-to-disk progression, level outro teleport, full campaign completion,
the original first tutorial's full NPL execution with retail assets,
building/economy/vehicles, actual audio/visual fidelity, or a tested
Apple Silicon gameplay session. This is a source-grounded menu progression
bridge, not a retail campaign acceptance or percentage of game completion.

Next playable milestone: inspect actual mission progression/reward data and
implement **separate, opt-in native save persistence** compatible with the
verified session unlock graph without ever overwriting original PC saves.
Before that, prioritize owner-asset Mac playthrough validation of original
drilling, four-stage rubble, CarryNull, deposit and NERPs success; fix the
first real failing action. No invented assets, percentages or paid runners.


## Explicit native-only campaign progression export/import — 2026-11-20

A genuine NERPs-scripted victory already changes the native mission map's
in-memory LevelLinks availability, but the state was lost on application exit.
This increment adds a user-invoked **Native Progress…** Mac control in the
existing non-retail utility toolbar. **Export…** writes only a small, separate
UTF-8 JSON snapshot chosen in an NSSavePanel; **Import…** restores that snapshot
from a manually selected JSON file after reopening the same original game and
original save slot. Neither operation touches original PC `.sav` files,
source archives, Wine, or the game's own media. There is intentionally no
automatic file writing, no export of source assets, and no conversion of
OpenLRR's proprietary PC save format.

The archive records a format version, the entire ordered original mission
selection identifier list, one-based original save slot (or no-slot state),
and identifiers recorded as completed in the active native campaign.
Restore rejects truncated/malformed/oversized files, unsupported versions,
mismatched original slots or mission catalogues, unrecognized/tutorial
identifiers and duplicate completions. All validation happens **before**
replacing session state. The native menu still unions the imported progress
with read-only original completed flags and follows actual LevelLinks.
Changing original WADs or save slots clears the volatile imported overlay;
the player must explicitly import again. An imported user-authored file is
not independently verified proof of a real NERPs victory.

Portable synthetic regressions cover deterministic JSON round-trip, no-slot
round-trip, selected-slot mismatch, changed mission catalogue, unknown/tutorial
and duplicate mission identifiers, malformed JSON, oversized input and
unsupported versions. The standard free Linux Swift tests and hosted
macOS-15 ARM64 build are configured for this branch; report exact-head CI
status separately. No in-game owner-asset playthrough or live Mac file-picker
interaction is claimed from hosted compilation.

**Acceptance remaining:** Original retail first tutorial must be played on
the owner's Apple Silicon Mac from drilling through four rubble stages,
resource pickup and original animated carrying, Toolstation deposit, real
NERPs victory, next-level unlock, application restart, explicit native
progress restore and successful launch of the linked mission. Native JSON
does not yet serialize a paused/in-progress world, units or buildings;
original SaveReward scoring, end-of-level animations, first-person retail
fidelity and campaign completion remain incomplete. No percentage of the
full game is inferred.

**Next chosen milestone:** Actual owner-asset Apple Silicon end-to-end
first-level acceptance, fix the first observed failing original action,
then implement per-object PTL resource positions and source-accurate
building/construction tasks. Keep original saves and assets read-only.


## Pre-placed original OL resource collection — 2026-11-21

Read the original per-level Object List (OL) source placements without modifying
their source coordinates or author order. A level can already contain original
PowerCrystal and Ore objects before drilling; the previous native Collect
scheduler only saw CryOreMap resources spawned after a wall was opened. This
branch seeds mission-local, individually owned Collect tasks for genuine OL
resources, including multiple original resource objects at distinct fractional
positions within one tile. The existing original OL LWOB model remains in its
authored placement until the completed Collect animation; the exact placed
model transfers into the Raider's animated CarryNull, then authentic Deposit
credits stored inventory only after arriving beside an actual OL Toolstation.

The native collector processes same-tile mixed crystal/ore sources in original
OL order, without crediting a future object early. Existing CryOreMap drops
remain a separate source and their original model rendering is suppressed when
the tile is currently occupied by placed OL resources; a newly drilled
CryOreMap deposit is queued rather than replacing an existing OL item.
Unrecognized ProcessedOre is intentionally not reclassified as ordinary Ore:
its economy and processed mesh behavior still need source-grounded support.
Off-map and wall-embedded OL entries are not turned into collectible resources.
Only real original LWOB assets are ever carried; missing assets remain hidden
or diagnostic rather than generated.

Portable tests are added for original OL parsing, multiple mixed-kind objects
on the same reachable tile, one-unit reservation, exact placement identity,
no premature NERPs credit, real Toolstation deposit, and no duplicate pickup.
The standard free portable Linux/FFmpeg + macOS-15 ARM64 workflow is enabled
for the isolated branch. Results must be verified on the final exact SHA;
source-only tests cannot establish owner's original-asset visible gameplay
acceptance. The full original first tutorial still needs an on-device
drill → four-stage clear → pickup → CarryNull → Toolstation → NERPs victory →
next-level launch playthrough. Original per-object PTL tumble positions for
newly drilled CryOreMap drops, full idle-AI task rules, construction, vehicles,
original saved game state and complete retail fidelity remain unfinished.

Next selected milestone: validate this mixed original-source collection and
the first tutorial against owner-owned retail files on Apple Silicon, then
replace provisional post-drill CryOreMap tile-centre distribution with
source-accurate PTL positions and original dynamic-task references. No overall
percentage of completion is supported.

## Idle original Raider rubble clearing — 2026-11-22

Original `src/openlrr/game/object/AITask.cpp` initialises
`AI_Priority_Clearing` at 20, below crystal 55 and ore/default
collection 49. After native Collect/Deposit assignment, eligible idle
non-driving Raiders can now be dispatched to a reachable existing or
post-drill rubble tile. Work uses the already integrated original
`Activity_Clear` and four-layer Spade clearing; it does not create a
new renderer, tool model, substitute art, or virtual completion.

The mission-local assignment planner excludes manually held, moving,
carrying, collecting, drilling, or already-clearing Raiders. In-transit
Clear destinations are tracked separately from active Clear animations,
preventing duplicate worker assignments during travel. Building
footprints and live unit clearance are checked before starting a
route; cancelled, replaced, or blocked routes release their target.
The original `CanClearRubble` config remains a runtime prerequisite.
A planned task cannot reduce rubble or advance NERPs resource counters.

**Verification boundary:** portable synthetic idle-assignment and
path/ownership regressions are added; their CI result must be reported
from the exact commit. Actual Apple Silicon compilation and owner-owned
retail gameplay/animation still require separate verification.
Original per-Raider Spade inventory, global editable AI priorities,
retail task queues, upgrades, path slope and real retail timing are
not implemented. No full-game completion percentage is claimed.

**Next milestone:** perform a legitimate owner-asset first-level
playthrough from drilling through automatic four-stage rubble clearing,
real-object pickup, Toolstation delivery and NERPs victory. Fix the
first observable failure and continue toward actual construction and
full retail mission playability.


## First-person isolated player control with continuing idle AI — 2026-11-23

The native first-person camera previously blocked the **entire** idle-Raider
dispatcher with `firstPersonRaider == nil`. During F-mode, other original
Raiders would stop receiving new Collect, Deposit-retry and four-layer Clear
jobs even when they were idle; existing completed deposits also stopped
chaining follow-up collections. That made the live cavern effectively lose
its autonomous workforce whenever the player directly steered one Pilot.

The dispatcher now keeps running on the unpaused simulation clock during
first-person play, while its busy-worker set explicitly includes the
camera-controlled Raider. Automatic Collect requests for any **other** idle
Raider are accepted, but first-person mouse/manual Collect orders and
automatic orders for the controlled Pilot remain disallowed. Completed
deposits by other Raiders may continue genuine Collect/CarryNull/Deposit
work. Entering F-mode cancels that Pilot's queued Clear destination and
pending Collect/Deposit animation, as well as its existing movement/drill;
no interrupted task advances resource or rubble counters. On F-mode exit the
manual-hold flag is released so that Pilot can rejoin the scheduler; an
already held real resource stays carried until a subsequently valid original
Toolstation Deposit rather than getting stranded indefinitely.

New portable synthetic checks cover player-owned worker exclusion,
concurrent assignment to another worker, manual/automatic Collect guards,
concurrent four-stage rubble scheduling and unchanged counters at task
assignment. The existing standard hosted Linux/FFmpeg/macOS-15 ARM64
pipeline is configured for this isolated branch. **CI status and exact-head
Mac compilation must be checked separately**; source changes alone are
not verification of the model, animations or real original assets.

Acceptance remains open: actual owner-asset Mac first mission drilling,
rubble clearing, CarryNull position, authentic sound, NERPs completion,
linked mission launch and first-person interaction all need an observed
playthrough. No full-game completion percentage can be inferred from this.

**Next chosen milestone:** first owner-asset Apple Silicon tutorial
playthrough; if local retail assets remain inaccessible to CI, implement
source-accurate per-object drilled CryOreMap placement and dynamic task
ownership without substitute artwork, then verify that code separately.

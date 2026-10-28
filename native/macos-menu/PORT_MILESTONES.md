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

# From original tutorial gameplay to source code to native macOS

This is an engineering map, **not a claim that the Windows tutorial has been played**.
It records verified C++ entry points in the checked-in OpenLRR source and the
current Swift equivalents. Every item is a hypothesis to validate in live Windows
gameplay before marking the corresponding native behavior faithful.

## First controlled experiment: tutorial 1 (moving Rock Raiders)

| Observable checkpoint | Original Windows source | Current native Swift | Missing to reproduce retail game |
|---|---|---|---|
| Tutorial step restricts clicks | `game/mission/NERPsFile.h::TutorialFlags`; `NERPsFunctions.cpp::NERPFunc__ClickOnlyObjects`, `ClickOnlyMap`, `AllowCameraMovement` | `NativeTutorialInputPolicy.swift`; enforced in `NativeLevel3DView.swift` and `NativeLevelView.swift` | Full original UI button/selection target behavior; NPL callback ID coverage |
| NPL control flow drives step order | `game/mission/NERPsFile.cpp::NERPsRuntime_Execute` and `NERPsFile_LoadScriptFile` | `NERPsRuntime.swift` and `NativeNERPsGameState.swift` | Most original callbacks, action verification and tutorial next-arrow flow |
| Rock Raider selection | `game/mission/Messages.cpp`; `game/Game.cpp` selected-unit interaction | `NativeLevel3DView.selectRaider` selects actual OL-derived **debug proxy** | Retail selection graphics, sound, toolbar commands, multiselect |
| New movement command | `game/GameCommon.h::AITask_Type_Goto`; `game/object/AITask.cpp`; `game/object/Object.cpp` | `NativeLevelNavigation.swift` does conservative four-neighbor route; `NativeLevel3DView.commandMove` animates proxy | Retail task queue, path costs, dynamic obstacles, unit AI, animation |
| Player notices result | `game/object/Object.cpp`, `game/mission/NERPsFunctions.cpp` tutorial block checks | NERPs VM can emit trace of known calls; static MAP state is loaded | Authoritative moved-unit state, tutorial completion callback, screenshot comparison |

Do **not** assume the native route algorithm matches the original one because
a debug capsule moved. When available, compare route positions, animation
timings and generated task queue against the original executable.

## Subsequent tutorial systems to investigate

| Tutorial area | Source of truth in this repository | Native status |
|---|---|---|
| Rock types, drilling, rubble | `game/GameCommon.h`, `game/object/Object.cpp`, `game/object/AITask.cpp`, `game/mission/NERPsFunctions.cpp` | Original terrain IDs parsed; no original drilling or rubble task behavior |
| Resource delivery, power paths, buildings | `game/world/Construction.cpp` (`Construction_Zone_StartPath`, `Construction_Zone_StartBuilding`, `Construction_Zone_RequestResource`, `Construction_UpdateAll`) | Not simulated |
| Vehicle controls and driving | `game/object/Vehicle.cpp`, `game/object/Object.cpp`, original OL placements | Visual placeholders only; no vehicle controls |
| Explosives and hazardous operations | `game/object/Object.cpp`, `game/object/AITask.cpp`, `game/object/Weapons.cpp` | Not implemented |
| Building prerequisites/upgrades | `game/object/Building.cpp`, `game/world/Construction.cpp`, `game/object/Dependencies.cpp` | Not implemented |
| Mission/defense success | `game/mission/Objective.cpp` (`Objective_IsObjectiveAchieved`, `Objective_CheckCompleted`); `game/object/Weapons.cpp` | Objective-switch latch only; cannot complete retail objective |

## Minimum original-game evidence required per tutorial action

1. A game-window frame **before** input, with matching timestamp and a recorded input
   (button/key/client-position).
2. A game-window frame **after**, associated with the same process and exact
   scenario step.
3. A detectable state transition (prefer actual instrumented unit/world/script state;
   visual difference by itself is weaker).
4. An OpenLRR source symbol that accounts for that transition and its parameter
   or data dependencies.
5. A native counterpart with a regression test and an explicit verdict:
   exact match, partial match, or unsupported.

The Windows lab currently passes synthetic GUI automation. The asset-free
`OpenLRR.exe` hosted runner exited before a matching game window opened.
That is not a tutorial observation. User-owned retail files have not been
uploaded to public GitHub, and should not be.

## Specific first-port conclusion

The original NERPs tutorial functions do not merely tell the player what to
click: they **modify which categories of input are enabled** by setting bits
in a 0x1fff mask. In the native branch this has been implemented as
`NativeTutorialInputPolicy` and propagated to the 3D and 2D viewers, with a
portable regression test. The original level script may still halt on
unsupported callbacks; no mission completion has been demonstrated.

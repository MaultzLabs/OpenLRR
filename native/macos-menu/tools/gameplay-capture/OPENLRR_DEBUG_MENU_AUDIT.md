# OpenLRR Windows system menu: source audit for Wine and native port

Evidence:
- `src/openlrr/OpenLRR.cpp`: `OpenLRR_UpdateMenuItems`, `OpenLRR_HandleCommand` and `OpenLRR_WindowCallback`
- `src/openlrr/game/Game.cpp`: `Lego_SetNoNERPs`, cheat setters and graphics flags
- `src/openlrr/game/mission/NERPsFile.cpp`: `NERPsRuntime_Execute` function dispatch
- `src/openlrr/game/mission/NERPsFile.h`: 294 function signatures and NERPs globals
- Upstream author release notes: https://github.com/trigger-segfault/OpenLRR/releases

## What the attached October 21 screenshots show

The `OpenLRR` window contains native Win32 menu bar `File / Options / Debug / Cheats / Help`
above an entirely black viewport with a dgVoodoo label. The menu bar is
**not** the original 1999 front-end: it is an OpenLRR addition. Wine appears
to draw the OS-level menus, but drawing those controls proves nothing about
the DirectDraw/Direct3DRM game viewport.

Grayed-out controls in the screenshots are a useful negative signal.
`OpenLRR_UpdateMenuItems` deliberately gates controls:

- `Menu_InitCommandLineIDs` require `Main_IsCommandLineParsed()`
- `Menu_LegoInitIDs` require `Lego_IsInit()`
- `Menu_InLevelIDs` require `Lego_IsInLevel()`

Thus gray `Music On`, `Sound On`, `Show Panels`, `No NERPs` and debug
rendering options suggest the Lego game state has not been marked initialized.
**Do not conclude these handlers are broken in Wine** without later evidence.
The enabled `No Build Costs` menu item only flips state; its effect is
not visible on a black viewport before a level exists.

## Menu controls: ranked diagnostic value

| Control | Source behavior | Useful when | Baseline advice |
| --- | --- | --- | --- |
| Options > Logging | toggles Error debug/trace/info/warning/fatal visibility | startup diagnostics and program warnings | Prefer Info/Warning; broad trace can affect timing |
| Options > Dual Mouse | toggles `Main_SetDualMouse` | diagnosing Wine cursor input after video works | Do not change during baseline |
| Options > Graphics | changes Direct3DRM quality, fog, filtering, etc. | isolated graphics A/B experiments | Do not change on working game |
| Debug > Rendering | individually turns on/off Draw, Images and Fonts engines | isolating why the *in-game* 2D HUD freezes | Test-copy only; can intentionally hide UI |
| Debug > Routing Paths | adds route overlays for units | reconstructing navigation/AI | Only after a level starts |
| Debug > Freeze + Advance Frame/1 Second | pauses and advances game frame simulation | measuring one update and input-response step | Only after recording normal timing |
| Debug > Programmer / Debug Mode / Debug Complete | flips developer-related `Main` flags | specific controlled runtime hypotheses | No blanket logging promise |
| Debug > Unlock All Levels | flips `Main_SetLevelsOpen` | navigating into a locked map, not solving rendering | Changes experimental state; optional only |
| Debug > Dump Mode | toggles main dump mode and unpauses | original engine's dump timing behavior | Avoid as a generic recorder |
| Cheats > No NERPs | `Lego_SetNoNERPs` toggles suppression of mission scripts | paired experiment: mission with and without scripts | **OFF while recording NERPs** |
| Cheats > Free Camera Movement | removes restrictions on camera movement | navigation experiment inside a mission | Avoid changing original baseline |
| Cheats > No Build Costs / No Construction Barriers | disables construction checks/costs | testing gameplay systems | No effect until relevant gameplay |
| Cheats > FP Controls | enables first-person-style unit controls | recording special movement | Not useful for menu stall |

The graphics menu is not a magical compatibility switch: in particular the
source explicitly disables changing window scale while render scaling is
active, because it would break the clipper/Direct3DRM device.

## Distinguish why controls appear dead

1. **Gray/unavailable:** the command is deliberately not dispatchable (e.g.
   `!Lego_IsInit()` or `!Lego_IsInLevel()`).
2. **Checked but little visible effect:** the command only updates state, with
   no relevant game object or loaded level to change.
3. **Live Win32 callback but stalled renderer:** clicking menu is responsive,
   while DirectDraw blitting/Direct3DRM presentation is blocked or very slow.
4. **Wine input or focus mismatch:** the game might not receive the same
   events the native Win32 menu handles; check input event timeline.
5. **Truly unimplemented:** the source comments `Toggle Console` is disabled
   because its implementation is unfinished. Some graphics cases are
   commented out rather than handled.

## Why menu video is worth recording

**Capture from the beginning, including the black and choppy sections.**
The black viewport with a live native Win32 system menu provides a useful
discriminator: Windows message dispatch can be responsive while game-specific
graphics and initialization are stalled. Include:
- menu launch and initial OS system-menu response;
- elapsed time until the original retail front-end appears, if ever;
- movement/hover/click timing on menu choices;
- whether `Options > Logging` changes console message visibility;
- any menu animation, ambient audio, or delayed picture;
- menu-to-tutorial navigation when practical.

Two planned session scopes: `--session menu` (15-minute ceiling; no mission
required) and `--session full` (menu through tutorial or 120-minute ceiling).
Both record the menu by default. 30 FPS is a **capture-request setting**, not
a claim the original game draws 30 unique frames.

## Important NERPs caveat

`Options > Logging` toggles OpenLRR Error logging; it does **not** expose
the internal NERPs interpreter's 294 function calls. The original
`nerpsruntimeGlobs.logFuncCalls` is marked "always 0" in
`NERPsFile.h` and the runtime writes only partial debug strings.

For actual NERPs execution data use separate opt-in instrumentation in
`NERPsFile.cpp` on `lab-nerps-trace-optin-v1`. It must compile and be
validated inside a disposable TEST game instance before any user rollout.
Never turn on `No NERPs` during that recording.

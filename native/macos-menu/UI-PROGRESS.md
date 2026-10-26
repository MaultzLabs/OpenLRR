# Mission UI pass

The mission now has a persistent, context-sensitive command sidebar instead of
standalone Drill/Back controls. Main commands, selected Raider, drillable wall,
first-person camera, and building catalog each have their own page. Original
CFG icon paths and available surround images are loaded from the user's WADs;
missing art retains accessible native text buttons.

Implemented controls: drill, cancel the selected Raider's order, first-person
and overhead cameras, Back/deselect, and browse original building names and
costs. Unsupported construction, teleporting, vehicles, tools, training,
reinforcement and dynamite are explicitly disabled. Hover displays the action
and its explanation, including unavailable reasons and building costs. Enabled
icons use the original source's green hover outline; AppKit provides pressed
and disabled feedback. Catalogs scroll without covering Back. Sidebar right
clicks are consumed instead of issuing cave orders.

Mission options now contains the diagnostics and NERPs pause/resume controls.
Action feedback expires after six seconds unless diagnostics is enabled. The
building-menu click feeds the original NERPs Get/SetBuildIconClicked counter.
Tutorial input restrictions continue to disable command buttons.

Validation added: synthetic CFG catalog order, prefix precedence, duplicate and
nested property handling, building labels/costs/icons, unavailable actions,
selection-dependent drilling, surround parsing and bounds, and independent
NERPs building-click get/reset semantics. Linux parser tests and macOS ARM64
AppKit compilation run on each branch push.

Limits: retail asset alignment and actual mouse/keyboard gameplay still need
an in-game review on the user's Mac. This is not a pixel-perfect restoration:
heading/help and the reserved Back row are native layout, and unsupported game
systems are not implemented by displaying their icons. No copyrighted game
art or music is included in source or CI artifacts.

## Screenshot-guided layout correction

Reference images inspected at 640x480:
- https://pichuonigiri.wordpress.com/2015/01/06/lego-rock-raiders/ (base/power paths)
- https://gamesdb.launchbox-app.com/games/images/5325-lego-rock-raiders (lava cavern)

Both show compact upper-right command icons and a persistent empty green bottom
message panel. The follow-up removes permanent sidebar help text, uses a floating
hover explanation, preserves original icon bitmap dimensions, anchors the menu
at the source's (565,18) position, and uses CFG Back highlight/pressed overlays
and offsets when their surround is available. Unused space below the compact
menu now passes clicks to the cave. The message panel stays visible when empty,
with Next hidden. Original surrounding panels, resources and camera controls are
still incomplete; this does not claim a finished retail HUD.

Regression checks cover the empty message panel/hidden Next and cave hit testing
below the sidebar, alongside existing action dispatch and tutorial locks. Real
asset alignment still needs checking in the running native build.

## Fidelity requirement

The target is a 1:1 port, not a redesigned or improved interface. Original
layout, artwork, text, timing and behavior are the specification. Native fallback
controls are temporary missing-asset scaffolding, not the intended design.
Custom hover explanations were removed. Original-style tooltips still need their
retail renderer; accessibility descriptions remain nonvisual. Development options
and action diagnostics are hidden in normal play. They can be enabled explicitly
by launching with `--native-diagnostics`. No additional gameplay HUD controls
should be invented to fill gaps in unported systems.

The first screenshot-pass Mac build compiled, but the UI test trapped. The hit
test fixture was passing flipped-local points to an API requiring parent-space
points. It now attaches the sidebar to a real parent and converts coordinates;
the UI test executable also retains debug assertion messages.

## Original frame panels, message typography and camera input

GameState.cpp provides the exact message origin (42,409), text rectangle
(55,435,325,42), font5_HI.bmp asset, and keyboard camera increments. This pass
replaces the earlier approximate message coordinates and system-font rendering
when the original font is available. It reuses the bitmap-font renderer and
ports TextWindow_Update's width-boundary, word splitting and page-stop behavior
for a single current message; full history/expanded NERPs text remains pending.

OriginalMissionPanels loads fixed panel artwork from Panels640x480: message side,
camera control, top panel, crystal sidebar and info dock. It preserves original
positions and draws in source order. Black-keyed transparent pixels let cave
clicks through. Sliding radar/priorities/info windows remain excluded until
implemented. Resource counters are not fabricated; the sidebar is its original
frame artwork, not a completed resource economy.

The configured camera rotation disk now drives the overhead camera while held,
including its original directional overlay images. Keyboard arrow rotation/tilt
and minus/equal zoom use GameState.cpp's 25-tick rates and CFG Min/MaxTilt/Dist.
Tutorial camera locks and first-person mode suppress these controls. The mouse
rotation sensitivity currently uses those keyboard rates; exact retail pointer
sensitivity still needs comparison. Zoom/cycle icon hit boxes are not guessed:
the Buttons640x480 format still needs a verified installed configuration.

Validation adds synthetic panel parsing, shared 640x480 transforms, circular
control normalization, camera rates/limits, original text wrapping and AppKit
black-keyed panel hit tests at two scales. No original asset bytes are in tests.

### NERPs startup and original message audio

- Added retail function opcodes True, False, Null and the four random expressions. Random uses the original MS C LCG and source masks/moduli; its stream is currently mission-local, not shared with every future gameplay system.
- Unknown nested function arguments now halt with their ID/PC instead of becoming packed instruction integers.
- Message files retain case-insensitive sound references and definition paths, including tab-separated definitions. Chief WAVs resolve from the selected original install/audio folder or WAD, play once independently of music, and stop when leaving the mission.
- Message timers use the original no-sample delay or decoded sample seconds × timerValues[0] + timerValues[1]. Repeated messages and the 0/1 first-line alias do not restart speech.
- Regression coverage executes actual True/False/Null bytecode, checks the source random sequence, unresolved nested callbacks, sound parsing, repeat suppression and timer values.
- Fixed macOS SceneKit camera offset CGFloat conversion from the preceding HUD change.

This is not a complete NERPs port. Unsupported gameplay calls still stop with an explicit ID/PC. SetMessageWait currently records state without interpreter suspension; tutorial block-pointer queries/camera targets, resource economy callbacks, original Next-button timer gating, inline message images and Chief animation remain incomplete. Real retail NPL/WAV mission playback requires the user's original install; CI fixtures verify behavior but are not a retail playthrough.

### NERPs live tutorial bindings

- Load and validate the original BlockPointersMap alongside terrain. Enumerate repeated positive marker IDs, excluding the extra MAP border vertices.
- Bind GetTutorialBlockIsGround (0x72) to the live excavation overlay. Preserve retail's unusual sum of 8 per exposed floor, so digging changes the next script evaluation.
- Bind SetCameraGotoTutorial (0x73) and GetCameraAtTutorial (0x8F) to the overhead camera target; bind GetMiniFiguresOnLevel (0x34) to actual loaded, exposed Raiders.
- Camera goto currently moves immediately while retaining the orbit offset; retail easing and first-person camera handoff still need porting. No terrain-changing tutorial setters or path queries are claimed.
- Tests cover grouped markers, null/invalid IDs, border exclusion, ground value before/after actual drilling, and VM dispatch of camera/ground/unit callbacks.

### Mission playback, cavern discovery and first-person atmosphere

- Mission track discovery retains alternate same-name files so an invalid copy cannot mask a valid one. Also inspect direct install tracks and bounded extracted Rock Raiders soundtrack folders. Playback failure now reports its actual cause in a sheet with access to the existing music picker; audible playback on the user's Mac is still unverified.
- First-person fog reads level FogColourRGB/HighFogColourRGB/FogRate and Main::FPClipBlocks; original rate is seconds (load multiplies by 25, update divides by 25). Use Main::AmbientRGB and camera-attached FPLightRGB. Cave SFX_AmbientLoop plays independently of menu atmosphere and soundtrack, stopping on mission exit. SceneKit fog interpolation remains an approximation of Direct3DRM's fog method.
- Shared lowered corner vertices produce sloped triangle wall surfaces instead of raised cubes. This follows Map3D_MoveBlockVertices/Level_DestroyWall; ProMesh overlays, transition textures/UVs and collision against exact slopes remain incomplete (collision stays conservatively tile bounded).
- Drilling leaves original full-rubble texture 0x10 and reveals connected hidden caverns using eight-neighbour discovery. Hidden OL placements activate on reveal. The Tool Store is still represented by its existing diagnostic placement until the building model/activity loader is ported; this does not claim a finished first-mission playthrough.
- Shift-click toggles Raiders in a group; movement issues individual collision-checked routes to spaced continuous destinations. NERPs sees selection count. Drag-box selection, original formation/task assignment and dynamic replanning remain unfinished.
- Original Activity_Drill is loaded when present and used for the work animation before wall removal. First-person forward contact with an adjacent drillable wall starts the operation. Drill duration currently follows one animation cycle (0.75s fallback if absent), not original hardness/tool/upgrade stats. The first-person body remains hidden: a faithful visible drill/hand rig and drill sound remain unfinished. Rubble is a floor texture/state, not yet debris meshes or four clearing jobs.

References: OpenLRR Game.cpp/GameState.cpp/GameCommon.h and ProjectReversio src/LegoRR/{lego.c,level.c,map3d.c}. Synthetic tests cover alternate music files, extracted patch discovery, fog period/color/distance, sloped mesh topology, rubble and isolated/connected hidden cavern navigation. Original-asset appearance/audio still need Mac review.

Blue/teal spheres are diagnostic non-Raider OL placement proxies, not retail artwork. Hide them in normal play, including when NERPs automatically reveals an error diagnostic. They are visible only when launched with --native-diagnostics and the Diagnostics control is enabled. Missing building/vehicle/resource models are not thereby implemented; those objects remain invisible in normal play until their asset loaders are ported.

## Source-grounded command geometry correction (2026-10-26)

The command layer now fills the mission bounds and uses `OriginalHUDTransform`,
matching panel placement in wide and tall windows. `InterfaceSurroundImages`
fields 1/2 (with Back) or 6/7 (without Back) offset the surround **art**, not the
icons. Icons stay at `(565,18)` and stack by their actual bitmap heights; Back
uses its independent fields 3/4. Main and first-person pages both omit Back.
Negative art/Back offsets are preserved rather than clamped into a narrow
sidebar. Opaque surround pixels and command rectangles consume input; black-key
surround pixels and unused overlay space pass through to the cave. Missing art
retains the native scrollable fallback; unsupported gameplay remains disabled.

Sources: local `src/openlrr/game/GameState.cpp` initialization and
[retail interface.c](https://github.com/ProjectReversio/LegoRockRaiders/blob/master/src/LegoRR/interface.c)
(`Interface_LoadItemPanels`, drawing at lines 249–324, icon-height stacking,
`Interface_NotMainOrFirstPersonMenu`, and rectangular/bitmap hit testing).

Expanded tests use synthetic indexed BMPs inside a synthetic WAD, exercising
negative/nonzero offsets, independent Back placement, uncapped bitmap sizes,
640x480 / 1280x960 / 1600x960 / 640x960 transforms, keyed-alpha input, page
changes, stale buttons, tutorial locks, and malformed/missing-art fallback.
`git diff --check` passed locally. Swift/AppKit tests are **not locally run**:
`bash test.sh` stops at `swiftc: command not found` in this cloud environment;
macOS CI must establish compilation/runtime results. Real retail-asset visual
alignment and mouse/keyboard behavior still require native in-game verification.

## Original OL building and resource meshes (2026-10-26)

- Existing OL building types now resolve case-insensitively through
  `BuildingTypes::<type>`, then `<directory>/<basename>.ae` and the configured
  `Activity_Stand` LWS. There is no hard-coded Tool Store directory and no
  requirement that a standing building provide Raider `Activity_Route`.
- OL `PowerCrystal`, `Ore`, and `ProcessedOre` resolve to `MiscObjects::Crystal`,
  `Ore`, and `ProcessedOre` LWO basenames. Missing/corrupt assets report their
  path/OL identifier in the diagnostic status tooltip. The original DirectX
  `.x` fallback is explicitly unsupported; no substitute mesh is generated.
- Buildings/resources and Raiders share one decoded LWOB/LWS renderer, including
  material groups, per-corner UView UV seams, local-before-SharedObjects and
  mesh-local-before-SharedTextures resolution, parent hierarchy and pivot matrix.
  Nonzero AE `Scale` is applied before world BlockSize conversion (zero/missing
  is identity). `LOOPING` defaults true; false/no/off clamps the clip at its last
  frame. Loop wrapping now follows `Lws_SetTime`'s LastFrame boundary rather
  than the previous inclusive frame-count period. LWSFILE now follows the
  source's TRUE/YES/ON tokens: numeric `1` is not true (the previous native
  adapter accepted it); numeric/unknown LOOPING still defaults true. The current declared-LWS-FPS
  clock is retained; original game-tick/object-stat animation rates are pending.
- Powered crystals use `Main::PowerCrystalRGB` for both diffuse and emissive
  material channels, not an invented crystal color. Missing/invalid configured
  color is an explicit diagnostic rather than a guessed value.
- Real object models display on discovered tiles with diagnostic markers off,
  including after connected hidden-cavern reveal. Original OL identifiers and
  coordinates are retained. Missing/unsupported non-Raider models still require
  the explicit diagnostic switch to show their proxy. All model roots are
  ground-based; capsule/sphere offsets belong only to fallback proxy children.
  Existing Raider first-person eye height and tutorial camera targets are kept.

This is an **asset-loading/rendering milestone**, not a construction or economy
port. Building heading cardinalization at hidden-cavern exposure, transformed
`Shape` footprints (including repeated points marking paths), ground flattening,
collision, upgrades, teleports and building function remain unported. It does
not add bounding-box collision. Existing OL resources are drawn; CryOreMap
mining drops, pickup, delivery, stock counters and construction costs are not
fabricated. Non-Stand building activities, DirectX meshes, full retail material
semantics and gameplay animation rates remain outside this change.

Source: `Building.cpp:112–138`, `Containers.cpp:532–613`,
`Game.cpp:841–873`, `GameCommon.h:184–206`, `Lws.cpp:476–486`,
`GameState.cpp:412–413`, `Object.cpp:705–723,1065–1067,1182–1199`.
Synthetic config/WAD/LWOB/LWS regression coverage is added for mapping,
stand-only buildings, scale, looping, ordered component fallback, missing-asset
errors and marker-independent reveal rules; macOS CI additionally exercises the
shared SceneKit geometry, hierarchy and crystal materials, initial frame-zero
poses, Raider activity/selection ancestry, and preserved camera/proxy offsets. No retail files are
included. `git diff --check`, shell syntax checks and a text-equivalence check
of the extracted geometry/UV/pivot code passed locally. Swift tests are **not
locally run** (`swiftc: command not found`, exit 127); native build is **not
locally run** (requires macOS, exit 2). CI must establish compile/test results.
Actual Tool Store/ore/crystal appearance in the first mission has **not** been
validated with the user's retail assets on Apple Silicon.

## Initial original mission briefing (source integration, 2026-10-26)

The initial objective is now a separate full-mission input overlay, not a native
text alert or a NERP tutorial message. It loads the selected level's configured
`ObjectiveText` and `ObjectiveImage640x480` from the user's archives. `[Level01]`
is matched from `Levels::Level01`; body/BEGIN underscores remain literal, while
only the heading's CFG underscores become spaces. Lowercase `\n`/`\a`, blank
pages, section/prefix matching and original BEGIN placement follow Objective.cpp.
Missing optional ObjectiveText keeps a blank, dismissible initial state with a
visible diagnostic; a configured unreadable/malformed file reports a load error.
No missing narrative is invented.

Rendering uses MBriefFONT.bmp for the body and MBriefFONT2.bmp for title/BEGIN,
source text-window bounds, exact TextWindow wrapping/centering and last-whole-line
overflow. Panel transparency keys the palette-zero **color** by default (including
duplicate palette entries), or the explicit CFG RGB key; it is not black by
assumption. Page arrows use RGB black. Next is at (470,315); Previous is drawn
from Main::BackArrow at (130,315), while its hit rectangle uses the different
Main::BackButton640x480/RepeatButtonImage dimensions. The existing 640×480 HUD
transform is shared at normal, doubled, wide and tall window sizes. Missing
art is diagnosed; missing fonts use an explicitly diagnostic system-font fallback.

The bottom original message panel stays visible. Its configured
`TextMessages::Text_SpaceToContinue` text is shown while the briefing freezes
interface time when MessagePermit allows generic messages; a current NERP
message keeps precedence. The later
TextMessagesWithImages override supplies its original text, but its image/SFX
variant remains unimplemented and explicitly diagnosed. No English prompt is
hardcoded. The lower panel retains its previously documented provisional layout.

Opening held/queued clicks and Space are seeded; the opening release is drained
before entering the script loop. Once visible, the original NERPs VM **still
executes every tick with zero elapsed interface time**. Actual overlay visibility
backs retail `GetObjectiveShowing` at function **0x32 / decimal 50**, zero args.
Initial dismissal signals the existing BF/C0 ObjectiveSwitch latch once; C1 is
not an alias and unknown reached opcodes still halt. Diagnostic VM pause stays
separate. Cave selection, command actions, camera controls, SceneKit actions and
model animation are blocked/frozen during the briefing. Resume resets clock
baselines and rebases model epochs rather than charging the frozen interval.

Speech resolves `Stream_Objective_<full level identifier>` through the existing
Samples catalog and original WAV resolver. It is attempted once, not on page
changes; missing/undecodable speech reports a diagnostic, with no replacement
recording. Dismissal stops speech and starts cave ambience/music once. Mission
exit cancels the overlay and all mission audio without signaling dismissal;
queued movement/drill completions are invalidated. The user's music-off
preference is preserved. Space repeats, focus loss, Command-modified release,
intermediate outside clicks, last-page Previous, final release and closing-click
consumption have synthetic regression coverage.

Validation in this Linux cloud checkout: `git diff --check`, shell syntax, all
8 soundtrack-import Python tests (including local FFmpeg paths), and all 10
window-capture safety Python tests passed. A source-algorithm differential check
covered 615,857 synthetic TextWindow wrap cases. Portable Swift, ARM64/AppKit and
SceneKit execution are **not locally verified**: `swiftc` is absent and build.sh
requires macOS. The portable tests and dedicated synthetic AppKit palette/font/
input renderer tests are wired into the existing hosted workflow; that exact
revision still needs its hosted run. The user's private original 118s retail
briefing frame was visually inspected as a reference only, not copied into the
repository. No original game/audio bytes or generated art/narration are included.

Still outside this change: mission completion/failure/replay screens, Chief LWS
advisor animation, objective economy/simulation, original prompt image/SFX,
full retail render fidelity and native real-asset gameplay/audio verification.

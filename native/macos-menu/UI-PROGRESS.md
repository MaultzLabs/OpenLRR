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

# Original LEGO Rock Raiders (Windows 1999) — native port visual and interaction target

This project ports **the original Windows PC game**, not the different
PlayStation title or a visually modernized remake. We do not commit original
media. All rendered retail art and sounds must come from the user's own game
installation.

## Primary video evidence

- [1999 Windows PC full walkthrough — Ringtail](https://www.youtube.com/watch?v=2jQ93-cdJeY)
  captured at the original **640×480** resolution at **60 FPS**, with 8
  tutorials and 25 missions. Reference timestamps:
  - [05:59 — Moving Rock Raiders](https://www.youtube.com/watch?v=2jQ93-cdJeY&t=359s):
    basic walk-to-target controls and in-game interface.
  - [10:16 — Rock Types and Drilling](https://www.youtube.com/watch?v=2jQ93-cdJeY&t=616s):
    drillable wall appearance and digging commands.
  - [12:27 — Building Rock Raider HQ](https://www.youtube.com/watch?v=2jQ93-cdJeY&t=747s):
    object/model scale, ground textures, power paths and buildings.
  - [47:53 — Defending Rock Raider HQ](https://www.youtube.com/watch?v=2jQ93-cdJeY&t=2873s):
    **exact training mission** shown by the Mac prototype user's screenshot.
  - [55:07 — Driller Night](https://www.youtube.com/watch?v=2jQ93-cdJeY&t=3307s):
    first main-game mission.
- [PC first mission screenshot, MobyGames](https://www.mobygames.com/game/2993/lego-rock-raiders/screenshots/windows/353968/)
  at the original 640×480 aspect ratio.
- [PC gameplay/gallery image, RRU](https://rockraidersunited.com/guides/back-to-basics-without-sonic-blasters-r16/)
  demonstrates the retail interface and underground structures.

## Original asset references

- [RRU PC file tree](https://kb.rockraidersunited.com/LEGO_Rock_Raiders_PC_file_tree):
  `Data/World/WorldTextures/RockSplit/Rock##.BMP`,
  `IceSplit/ICE##.BMP`, `LavaSplit/LAVA##.BMP`, original
  `World/ProMeshes`, minifigures, and buildings.
- [Original texture IDs](https://github.com/MaultzLabs/OpenLRR/blob/lab-native-macos-menu-v1/src/openlrr/game/GameCommon.h):
  the `SurfaceTexture` enum specifies ground=0, solid=5,
  crystal wall=0x20, ore wall=0x40, water=0x45, lava=0x46, etc.
- [RRU terrain map format](https://kb.rockraidersunited.com/Terrain_map):
  .MAP is the source of height, exposed/hidden cave, and terrain types.
- [RRU config documentation](https://kb.rockraidersunited.com/Config_documentation):
  retail defaults are `BlockSize 40`, `RoughLevel 6`,
  `DigDepth 40`, `RoofHeight 40`. The actual `Lego.cfg` values override
  defaults where specified.
- [RRU object-list format](https://kb.rockraidersunited.com/Object_List_file):
  .ol placements specify original Rock Raider/building/camera positions and
  headings. Retail models and animations use .ae/.lwo/.lws/.x.

## Acceptance criteria (in priority order)

1. **One game window.** Menu > briefing > mission > pause/return all happen
   in the same native macOS window. Back returns to the original menu; opening
   a mission must never create an independent new NSWindow.
2. **Authentic initial visuals.** Discovered cavern and adjacent rock
   boundaries appear with actual installed Rock/Ice/Lava textures; hidden map
   is not shown as a full flat colored plate. Match the original viewport
   camera distance, roof/wall height, and darkness/fog as closely as possible.
3. **Retail in-game HUD.** Use supplied game's BMP and animation assets.
   Do not substitute an unlabelled toy interface or claim bare diagnostic
   buttons are retail UI.
4. **Original models, not capsules.** Port original .ae animation controls
   and model geometry from user-owned archives; debug proxies may only
   remain while flagged as previews.
5. **First real tutorial gameplay.** Select a Rock Raider, right-click to
   move, drill accessible wall, move rubble/resources, and complete the
   scripted tutorial with NERP objectives and result screens.
6. **Verified behavior and performance.** Every source change has portable
   tests where appropriate; macOS ARM64 CI must compile. Mac user screenshot
   or screen recording is required before claiming the retail appearance has
   been reproduced or a level is playable at 60 visible FPS.

## Current state

Native SceneKit terrain derived from real .MAP data; some original .BMP
textures are now loaded; .ol placements and conservative movement routing
exist. **No original animated minifigure, original HUD, driller, inventory,
NERP execution, or complete level has been ported yet.** This is still a
working prototype, not the full retail game.

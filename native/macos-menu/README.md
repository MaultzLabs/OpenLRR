# Original Rock Raiders — Native macOS prototype (experimental)

**This is a native application prototype, not yet a playable game.** It does
not use Wine, the original Windows EXE, DirectDraw, or any injected DLLs.

## Source-grounded features developed

- Read-only WWAD parser based on `src/openlrr/engine/core/Wad.cpp`.
  Loads only explicitly selected `LegoRR0.wad` plus adjacent `LegoRR1.wad`.
  Higher-numbered WAD overrides lower-numbered WAD entries.
- `Lego.cfg` parser preserving the game's nested menus, settings, colon-separated
  original front-end items, original coordinates and display strings.
- Native AppKit window with original `Interface/FrontEnd/MenuBGpic.bmp`,
  per-menu `MenuImage` BMPs, configured bitmap overlays, and mouse-driven
  navigation for actual `Next` items defined in `Menu::MainMenuFull`.
  Banner text honors the retail `AutoCenter` flag, and unpositioned menu
  images draw at their original pixel dimensions instead of being stretched.
  The game viewport stays at 4:3, separately centered above the utility bar.
- Original sprite-font format: indexed 8-bit BMP, 10 columns by 19 rows,
  pen-zero transparency and pen-255 trailing width markers, following
  `src/openlrr/engine/drawing/Fonts.cpp`. Native system font is only a fallback.
- Parses original mission and tutorial ordering from `Main/StartLevel`,
  `TutorialStartLevel`, and the `NextLevel` chains.
- Reads original `.map` binary terrain/height/predug arrays without altering
  them, using the documented `MAP ` header and little-endian 16-bit cells.
- Experimental macOS playback of the **configured original front-end** `AmbientMusicLoop` WAV via AVFoundation, sourced from the selected WADs or adjacent `Data/` files. No Windows music DLLs, audio extraction or bundled tracks. Playback requires macOS testing; the separate CD/OGG *in-level* soundtrack is not yet implemented.
- Portable tests use **synthetic bytes only**. No copyrighted assets in GitHub.

## Actual verified scope

The portable archive, config, front-end, map and font decoding tests **compile
and run on Linux** with Swift 6 using synthetic fixtures. The native AppKit
prototype has been built and launched on an Apple Silicon Mac by the project
owner using their own original WAD files. The original menu artwork and some
navigation display, but the layout and controls are incomplete; original audio
playback is newly added and **not yet verified on a Mac**. Frame rate, 3D
rendering, gameplay, and missions have not been validated.

The framework for `Next` navigation exists, but the rest of the original menu
items remain intentionally non-operational; no fake game or save actions.
Native 3D graphics, AI, level runtime, and executable NERPs have **not** been ported. WAV decoding and initial native menu audio playback are experimental.

## Building locally when you are ready

Requires Apple Silicon and Apple Command Line Tools / Xcode.

```
cd native/macos-menu
bash test.sh
bash build.sh
open build/RockRaidersNativeMenu.app
```

Select `LegoRR0.wad` (or its adjacent `LegoRR1.wad`) **once**. After a
successful load, the selected file's local path is saved in macOS UserDefaults,
and the viewer automatically reopens those WADs on future launches. The file
picker remains available if you move the installation or want to change games.
The other neighboring WAD is loaded automatically when present. The audio
status under the window controls reports the configured ambient sound filename
if native playback cannot locate it. Do not upload those private original
assets or extracted files to the public GitHub repository.

Only creates build files under `native/macos-menu/build`. Does not change
original installation, the separate Wine TEST app, or save files.

## Source references

- OpenLRR C++: `src/openlrr/game/front/FrontEnd.cpp` (`Front_LoadMenuSet`,
  `Front_Menu_LoadMenuImage`, `Front_Menu_Update`), `engine/drawing/Fonts.cpp`,
  `engine/core/Wad.cpp`.
- RRU Knowledge Base: WWAD file format, `Lego.cfg`, MAP file,
  [original file tree](https://kb.rockraidersunited.com/LEGO_Rock_Raiders_PC_file_tree).

This is intentionally a **single** native prototype under an isolated branch,
not an independent testing laboratory or a replacement for your working game.

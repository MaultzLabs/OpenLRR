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
- Original sprite-font format: indexed 8-bit BMP, 10 columns by 19 rows,
  pen-zero transparency and pen-255 trailing width markers, following
  `src/openlrr/engine/drawing/Fonts.cpp`. Native system font is only a fallback.
- Parses original mission and tutorial ordering from `Main/StartLevel`,
  `TutorialStartLevel`, and the `NextLevel` chains.
- Reads original `.map` binary terrain/height/predug arrays without altering
  them, using the documented `MAP ` header and little-endian 16-bit cells.
- Portable tests use **synthetic bytes only**. No copyrighted assets in GitHub.

## Actual verified scope

The portable archive, config, front-end, map and font decoding tests **compile
and run on Linux** with Swift 6. No original WADs were available during these
remote tests. The AppKit code has been parsed, but **has not yet compiled or run
on real macOS** because GitHub's free Mac jobs were cancelled before acquiring
runners. Original image rendering, controls, menu positions, audio, performance,
3D gameplay and missions require testing before any working-game claims.

The framework for `Next` navigation exists, but the rest of the original menu
items remain intentionally non-operational; no fake game or save actions.
Native 3D graphics, AI, level runtime, NERPs and sound have **not** been ported.

## Building locally when you are ready

Requires Apple Silicon and Apple Command Line Tools / Xcode.

```
cd native/macos-menu
bash test.sh
bash build.sh
open build/RockRaidersNativeMenu.app
```

Select `LegoRR0.wad` (or its adjacent `LegoRR1.wad`). The viewer loads the
other neighboring WAD automatically when present. Do not upload those private
original assets or extracted files to the public GitHub repository.

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

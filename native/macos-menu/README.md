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
- Experimental macOS playback of the original `SFX_AmbientMusicLoop` sound using
  AVFoundation. Resolves configured WAVs from the WADs or loose
  `Data/Sounds/Streamed/` files; falls back to the original `Atmosdel.wav`
  when present. A "Locate Sounds…" picker can select a separate user-owned
  directory once, remembers the path, and shows persistent playback diagnostics.
  No Windows music DLLs or copyrighted WAVs are bundled.
- Optional offline media converter (`tools/convert-original-media.sh`) using
  local FFmpeg: Indeo/other legacy `.avi` -> H.264/AAC `.mp4`, original
  `Trackxx.ogg` music -> AAC `.m4a`. Keeps the originals unchanged.
  Converted media is **not yet connected** to cutscene/gameplay playback.
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

### Restoring the authentic main-menu ambience

The original menu sound is a **WAV**, not a CD track. The Rock Raiders United
[Atmosdel and Stats.wav download](https://rockraidersunited.com/files/lego_rock_raiders/resources/atmosdel-and-statswav-r323/)
contains the original menu and score audio. RRU instructs users to extract it
into `Data/Sounds/Streamed` (rather than into either WAD). Some extracted
retail installations contain corrupted copies.

The native app now searches `Data/Sounds/Streamed`, `Data/Sounds` and the
original sound path in `Lego.cfg`. If your WADs are stored elsewhere, extract
the RRU ZIP locally **after reviewing RRU's download terms**, open our app,
click **Locate Sounds…** and choose the extracted folder containing the WAVs.
The app remembers that folder; no repeated selection is necessary. The
original assets stay local, no upload to GitHub and no changes to the Wine game.

The separate [RRU Music without CD fix](https://rockraidersunited.com/guides/lrr-music-without-cd-fix-r11/)
intercepts *Windows* `winmm.dll` CD-audio calls and maps tracks onto
`Music/Trackxx.ogg` files. Those DLLs must **not** be copied into this native
Mac app. Native soundtrack playback has to use an appropriate macOS decoder
(or optional local conversion), and will be wired up with gameplay.

### Optional local audio/video conversion

Requires FFmpeg installed on your Mac (e.g. `brew install ffmpeg`). The
converter performs no network requests and never overwrites originals:

```bash
cd native/macos-menu
bash tools/convert-original-media.sh "/path/to/your/original/Data/AVI"
bash tools/convert-original-media.sh "/path/to/your/original/Music"
```

The output is kept privately under
`~/Library/Application Support/RockRaidersNativeMenu/ConvertedMedia`.
Converting a legacy AVI container is **not** the same as translating Windows
program code. Modern macOS video players can use the converted MP4 when
cutscene playback is implemented. WAV files are played directly and do not
need MP4 conversion.

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

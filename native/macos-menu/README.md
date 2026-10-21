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
- Parses original mission/tutorial order (`NextLevel`) and the *actual*
  `LevelLinks` mission map traversal, rendering original `MenuBMP` variants
  for initially open/locked missions and training missions. This selection
  does **not** launch the mission runtime.
- Reads original PC `Saves/0.sav` through `Saves/4.sav` **without modifying
  them**. Validates the 0xb0-byte save header and 0x3190-byte reward records,
  displays the five visible save slots and derives mission unlocks from
  completed-level flags when an existing slot is selected.
- Resolves the original `SurfaceMap`, `TerrainMap`, `PredugMap` and other
  world assets, plus object lists and NERP file paths, from each level's real
  `Lego.cfg` section. Reads binary `.map` terrain/height/predug arrays
  without altering them using the documented `MAP ` header and little-endian
  16-bit cells.
- **First interactive mission terrain inspection:** a native AppKit tile map
  using the original level's three essential MAP files. Click `First Level`
  or an unlocked original mission-map icon; pan by dragging/WASD/arrow keys,
  scroll or +/- to zoom, inspect original tile types and heights by clicking,
  press R to recenter and Escape to close. This diagnostic top-down scene is
  **not yet a playable 3D level**: it has no object/unit rendering, drilling,
  goals, camera engine, or original terrain textures. Original files stay read-only.
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

The portable archive, config, front-end, map, save, and mission-link parsing
tests compile and run on Linux using synthetic fixtures. The native AppKit
prototype has been launched on the owner's Apple Silicon Mac using their own
WAD files. A standard hosted macOS Actions runner also **successfully compiled**
the ARM64 AppKit menu, including the new graphical mission-selection and save
slot integration, without any original WADs in CI. Runtime behavior of the
new mission/save screens is still unverified, as are visible FPS, 3D gameplay,
and actual mission launching.

The framework for `Next` navigation exists and the original mission and save
menus can now present decoded game data. Selecting a save is read-only. Clicking
a mission opens its authentic terrain files in the new overhead inspection
window; it cannot launch gameplay yet. Native 3D graphics,
camera/movement, AI, drilling/building, object simulation, objectives and
executable NERPs have **not** been ported. WAV decoding and native menu audio
playback are experimental.

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

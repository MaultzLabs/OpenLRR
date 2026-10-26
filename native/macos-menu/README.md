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
- **Original scrolling mission selection:** honors the retail menu
  `CanScroll` configuration, uses `Front_Menu_UpdateMousePosition`'s
  original top/bottom mouse position scrolling curve and clamps at the
  image bounds. Mission icons travel with the map; mouse wheel also works.
  Uses `Pointers::Pointer_Standard` BMP from the installed original WAD
  as a custom transparent cursor in menus and both mission views, with a
  system-arrow fallback when the original asset is absent.
- **Original Quit Game Yes/No behavior:** original `MainMenuFull` quit
  confirmation screen is found from the installed Lego.cfg, with its normal
  image/text buttons. The configured terminal Yes trigger quits; No navigates
  back. Cmd-Q, toolbar Quit and Mac window close also request in-game
  confirmation. If the WAD isn't loaded, a standard Mac Yes/No alert is used.
- **Retail Boulder rock wipe (experimental):** interprets the original
  `Menu::MenuWipe` LWSC1 scene, animates its real `.lwo` Boulder parts in
  SceneKit from the user's WAD, and changes menu pages halfway through the
  original wipe. If a supported scene/mesh isn't available, navigation
  remains functional without a made-up substitute animation. Original
  motion smoothing, material mapping and WAD rendering remain unverified.
- **More authentic button input:** original BMP button positions respect
  `AutoCenter`, and selections play the actual configured `SFX_Okay` WAV
  when available, without interrupting the looping front-end ambience.
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
- **Single-window native mission view:** clicking `First Level` or an
  unlocked original mission icon replaces the menu inside the **existing
  native window**, rather than spawning a second Mac window. A visible
  `← Back to Main Menu` button and Escape return to the menu. Resize to make
  room for the scene; your previous menu window dimensions are restored.
- **First 3D cave with original terrain BMPs:** decodes the actual level
  height, terrain, and predug MAP data, but draws only exposed caverns and
  adjacent walls (not a full flat plate of hidden rock). Loads the original
  Rock/Ice/Lava biome `World/WorldTextures/*Split/*##.BMP` images from
  the user's WAD files and applies per-tile repeating UVs. Uses original
  default level height and wall scaling as the starting geometry baseline.
  Switch to `2D MAP` for raw map inspection. Per-wall transitions, roof,
  shadows and model detail are still incomplete.
- **Level loading regression corrected:** `Levels::Level01::TextureSet`
  can contain colon-separated original texture descriptors. It is not an
  ordinary file path, and no longer triggers a false "unsafe TextureSet"
  error. Actual referenced map/object/script paths still undergo traversal
  and malformed-filename protection.
- **Read-only classic LightWave `.lwo` decoder:** validates the original
  `FORM/LWOB` format with `PNTS`, `SRFS`, and `POLS` chunks, bounds checks,
  triangle fan conversion and basic detail polygons. The new `LWSC 1` parser
  reads scene objects and motion channels for the original menu rock wipe.
  Assembly and animation of full character/building models are not yet ported.
- **Retail OL object placement:** parses the level's original text `.ol`
  file with the actual `ObjectN { type, xPos, yPos, heading }` entries.
  The first TVCamera guides the initial viewport; visible Rock Raiders
  (type `Pilot`) are shown as **yellow debug capsules**, and other exposed
  placements as turquoise debug spheres, **not** original character or
  building models. Select an on-foot yellow Raider and click a discovered
  passable cavern tile to preview four-way walking. Solid/hidden terrain
  and lava/water are blocked. This is the first *movement prototype*;
  collisions, AI, original character animations, model meshes, drilling,
  vehicle movement, resource collection and mission objectives remain unported.
  All original files and saved games remain read-only.
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

Most portable archive, config, front-end, map, save and mission-link
parsing tests have previously passed on Linux with synthetic fixtures.
The newest quit/rock-wipe batch exposed a zero-item menu iteration trap, which
has been fixed in source; a passing combined run for the *current* revision
has not yet been confirmed. The native AppKit
prototype has been launched on the owner's Apple Silicon Mac using their own
WAD files. A standard hosted macOS Actions runner has successfully compiled the ARM64
AppKit and SceneKit prototype without any original WADs in CI. The owner has
visually confirmed that the initial 3D debug-map build was far from the retail
game. Original WAD rendering of the new single-window/bitmap-texture revision
still needs a screenshot check; 60 visible FPS and gameplay are unverified.

The framework for `Next` navigation exists and the original mission and save
menus can now present decoded game data. Selecting a save is read-only.
Selecting a mission opens native 3D terrain from its original MAP files
and can show original OL spawn positions with prototype click-to-move pathing
on exposed terrain. The proxies and movement are diagnostic, not retail
character meshes or simulated Rock Raider gameplay. The original Direct3D renderer, precise retail material transitions, detailed
wall/roof meshes, the in-game HUD, minifigure models/animations, collision,
AI, drilling/building, vehicle systems, inventory, objective completion and
executable NERPs have **not** been ported. Native menu audio remains experimental.
See [ORIGINAL_PC_REFERENCE.md](ORIGINAL_PC_REFERENCE.md) for verified Windows
gameplay recording timestamps and specific restoration criteria.

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


### Import the RRU mission soundtrack into the native app

After downloading `LRR_Music_Fix.zip` from the RRU Music Fix page, run:

```bash
python3 tools/import-mission-music.py "$HOME/Downloads/LRR_Music_Fix.zip"
```

Requires local FFmpeg (`brew install ffmpeg`). The importer reads only named
Track00–98 OGG audio, converts it to native M4A, and installs it in the app's
existing discovery cache. It never extracts DLLs or changes the Wine game.
Existing converted tracks are kept. Return to the menu and enter a mission
again to discover the imported tracks. The download itself requires accepting
RRU's terms; no soundtrack files are included in this repository.

The model texture branch reads original LWOB TIMG/TSIZ/TCTR/TFLG projection
and UView v2 `.uv` corner coordinates, including shared-vertex UV seams.
Original model BMPs resolve beside the mesh and in Main::SharedTextures.
Terrain wall faces retain their rock/seam material; exposed dry ground uses
floor material. Full retail wall transitions, power paths, texture animation,
color keys, and real-asset visual verification remain pending.

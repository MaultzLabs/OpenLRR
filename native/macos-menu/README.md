# Native macOS menu background — experimental

This is **the first native asset-loading milestone**, not a playable port.

The prototype reads the original Rock Raiders menu image from the user's local
`LegoRR0.wad` and draws it in a real macOS AppKit window. It does not use
Wine, DirectDraw, dgVoodoo, the original Windows EXE, or injected DLLs.

## Implemented

- Portable read-only WWAD parser: validates the WWAD header, reads the two
  filename tables and 16-byte entry descriptors, normalizes Windows paths,
  checks file bounds, and extracts uncompressed entries into memory.
- Swift tests using entirely synthetic archive bytes; no game assets or
  user files are checked into GitHub.
- Native Apple Silicon AppKit viewer of
  `Interface/FrontEnd/MenuBGpic.bmp` via macOS ImageIO.
- Open WAD, About, and Quit controls; aspect-ratio-preserving rendering;
  read-only asset access; explicit errors for malformed archives.

## Verified so far

- WWAD parser compiles and the synthetic portable tests pass on Linux.
- The macOS AppKit code has only been syntax-parsed without macOS frameworks.
  **It has not yet compiled or run on a Mac**, and no original WAD has yet
  been tested with this new prototype.

## Build and run (later, when you want to test on your Mac)

1. Use an isolated copy of the repository branch
   `lab-native-macos-menu-v1`. Your working game remains untouched.
2. Install Apple Command Line Tools / Xcode if needed.
3. From `native/macos-menu` run `bash test.sh` and `bash build.sh`.
4. Open `build/RockRaidersNativeMenu.app`. Select your own `LegoRR0.wad`
   using the file chooser. The app reads but does not modify or upload it.

Minimum target: macOS 12, Apple Silicon arm64. Built output stays within
this project folder; the script does not install or change existing apps.

## Scope still missing

This app only displays the authentic menu **background image**. It does not
yet have original menu interaction, sound, video, input/game state, 3D rendering,
or playable missions. It is not a faithful reproduction of the complete menu,
and no visible FPS performance claims have been made.

Compressed RNC WAD entries are rejected explicitly (original game WADs
normally contain uncompressed entries).

The next milestone is **compile and run this actual AppKit app on a Mac and
verify that the original menu image renders correctly**. The native work stays
separate from the existing Sikarugir/Wine test installation.

### Safety

Never upload or commit `LegoRR0.wad`, `LegoRR1.wad`, extracted game
art, licensed music, or private local filesystem paths to the public repo.

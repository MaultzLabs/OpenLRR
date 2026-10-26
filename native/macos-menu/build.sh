#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo 'Native AppKit build requires macOS. Run bash test.sh for portable core tests.' >&2
  exit 2
fi
command -v xcrun >/dev/null || { echo 'Apple Command Line Tools/Xcode needed.' >&2; exit 2; }
out="$PWD/build/RockRaidersNativeMenu.app"
mkdir -p "$out/Contents/MacOS"
cat > "$out/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>RockRaidersNativeMenu</string>
<key>CFBundleIdentifier</key><string>com.maultzlabs.rockraiders-native-menu-prototype</string>
<key>CFBundleName</key><string>Rock Raiders Native Menu Prototype</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>12.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
xcrun swiftc -O -target arm64-apple-macos12.0 -framework AppKit -framework ImageIO -framework AVFoundation -framework SceneKit \
  Sources/WadArchive.swift Sources/GameResources.swift Sources/LegoConfig.swift \
  Sources/MenuDefinition.swift Sources/LevelCatalog.swift Sources/MissionSelection.swift \
  Sources/MapFile.swift Sources/LevelRuntimeResources.swift Sources/LevelWorld.swift Sources/NativeTerrainMesh.swift Sources/NativeLevelNavigation.swift Sources/NativeExcavationState.swift Sources/NativeDynamicCollision.swift Sources/NativeFirstPersonController.swift Sources/OriginalTerrainTextureCatalog.swift Sources/LightWaveObject.swift Sources/LightWaveScene.swift \
  Sources/PalettedBMP.swift Sources/OriginalFontLayout.swift Sources/OriginalMenuScroll.swift Sources/OriginalPointerAsset.swift Sources/WavePCM.swift \
  Sources/SoundSampleCatalog.swift Sources/NERPsScript.swift Sources/NERPsRuntime.swift Sources/NativeNERPsMessageFile.swift Sources/NativeTutorialInputPolicy.swift Sources/NativeNERPsGameState.swift Sources/OriginalObjectList.swift Sources/OriginalSaveFile.swift Sources/OriginalAudioFileLocator.swift \
  Sources/OriginalRaiderModel.swift Sources/OriginalMenuAudio.swift Sources/OriginalMacCursor.swift Sources/NativeRockWipeView.swift Sources/OriginalMissionMessageUI.swift Sources/NativeLevelView.swift Sources/NativeLevel3DView.swift Sources/NativeMenu.swift \
  -o "$out/Contents/MacOS/RockRaidersNativeMenu"
# Embed locally installed mission music in this private app build. Audio is
# never downloaded by the build or committed to the source repository.
music_cache="$HOME/Library/Application Support/RockRaidersNativeMenu/ConvertedMedia/Music"
mkdir -p "$out/Contents/Resources/Music"
for track in "$music_cache"/Track[0-9][0-9].m4a; do
  [[ -f "$track" ]] || continue
  [[ "$(basename "$track")" == "Track99.m4a" ]] && continue
  cp "$track" "$out/Contents/Resources/Music/"
done
/usr/bin/codesign --force --sign - "$out"
printf 'Compiled native ARM64 app: %s\n' "$out"
printf 'Open locally: open "%s"\n' "$out"

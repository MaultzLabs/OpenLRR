#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
tmp1="$(mktemp /tmp/openlrr-wad-test.XXXXXXXX)"
tmp2="$(mktemp /tmp/openlrr-core-test.XXXXXXXX)"
tmp3="$(mktemp /tmp/openlrr-wav-test.XXXXXXXX)"
tmp4="$(mktemp /tmp/openlrr-nerps-test.XXXXXXXX)"
tmp5="$(mktemp /tmp/openlrr-audio-file-test.XXXXXXXX)"
tmp6="$(mktemp /tmp/openlrr-mission-test.XXXXXXXX)"
tmp7="$(mktemp /tmp/openlrr-save-test.XXXXXXXX)"
tmp8="$(mktemp /tmp/openlrr-world-map-test.XXXXXXXX)"
tmp9="$(mktemp /tmp/openlrr-ol-test.XXXXXXXX)"
tmp10="$(mktemp /tmp/openlrr-lightwave-test.XXXXXXXX)"
tmp11="$(mktemp /tmp/openlrr-lightwave-scene-test.XXXXXXXX)"
tmp12="$(mktemp /tmp/openlrr-texture-set-test.XXXXXXXX)"
tmp13="$(mktemp /tmp/openlrr-nerps-runtime-test.XXXXXXXX)"
tmp14="$(mktemp /tmp/openlrr-nerps-game-state-test.XXXXXXXX)"
tmp15="$(mktemp /tmp/openlrr-raider-model-test.XXXXXXXX)"
trap 'rm -f "$tmp1" "$tmp2" "$tmp3" "$tmp4" "$tmp5" "$tmp6" "$tmp7" "$tmp8" "$tmp9" "$tmp10" "$tmp11" "$tmp12" "$tmp13" "$tmp14" "$tmp15"' EXIT
swiftc -O Sources/WadArchive.swift Tests/WadArchiveTests.swift -o "$tmp1"
"$tmp1"
swiftc -O Sources/WadArchive.swift Sources/GameResources.swift \
  Sources/LegoConfig.swift Sources/MenuDefinition.swift \
  Sources/LevelCatalog.swift Sources/MapFile.swift Sources/PalettedBMP.swift \
  Sources/OriginalFontLayout.swift Sources/OriginalMenuScroll.swift Sources/OriginalPointerAsset.swift \
  Sources/WavePCM.swift Sources/SoundSampleCatalog.swift \
  Tests/NativeCoreTests.swift -o "$tmp2"
"$tmp2"
swiftc -O Sources/WavePCM.swift Tests/WavePCMTests.swift -o "$tmp3"
"$tmp3"
swiftc -O Sources/WadArchive.swift Sources/GameResources.swift \
  Sources/LegoConfig.swift Sources/NERPsScript.swift \
  Tests/NERPsScriptTests.swift -o "$tmp4"
"$tmp4"
swiftc -O Sources/OriginalAudioFileLocator.swift Tests/OriginalAudioFileLocatorTests.swift -o "$tmp5"
"$tmp5"

# Converter is optional on macOS; syntax/help must work without FFmpeg.
bash -n tools/convert-original-media.sh
bash tools/convert-original-media.sh --help >/dev/null

swiftc -O Sources/LegoConfig.swift Sources/LevelCatalog.swift \
  Sources/MissionSelection.swift Tests/MissionSelectionTests.swift -o "$tmp6"
"$tmp6"

swiftc -O Sources/OriginalSaveFile.swift Tests/OriginalSaveFileTests.swift -o "$tmp7"
"$tmp7"

swiftc -O Sources/WadArchive.swift Sources/GameResources.swift \
  Sources/LegoConfig.swift Sources/MapFile.swift Sources/LevelRuntimeResources.swift \
  Sources/LevelWorld.swift Sources/NativeTerrainMesh.swift Sources/NativeLevelNavigation.swift \
  Sources/OriginalTerrainTextureCatalog.swift Tests/LevelRuntimeResourcesTests.swift -o "$tmp8"
"$tmp8"

swiftc -O Sources/WadArchive.swift Sources/GameResources.swift \
  Sources/LegoConfig.swift Sources/MapFile.swift Sources/LevelRuntimeResources.swift \
  Sources/OriginalObjectList.swift Tests/OriginalObjectListTests.swift -o "$tmp9"
"$tmp9"

swiftc -O Sources/LightWaveObject.swift Tests/LightWaveObjectTests.swift -o "$tmp10"
"$tmp10"

swiftc -O Sources/LightWaveScene.swift Tests/LightWaveSceneTests.swift -o "$tmp11"
"$tmp11"

swiftc -O Sources/WadArchive.swift Sources/GameResources.swift \
  Sources/OriginalTerrainTextureCatalog.swift Sources/LevelWorld.swift \
  Sources/LevelRuntimeResources.swift Sources/LegoConfig.swift \
  Sources/LevelCatalog.swift Sources/MapFile.swift \
  Tests/OriginalTerrainTextureCatalogTests.swift -o "$tmp12"
"$tmp12"

# Execute a simulated NERPs mission bytecode tick with native callbacks.
# Original executable function pointers and retail assets are NEVER used.
swiftc -O Sources/WadArchive.swift Sources/GameResources.swift \
  Sources/LegoConfig.swift Sources/NERPsScript.swift \
  Sources/NERPsRuntime.swift Tests/NERPsRuntimeTests.swift -o "$tmp13"
"$tmp13"

# Persistent NERPs game state from original C++ callbacks; no retail assets.
swiftc -O Sources/WadArchive.swift Sources/GameResources.swift \
  Sources/LegoConfig.swift Sources/NERPsScript.swift \
  Sources/NERPsRuntime.swift Sources/NativeNERPsMessageFile.swift \
  Sources/NativeTutorialInputPolicy.swift Sources/NativeNERPsGameState.swift \
  Tests/NativeNERPsGameStateTests.swift -o "$tmp14"
"$tmp14"

# Original Raider activity references and original mesh/scene parsers.
swiftc -O Sources/WadArchive.swift Sources/GameResources.swift Sources/LegoConfig.swift \
  Sources/LightWaveObject.swift Sources/LightWaveScene.swift Sources/OriginalRaiderModel.swift \
  Tests/OriginalRaiderModelTests.swift -o "$tmp15"
"$tmp15"

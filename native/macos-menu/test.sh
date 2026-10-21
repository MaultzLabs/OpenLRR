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
trap 'rm -f "$tmp1" "$tmp2" "$tmp3" "$tmp4" "$tmp5" "$tmp6" "$tmp7" "$tmp8" "$tmp9"' EXIT
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

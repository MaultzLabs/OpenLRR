#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
tmp1="$(mktemp /tmp/openlrr-wad-test.XXXXXXXX)"
tmp2="$(mktemp /tmp/openlrr-core-test.XXXXXXXX)"
tmp3="$(mktemp /tmp/openlrr-wav-test.XXXXXXXX)"
trap 'rm -f "$tmp1" "$tmp2" "$tmp3"' EXIT
swiftc -O Sources/WadArchive.swift Tests/WadArchiveTests.swift -o "$tmp1"
"$tmp1"
swiftc -O Sources/WadArchive.swift Sources/GameResources.swift \
  Sources/LegoConfig.swift Sources/MenuDefinition.swift \
  Sources/LevelCatalog.swift Sources/MapFile.swift Sources/PalettedBMP.swift \
  Sources/WavePCM.swift Sources/SoundSampleCatalog.swift \
  Tests/NativeCoreTests.swift -o "$tmp2"
"$tmp2"
swiftc -O Sources/WavePCM.swift Tests/WavePCMTests.swift -o "$tmp3"
"$tmp3"

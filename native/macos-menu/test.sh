#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
output="$(mktemp /tmp/openlrr-wad-tests.XXXXXXXX)"
trap 'rm -f "$output"' EXIT
swiftc -O Sources/WadArchive.swift Tests/WadArchiveTests.swift -o "$output"
"$output"

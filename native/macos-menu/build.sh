#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo 'This AppKit build requires macOS. Run ./test.sh for portable WAD tests.' >&2
  exit 2
fi
command -v xcrun >/dev/null || { echo 'Install Apple Command Line Tools (xcode-select --install)' >&2; exit 2; }
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
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>12.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
xcrun swiftc -O -target arm64-apple-macos12.0 -framework AppKit -framework ImageIO \
    Sources/WadArchive.swift Sources/NativeMenu.swift \
    -o "$out/Contents/MacOS/RockRaidersNativeMenu"
/usr/bin/codesign --force --sign - "$out"
printf 'Built native Apple Silicon prototype: %s\n' "$out"
printf 'To open: open "%s"\n' "$out"

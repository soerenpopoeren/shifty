#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Builds Shifty.app (only the Xcode Command Line Tools are needed).
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Shifty.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 \
  -target "$(uname -m)-apple-macos14.0" \
  -o "$APP/Contents/MacOS/Shifty" \
  Sources/*.swift

cp Info.plist "$APP/Contents/Info.plist"

# Translated permission prompts (Bluetooth, local network)
cp -R Resources/*.lproj "$APP/Contents/Resources/"

# App icon from Assets/AppIcon.png (ideally 1024×1024) in all sizes
if [[ -f Assets/AppIcon.png ]]; then
  ICONSET=build/AppIcon.iconset
  rm -rf "$ICONSET"; mkdir -p "$ICONSET"
  # macOS grid: the icon is 824 px and sits centered in 1024 px with a transparent margin,
  # otherwise it looks bigger than other apps in the Dock. The original in Assets stays unchanged.
  GRID=build/AppIcon-grid.png
  sips -Z 824 Assets/AppIcon.png --out "$GRID" >/dev/null
  sips --padToHeightWidth 1024 1024 "$GRID" >/dev/null
  for s in 16 32 128 256 512; do
    sips -z $s $s "$GRID" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$GRID" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  cp Assets/AppIcon.png "$APP/Contents/Resources/AppIcon.png"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"
fi

xattr -cr "$APP"
codesign --force --sign - --entitlements Shifty.entitlements "$APP"
echo "Done: $APP"

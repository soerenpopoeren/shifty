#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Builds and starts the Zwift controller probe (developer tool). Output: ~/Library/Logs/ZwiftProbe.log
set -euo pipefail
cd "$(dirname "$0")"
APP=../../build/ZwiftProbe.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos14.0" -o "$APP/Contents/MacOS/ZwiftProbe" main.swift
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>io.github.soerenpopoeren.shifty.zwiftprobe</string>
<key>CFBundleExecutable</key><string>ZwiftProbe</string>
<key>CFBundleName</key><string>ZwiftProbe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>NSBluetoothAlwaysUsageDescription</key><string>ZwiftProbe reads your Zwift controllers to learn their protocol.</string>
</dict></plist>
PLIST
xattr -cr "$APP"; codesign --force --sign - "$APP" >/dev/null 2>&1
echo "Starting ZwiftProbe (120 s). Log: ~/Library/Logs/ZwiftProbe.log"
open "$APP"

#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Builds Shifty and packs it as build/Shifty-<version>.zip for a GitHub release.
set -euo pipefail
cd "$(dirname "$0")"
./build.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
ZIP="build/Shifty-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent build/Shifty.app "$ZIP"
echo "Release package: $ZIP"

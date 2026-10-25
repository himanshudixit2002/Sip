#!/bin/bash
# Renders AppIcon.png, scales it into an .iconset, and packs AppIcon.icns.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p .build
swiftc -O make-icon.swift -o .build/make-icon
.build/make-icon

ICONSET="AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for pair in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" \
            "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" \
            "512 512x512" "1024 512x512@2x"; do
  set -- $pair
  sips -z "$1" "$1" AppIcon.png --out "$ICONSET/icon_$2.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o AppIcon.icns
rm -rf "$ICONSET"
echo "==> AppIcon.icns ready"

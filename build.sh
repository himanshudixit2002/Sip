#!/bin/bash
# Builds Sip.app with Xcode, signed with your Apple Development identity
# (team set in Sip.xcodeproj), and leaves it at .build/Sip.app.
#
# The app, its widget/Control Center extension and the `sip` command are all
# built and signed by Xcode. Builds live under .build, which Spotlight skips,
# and are unregistered from Launch Services, so the only Sip macOS knows
# about is the one in /Applications.
set -euo pipefail
cd "$(dirname "$0")"
DERIVED=".build/xcode"
OUT=".build/Sip.app"
LOG=".build/xcodebuild.log"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
mkdir -p .build
touch .build/.metadata_never_index

ARGS=(-project Sip.xcodeproj -scheme Sip -configuration Release -derivedDataPath "$DERIVED"
      -destination "platform=macOS" -allowProvisioningUpdates)
[ -n "${SIP_TEAM:-}" ] && ARGS+=(DEVELOPMENT_TEAM="$SIP_TEAM")

echo "==> Building Sip (release)"
if ! xcodebuild "${ARGS[@]}" build > "$LOG" 2>&1; then
  grep -E "error:|BUILD FAILED" "$LOG" | sort -u | head -40
  echo "!! build failed (full log: $LOG)"
  exit 1
fi
grep -E "warning:" "$LOG" | grep -v -E "search path|Metadata extraction skipped" | sort -u | head -20 || true

BUILT="$DERIVED/Build/Products/Release/Sip.app"
rm -rf "$OUT"
cp -R "$BUILT" "$OUT"

# Xcode registers what it builds; keep macOS from treating these as more Sips.
for copy in "$DERIVED"/Build/Products/*/Sip.app "$PWD/$OUT"; do
  [ -e "$copy" ] && "$LSREGISTER" -u "$copy" 2>/dev/null || true
done

codesign --verify --deep --strict "$OUT" && echo "   signature ok ($(codesign -dv --verbose=2 "$OUT" 2>&1 | sed -n 's/^Authority=\(Apple Development.*\)/\1/p'))"
echo "==> Done: $(pwd)/$OUT ($(du -sh "$OUT" | cut -f1))"

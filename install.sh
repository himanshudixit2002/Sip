#!/bin/bash
# Builds Sip, replaces /Applications/Sip.app and relaunches it. Settings,
# history and the login item carry over: they belong to the bundle id, and the
# path stays the same.
set -euo pipefail
cd "$(dirname "$0")"

./build.sh
DEST="/Applications/Sip.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

echo "==> Installing to $DEST"
osascript -e 'tell application id "com.himanshudixit.sip" to quit' >/dev/null 2>&1 || true
pkill -f "Sip.app/Contents/MacOS/Sip" 2>/dev/null || true
sleep 0.5
rm -rf "$DEST"
mv .build/Sip.app "$DEST"
"$LSREGISTER" -f "$DEST"
# The widget extension is discovered from the installed app.
pluginkit -a "$DEST/Contents/PlugIns/SipWidget.appex" 2>/dev/null || true

echo "==> Launching"
open "$DEST"
echo "==> Done"

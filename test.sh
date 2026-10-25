#!/bin/bash
# Runs the SipCore tests. Command Line Tools ship Swift Testing's macro plugin
# but SwiftPM doesn't find it on its own, so its directory is passed in.
set -euo pipefail
cd "$(dirname "$0")"
PLUGINS="$(dirname "$(xcrun --find swift)")/../lib/swift/host/plugins/testing"
swift test -Xswiftc -plugin-path -Xswiftc "$PLUGINS" "$@" 2>&1 | grep -v "ld: warning: search path"

# Guard: nothing in SwiftUI may animate forever. A repeating effect redraws the
# whole widget every frame, covered or not (it cost 10% CPU once). Continuous
# motion belongs in the Core Animation bottle, which pauses itself. A line that
# really needs one must say so with `// live-gated`.
if grep -rnE "repeatForever|\.repeat\(\.continuous\)|options: \.repeating" Sources | grep -v "live-gated"; then
  echo "!! continuous SwiftUI animation found (see above)"; exit 1
fi
echo "==> Animation guard passed"

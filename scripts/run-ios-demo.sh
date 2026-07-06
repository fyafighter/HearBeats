#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SIMULATOR="${SIMULATOR:-iPhone 17 Pro}"
CONFIG="${CONFIG:-Debug}"

echo "→ Generating Xcode project…"
xcodegen generate

echo "→ Building HearBeats for iOS Simulator ($SIMULATOR)…"
xcodebuild \
  -project HearBeats.xcodeproj \
  -scheme HearBeats \
  -destination "platform=iOS Simulator,name=$SIMULATOR" \
  -configuration "$CONFIG" \
  -derivedDataPath "$ROOT/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  build

APP="$ROOT/DerivedData/Build/Products/$CONFIG-iphonesimulator/HearBeats.app"
if [[ ! -d "$APP" ]]; then
  echo "Build succeeded but app bundle not found at $APP" >&2
  exit 1
fi

DEVICE_ID="$(xcrun simctl list devices available | grep "$SIMULATOR (" | head -1 | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/')"
if [[ -z "$DEVICE_ID" ]]; then
  echo "Simulator '$SIMULATOR' not found." >&2
  exit 1
fi

echo "→ Booting simulator and installing app…"
xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
xcrun simctl install "$DEVICE_ID" "$APP"
xcrun simctl launch "$DEVICE_ID" com.hearbeats.app

echo "✓ HearBeats is running on $SIMULATOR (Demo mode: switch source to Demo, press Listen)."

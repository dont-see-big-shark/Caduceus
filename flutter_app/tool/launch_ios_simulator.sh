#!/usr/bin/env bash
set -euo pipefail

# Launch and reveal an iOS Simulator on Xcode 27 beta, where the standalone
# Simulator.app has been replaced by DeviceHub.app.
#
# Usage:
#   tool/launch_ios_simulator.sh [device-name]
#
# Defaults to iPhone 17 Pro. The script:
#   1. Creates the Simulator.app symlink Flutter expects.
#   2. Boots the requested simulator if it is not already booted.
#   3. Points DeviceHub at that simulator so it does not open a physical phone.
#   4. Opens DeviceHub in the foreground.

DEVICE_NAME="${1:-iPhone 17 Pro}"

DEV_DIR="$(xcode-select -p)"
XCODE_CONTENTS_DIR="$(dirname "$DEV_DIR")"
DEVICE_HUB="$XCODE_CONTENTS_DIR/Applications/DeviceHub.app"
SIMULATOR_LINK="$DEV_DIR/Applications/Simulator.app"

if [[ ! -d "$DEVICE_HUB" ]]; then
  echo "error: DeviceHub.app not found at $DEVICE_HUB" >&2
  exit 1
fi

# Xcode 27 no longer ships Simulator.app; Flutter looks for it under the
# selected Xcode's Developer/Applications directory.
if [[ ! -e "$SIMULATOR_LINK" ]]; then
  echo "creating Simulator.app symlink -> $DEVICE_HUB"
  ln -s "$DEVICE_HUB" "$SIMULATOR_LINK"
fi

if ! xcrun simctl list devices | grep -F "$DEVICE_NAME" | grep -q '(Booted)'; then
  echo "booting $DEVICE_NAME ..."
  xcrun simctl boot "$DEVICE_NAME" || true
  xcrun simctl bootstatus "$DEVICE_NAME" -b >/dev/null 2>&1 || true
fi

UDID="$(xcrun simctl list devices | grep -F "$DEVICE_NAME" | grep -E '(Booted)' | grep -oE '[0-9A-F-]{36}' | head -1 || true)"
if [[ -z "$UDID" ]]; then
  echo "error: could not resolve a booted simulator named \"$DEVICE_NAME\"" >&2
  xcrun simctl list devices >&2
  exit 1
fi

# DeviceHub stores this as a JSON string inside a data blob.
HEX="$(printf '"%s"' "$UDID" | xxd -p | tr -d '\n')"
defaults write com.apple.dt.Devices lastSelectedDeviceIdentifier -data "$HEX"

# DeviceHub only reads this preference at launch, so restart it.
pkill -9 -f '/DeviceHub.app/Contents/MacOS/DeviceHub' 2>/dev/null || true
sleep 1

open "$SIMULATOR_LINK"
sleep 2
osascript -e 'tell application id "com.apple.dt.Devices" to activate' >/dev/null 2>&1 || true

echo "iOS Simulator is ready: $DEVICE_NAME ($UDID)"

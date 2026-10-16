#!/bin/bash
# Builds Switchboard.app and does a clean install into /Applications:
#   1. builds a release binary and wraps it in Switchboard.app (ad-hoc signed)
#   2. quits any running copy, including earlier names of this app
#      (DisplayToggle, Display Control, Dimmer)
#   3. undoes what those copies did to your screens: reconnects screens they
#      disconnected, removes software dimming, wakes monitors in standby
#   4. deletes their app bundles, settings and Accessibility permission
#   5. installs and launches the new app (which turns on Start at Login)
# Usage: ./make-app.sh             build and install
#        ./make-app.sh --package   build dist/Switchboard.zip only (for releases)
set -euo pipefail
cd "$(dirname "$0")"

PACKAGE_ONLY=false
[ "${1:-}" = "--package" ] && PACKAGE_ONLY=true

APP="Switchboard.app"
STAGE=".build/app/$APP"
OLD_NAMES=("DisplayToggle" "DisplayControl" "Dimmer" "Switchboard")
OLD_BUNDLES=("DisplayToggle.app" "Display Control.app" "Dimmer.app" "Switchboard.app")
OLD_DOMAINS=(
    "app.displaytoggle.DisplayToggle"
    "app.displaycontrol.DisplayControl"
    "app.dimmer.Dimmer"
    "app.switchboard.Switchboard"
)

echo "==> Building release binary"
swift build -c release

echo "==> Assembling $APP"
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/Switchboard" "$STAGE/Contents/MacOS/Switchboard"
cp Resources/Info.plist "$STAGE/Contents/Info.plist"
cp Resources/AppIcon.icns "$STAGE/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$STAGE"

if $PACKAGE_ONLY; then
    echo "==> Packaging dist/Switchboard.zip"
    mkdir -p dist
    rm -f dist/Switchboard.zip
    ditto -c -k --keepParent "$STAGE" dist/Switchboard.zip
    echo "Done: dist/Switchboard.zip"
    exit 0
fi

echo "==> Quitting running copies"
for name in "${OLD_NAMES[@]}"; do pkill -x "$name" 2>/dev/null || true; done
sleep 1

echo "==> Restoring screens (reconnect, undo dimming, wake monitors)"
"$STAGE/Contents/MacOS/Switchboard" --reset || true

echo "==> Removing earlier installs and their settings"
for bundle in "${OLD_BUNDLES[@]}"; do rm -rf "/Applications/$bundle"; done
for domain in "${OLD_DOMAINS[@]}"; do
    defaults delete "$domain" >/dev/null 2>&1 || true
    tccutil reset Accessibility "$domain" >/dev/null 2>&1 || true
    tccutil reset ListenEvent "$domain" >/dev/null 2>&1 || true
done

echo "==> Installing to /Applications"
cp -R "$STAGE" /Applications/
rm -rf "$STAGE"
touch "/Applications/$APP" # make Finder/Dock pick up the icon

echo "==> Launching"
open "/Applications/$APP"
echo "Done. Switchboard is in the menu bar."

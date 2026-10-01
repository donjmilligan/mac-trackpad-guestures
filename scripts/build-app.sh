#!/bin/bash
# Builds build/GestureKeys.app from the SwiftPM executable.
#
# Signing: macOS ties the Accessibility grant to the signature. Uses the "GestureKeys Dev" certificate
# (scripts/make-signing-identity.sh) when present so the grant survives rebuilds; otherwise falls back
# to ad-hoc signing, which needs the grant redone after every build. SIGN_IDENTITY overrides both.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIGURATION="${CONFIGURATION:-release}"
APP="build/GestureKeys.app"

swift build -c "$CONFIGURATION" --product GestureKeys
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/GestureKeys" "$APP/Contents/MacOS/GestureKeys"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Icons (source: Resources/AppIcon.png, the Drum Foundary logo)
swift scripts/make-icons.swift Resources/AppIcon.png build/icons
iconutil -c icns build/icons/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cp build/icons/MenuBarIcon.png build/icons/MenuBarIcon@2x.png "$APP/Contents/Resources/"

if [[ -z "${SIGN_IDENTITY:-}" ]]; then
    # Not `-v`: the self-signed certificate is untrusted but codesign accepts it by hash.
    SIGN_IDENTITY="$(security find-identity -p codesigning | awk '/"GestureKeys Dev"/ { print $2; exit }')"
fi
if [[ -z "$SIGN_IDENTITY" ]]; then
    echo "warning: no \"GestureKeys Dev\" certificate; signing ad-hoc. Run scripts/make-signing-identity.sh to keep" \
         "the Accessibility permission across rebuilds." >&2
    SIGN_IDENTITY="-"
fi

codesign --force --sign "$SIGN_IDENTITY" --identifier com.donjmilligan.GestureKeys "$APP"
echo "Built $APP (signed with $SIGN_IDENTITY)"

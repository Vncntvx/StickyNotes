#!/bin/bash
# Local manual-test signing: uses a STABLE code-signing identity so the
# Keychain ACL (bound to the certificate) matches across rebuilds —
# macOS stops asking for the Keychain password on every launch.
#
# Ad-hoc signing (`codesign -s -`) changes the CDHash on every rebuild,
# which makes Keychain prompt every time. A stable identity (the local
# Apple Development certificate, or any trusted codesigning identity)
# fixes that.
#
# Usage: scripts/sign-local.sh   (builds Debug, signs app+widget, opens)
set -euo pipefail
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
IDENTITY="${IDENTITY:-Apple Development: wenjie.xu.sino@foxmail.com (SJFRS6Q8GH)}"
PROJECT="${PROJECT:-StickyNotes.xcodeproj}"

"$DEVELOPER_DIR/usr/bin/xcodebuild" build \
  -project "$PROJECT" -scheme StickyNotes -configuration Debug \
  CODE_SIGNING_ALLOWED=NO

APP=$(find "$HOME/Library/Developer/Xcode/DerivedData"/StickyNotes-*/Build/Products/Debug/StickyNotes.app -maxdepth 0 | head -1)
if [ -z "$APP" ]; then echo "app bundle not found" >&2; exit 1; fi

codesign --force --sign "$IDENTITY" \
  --entitlements WidgetExtension/WidgetExtension.entitlements \
  "$APP/Contents/PlugIns/StickyNotesWidget.appex"
codesign --force --sign "$IDENTITY" \
  --entitlements App/Resources/StickyNotes.entitlements "$APP"

# Restart cleanly: `open` on a running instance only activates it.
pkill -x StickyNotes 2>/dev/null || true
sleep 1
open "$APP"
echo "Signed and launched: $APP"

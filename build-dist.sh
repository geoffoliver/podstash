#!/bin/bash
# Builds Podstash for macOS and iOS and places the resulting .app.zip / .ipa in dist/.
# macOS build is signed with the Developer ID Application identity, notarized, and stapled.
set -euo pipefail

PROJECT="Podstash.xcodeproj"
SCHEME="Podstash"
CONFIGURATION="Release"
TEAM_ID="8F5SLDK3C7"
NOTARY_PROFILE="podstash-notary"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

BUILD_DIR="$ROOT_DIR/build"
DIST_DIR="$ROOT_DIR/dist"

rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$DIST_DIR"

echo "==> Archiving macOS build..."
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=macOS" \
  -archivePath "$BUILD_DIR/macOS.xcarchive" \
  -allowProvisioningUpdates

MAC_EXPORT_OPTIONS_PLIST="$BUILD_DIR/ExportOptions-macOS.plist"
cat > "$MAC_EXPORT_OPTIONS_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF

echo "==> Exporting Developer ID-signed macOS app..."
MAC_EXPORT_DIR="$BUILD_DIR/macOS-export"
xcodebuild -exportArchive \
  -archivePath "$BUILD_DIR/macOS.xcarchive" \
  -exportPath "$MAC_EXPORT_DIR" \
  -exportOptionsPlist "$MAC_EXPORT_OPTIONS_PLIST" \
  -allowProvisioningUpdates

MAC_APP="$(find "$MAC_EXPORT_DIR" -maxdepth 1 -name "*.app" | head -n 1)"
if [ -z "$MAC_APP" ]; then
  echo "error: could not find .app in macOS export" >&2
  exit 1
fi

APP_NAME="$(basename "$MAC_APP" .app)"
NOTARIZE_ZIP="$BUILD_DIR/$APP_NAME-notarize.zip"

echo "==> Zipping app for notarization..."
ditto -c -k --keepParent "$MAC_APP" "$NOTARIZE_ZIP"

echo "==> Submitting to Apple notary service (this can take a few minutes)..."
xcrun notarytool submit "$NOTARIZE_ZIP" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

echo "==> Stapling notarization ticket..."
xcrun stapler staple "$MAC_APP"

DIST_APP="$DIST_DIR/$APP_NAME.app"
cp -R "$MAC_APP" "$DIST_APP"

echo "==> Zipping notarized app for distribution..."
ditto -c -k --keepParent "$DIST_APP" "$DIST_DIR/$APP_NAME.app.zip"
rm -rf "$DIST_APP"
echo "==> macOS app copied to dist/$APP_NAME.app.zip"

echo "==> Archiving iOS build..."
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=iOS" \
  -archivePath "$BUILD_DIR/iOS.xcarchive" \
  -allowProvisioningUpdates

EXPORT_OPTIONS_PLIST="$BUILD_DIR/ExportOptions-iOS.plist"
cat > "$EXPORT_OPTIONS_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>development</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>compileBitcode</key>
    <false/>
</dict>
</plist>
EOF

echo "==> Exporting iOS .ipa..."
IOS_EXPORT_DIR="$BUILD_DIR/iOS-export"
xcodebuild -exportArchive \
  -archivePath "$BUILD_DIR/iOS.xcarchive" \
  -exportPath "$IOS_EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"

IOS_IPA="$(find "$IOS_EXPORT_DIR" -maxdepth 1 -name "*.ipa" | head -n 1)"
if [ -z "$IOS_IPA" ]; then
  echo "error: could not find .ipa in iOS export" >&2
  exit 1
fi
cp "$IOS_IPA" "$DIST_DIR/"
echo "==> iOS ipa copied to dist/$(basename "$IOS_IPA")"
echo "    note: this is a development-signed build and will only install on devices"
echo "    registered in the team's provisioning profile."

echo
echo "==> Done. Contents of dist/:"
ls -la "$DIST_DIR"

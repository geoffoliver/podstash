#!/bin/bash
# Builds Podstash for macOS and iOS and places the resulting .app / .ipa in dist/.
set -euo pipefail

PROJECT="Podstash.xcodeproj"
SCHEME="Podstash"
CONFIGURATION="Release"
TEAM_ID="8F5SLDK3C7"

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

MAC_APP="$(find "$BUILD_DIR/macOS.xcarchive/Products/Applications" -maxdepth 1 -name "*.app" | head -n 1)"
if [ -z "$MAC_APP" ]; then
  echo "error: could not find .app in macOS archive" >&2
  exit 1
fi
cp -R "$MAC_APP" "$DIST_DIR/"
echo "==> macOS app copied to dist/$(basename "$MAC_APP")"

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

echo
echo "==> Done. Contents of dist/:"
ls -la "$DIST_DIR"

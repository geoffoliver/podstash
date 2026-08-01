#!/bin/bash
# Compiles the Airfoil integration AppleScript sources (Podstash/*.applescript) into
# .scpt files for quick manual testing, without needing a full Xcode/xcodebuild run.
# Mirrors the "Compile AppleScript Resources" build phase in Podstash.xcodeproj.
#
# Usage:
#   ./compile-applescripts.sh            # compile to build/AirfoilScripts/
#   ./compile-applescripts.sh --install  # also install into ~/Library/Application Support/Airfoil
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$ROOT_DIR/Podstash"
OUT_DIR="$ROOT_DIR/build/AirfoilScripts"
BUNDLE_ID="me.geoffoliver.Podstash"

mkdir -p "$OUT_DIR"

echo "==> Compiling TrackMetadata.applescript"
osacompile -o "$OUT_DIR/TrackMetadata.scpt" "$SRC_DIR/TrackMetadata.applescript"

echo "==> Compiling RemoteControl.applescript"
osacompile -o "$OUT_DIR/RemoteControl.scpt" "$SRC_DIR/RemoteControl.applescript"

echo "==> Compiled scripts:"
echo "  $OUT_DIR/TrackMetadata.scpt"
echo "  $OUT_DIR/RemoteControl.scpt"

if [ "${1:-}" = "--install" ]; then
  echo
  echo "==> Installing for Airfoil testing..."
  mkdir -p ~/Library/Application\ Support/Airfoil/TrackTitles
  mkdir -p ~/Library/Application\ Support/Airfoil/RemoteControl
  cp "$OUT_DIR/TrackMetadata.scpt" ~/Library/Application\ Support/Airfoil/TrackTitles/${BUNDLE_ID}.scpt
  cp "$OUT_DIR/RemoteControl.scpt" ~/Library/Application\ Support/Airfoil/RemoteControl/dacp.${BUNDLE_ID}.scpt
  echo "  Installed to ~/Library/Application Support/Airfoil/{TrackTitles,RemoteControl}/"
fi

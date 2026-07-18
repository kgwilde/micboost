#!/bin/bash
set -e
cd "$(dirname "$0")"

APP=MicBoost.app

echo "Building..."
swift build -c release

echo "Assembling app bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"
cp .build/release/MicBoost "$APP/Contents/MacOS/MicBoost"

echo "Signing (ad-hoc)..."
codesign --force --deep --sign - "$APP"

cp .build/release/micboostctl ./micboostctl

echo "Done. Built $APP and ./micboostctl"

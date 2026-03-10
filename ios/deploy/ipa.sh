#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"
mkdir -p build
xcodebuild -project Mystro.xcodeproj -scheme Destro -configuration Release VALID_ARCHS=arm64 ONLY_ACTIVE_ARCH=NO -archivePath ./build/Destro.xcarchive clean archive
xcodebuild -exportArchive -archivePath ./build/Destro.xcarchive -exportOptionsPlist "$PROJECT_ROOT/ExportOptions.plist" -exportPath ./build
echo "✅ Destro.ipa in build/ — install via Xcode > Devices (ad‑hoc) or use TestFlight: Product → Archive → Distribute App → App Store Connect. Set teamID in ExportOptions.plist."
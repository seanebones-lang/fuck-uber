#!/bin/bash
set -e
mkdir -p build
xcodebuild -project Mystro.xcodeproj -scheme Mystro -configuration Release VALID_ARCHS=arm64 ONLY_ACTIVE_ARCH=NO -archivePath ./build/Mystro.xcarchive clean archive
xcodebuild -exportArchive -archivePath ./build/Mystro.xcarchive -exportOptionsPlist ExportOptions.plist -exportPath ./Mystro.ipa
echo "✅ Mystro.ipa built! Sideload: Xcode > Devices or AltStore. teamID in ExportOptions.plist."
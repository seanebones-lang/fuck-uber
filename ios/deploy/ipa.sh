#!/bin/bash
set -e
xcodebuild clean -workspace ../Mystro.xcworkspace -scheme Mystro || xcodebuild clean -project ../Mystro.xcodeproj -scheme Mystro
xcodebuild archive \
  -project ../Mystro.xcodeproj \
  -scheme Mystro \
  -destination 'generic/platform=iOS' \
  -archivePath ./Mystro.xcarchive \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES
xcodebuild -exportArchive \
  -archivePath ./Mystro.xcarchive \
  -exportOptionsPlist exportOptions.plist \
  -exportPath ./Mystro.ipa
rm -rf ./Mystro.xcarchive
echo '✅ IPA ready: ./Mystro.ipa (AltStore/Sideloadly)'
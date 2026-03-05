#!/bin/bash
xcodebuild -workspace ios/Mystro.xcworkspace -scheme Mystro -destination 'platform=iOS,name=iPhone 15 Pro' -archivePath build/Mystro.xcarchive archive
xcodebuild -exportArchive -archivePath build/Mystro.xcarchive -exportPath build/ -exportOptionsPlist exportOptions.plist
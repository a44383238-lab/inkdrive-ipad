#!/bin/bash
set -euo pipefail
mkdir -p build artifacts
xcodebuild -list -workspace ios/InkDrive.xcworkspace
xcodebuild \
  -workspace ios/InkDrive.xcworkspace \
  -scheme InkDrive \
  -configuration Debug \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' \
  DEVELOPMENT_TEAM='' \
  ONLY_ACTIVE_ARCH=NO \
  ARCHS=arm64 \
  build 2>&1 | tee build/xcodebuild.log

APP='build/DerivedData/Build/Products/Debug-iphoneos/InkDrive.app'
test -d "$APP"
test -f "$APP/InkDrive"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")" = 'app.inkdrive.notes'
mkdir -p build/Package/Payload
ditto "$APP" build/Package/Payload/InkDrive.app
(
  cd build/Package
  zip -qry ../../artifacts/InkDrive-development-unsigned.ipa Payload
)
shasum -a 256 artifacts/InkDrive-development-unsigned.ipa > artifacts/InkDrive-development-unsigned.ipa.sha256
node -e 'const fs=require("fs");fs.writeFileSync("artifacts/build-info.json",JSON.stringify({name:"InkDrive",configuration:"Debug",developmentClient:true,signed:false,installation:"Sign and install with Sideloadly",commit:process.env.GITHUB_SHA,run:process.env.GITHUB_RUN_ID},null,2))'

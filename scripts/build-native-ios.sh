#!/bin/bash
set -euo pipefail
mkdir -p build artifacts
(
  cd native
  xcodegen generate
)
xcodebuild -project native/InkDrive.xcodeproj -scheme InkDrive -configuration Debug \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build/NativeDerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' DEVELOPMENT_TEAM='' \
  ONLY_ACTIVE_ARCH=NO ARCHS=arm64 build 2>&1 | tee build/native-app.log
APP='build/NativeDerivedData/Build/Products/Debug-iphoneos/InkDrive.app'
test -d "$APP"
test -f "$APP/InkDrive"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")" = 'app.inkdrive.notes'
# Fail if the old JavaScript runtime or development launcher slips into the product.
if find "$APP" -iname '*hermes*' -o -iname '*React*' -o -iname '*EXDevLauncher*' | grep -q .; then
  echo 'Unexpected JavaScript runtime in native application'; exit 1
fi
mkdir -p build/NativePackage/Payload
ditto "$APP" build/NativePackage/Payload/InkDrive.app
(cd build/NativePackage && zip -qry ../../artifacts/InkDrive-Swift-development.ipa Payload)
shasum -a 256 artifacts/InkDrive-Swift-development.ipa > artifacts/InkDrive-Swift-development.ipa.sha256
python3 - <<'PY'
import json,os,pathlib
pathlib.Path('artifacts/build-info.json').write_text(json.dumps(dict(name='InkDrive',version='0.4.0',configuration='Debug',nativeSwift=True,developmentServerRequired=False,signed=False,installation='Sign and install with Sideloadly',commit=os.environ.get('GITHUB_SHA'),run=os.environ.get('GITHUB_RUN_ID')),indent=2))
PY

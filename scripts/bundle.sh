#!/bin/zsh
# Builds Shelf.app. Uses swiftc directly because SwiftPM in some
# Command Line Tools installs fails with "unable to lookup item 'PlatformPath'".
set -euo pipefail
cd "$(dirname "$0")/.."

APP=Shelf.app
ARCH=$(uname -m)
mkdir -p .build
swiftc -O -parse-as-library -target "${ARCH}-apple-macos13.0" -framework Carbon \
  $(find Sources/Core Sources/App -name '*.swift') -o .build/Shelf

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/Shelf "$APP/Contents/MacOS/Shelf"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Shelf</string>
  <key>CFBundleDisplayName</key><string>Shelf</string>
  <key>CFBundleIdentifier</key><string>com.awesomesauce.Shelf</string>
  <key>CFBundleExecutable</key><string>Shelf</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>Shelf reads your Terminal windows and arranges them.</string>
</dict>
</plist>
PLIST
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"

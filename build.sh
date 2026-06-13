#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "Building ClaudeTrafficLight (dual mode)..."

rm -f build/ClaudeTrafficLight

# Compile all Swift source files together
swiftc \
  -o build/ClaudeTrafficLight \
  -target arm64-apple-macosx13.0 \
  -framework SwiftUI \
  -framework AppKit \
  -framework Foundation \
  Sources/ClaudeTrafficLight/Models.swift \
  Sources/ClaudeTrafficLight/SessionMonitor.swift \
  Sources/ClaudeTrafficLight/main.swift \
  2>&1 | grep -v "warning:" || true

APP_DIR="build/ClaudeTrafficLight.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
cp build/ClaudeTrafficLight "$APP_DIR/Contents/MacOS/"

cat > "$APP_DIR/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ClaudeTrafficLight</string>
    <key>CFBundleIdentifier</key>
    <string>com.claude.trafficlight</string>
    <key>CFBundleName</key>
    <string>Claude Traffic Light</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "Build OK — run: open $APP_DIR"

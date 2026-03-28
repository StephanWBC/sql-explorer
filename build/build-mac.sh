#!/bin/bash
set -euo pipefail

echo "=== Building SQL Explorer for macOS ==="

# Build release binary
swift build -c release

# Find the binary
BINARY=".build/release/SQLExplorer"
if [ ! -f "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY"
    exit 1
fi

# Create app bundle
APP_DIR="publish/SQL Explorer.app"
rm -rf publish
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy binary
cp "$BINARY" "$APP_DIR/Contents/MacOS/SQLExplorer"

# Copy MSAL framework if present
MSAL_FRAMEWORK=".build/release/MSAL.framework"
if [ -d "$MSAL_FRAMEWORK" ]; then
    mkdir -p "$APP_DIR/Contents/Frameworks"
    cp -R "$MSAL_FRAMEWORK" "$APP_DIR/Contents/Frameworks/"
    # Sign the framework first
    codesign --deep --force --sign - "$APP_DIR/Contents/Frameworks/MSAL.framework" 2>/dev/null || true
fi

# Create Info.plist
VERSION="${1:-1.0.0}"
cat > "$APP_DIR/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>SQLExplorer</string>
    <key>CFBundleIdentifier</key>
    <string>com.sqlexplorer.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>SQL Explorer</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
</dict>
</plist>
PLIST

# Ad-hoc code sign (ignore warnings)
codesign --deep --force --sign - "$APP_DIR" 2>/dev/null || true
echo "Code signed."

# Create DMG
DMG_PATH="publish/SQLExplorer-${VERSION}-mac.dmg"
STAGING="publish/dmg-staging"
mkdir -p "$STAGING"
cp -R "$APP_DIR" "$STAGING/"
ln -sf /Applications "$STAGING/Applications"

hdiutil create -volname "SQL Explorer" -srcfolder "$STAGING" \
    -ov -format UDZO "$DMG_PATH"

rm -rf "$STAGING"

echo ""
echo "=== Build complete ==="
echo "DMG: $(pwd)/$DMG_PATH"
echo "App: $(pwd)/$APP_DIR"
ls -lh "$DMG_PATH"

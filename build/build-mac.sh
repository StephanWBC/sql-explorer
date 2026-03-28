#!/bin/bash
set -euo pipefail

echo "=== Building SQL Explorer for macOS ==="

VERSION="${1:-1.0.0}"

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
mkdir -p "$APP_DIR/Contents/Frameworks"

# Copy binary
cp "$BINARY" "$APP_DIR/Contents/MacOS/SQLExplorer"

# Copy MSAL framework — the binary links to @rpath/MSAL.framework
MSAL_FW=".build/arm64-apple-macosx/release/MSAL.framework"
if [ ! -d "$MSAL_FW" ]; then
    # Fallback: look in artifacts
    MSAL_FW=$(find .build/artifacts -name "MSAL.framework" -path "*/macos-*" | head -1)
fi

if [ -d "$MSAL_FW" ]; then
    echo "Copying MSAL.framework from $MSAL_FW"
    cp -R "$MSAL_FW" "$APP_DIR/Contents/Frameworks/"

    # Fix rpath: the binary looks for @rpath/MSAL.framework
    # Add the Frameworks directory to rpath
    install_name_tool -add_rpath @executable_path/../Frameworks "$APP_DIR/Contents/MacOS/SQLExplorer" 2>/dev/null || true

    # Sign the framework
    codesign --deep --force --sign - "$APP_DIR/Contents/Frameworks/MSAL.framework" 2>/dev/null || true
else
    echo "WARNING: MSAL.framework not found!"
fi

# Copy FreeTDS dylib and fix load path
SYBDB_PATHS=("/opt/homebrew/lib/libsybdb.5.dylib" "/opt/homebrew/opt/freetds/lib/libsybdb.5.dylib")
for SYBDB in "${SYBDB_PATHS[@]}"; do
    if [ -f "$SYBDB" ]; then
        cp "$SYBDB" "$APP_DIR/Contents/Frameworks/"
        # Get the actual path the binary references
        LINKED_PATH=$(otool -L "$APP_DIR/Contents/MacOS/SQLExplorer" | grep sybdb | awk '{print $1}')
        if [ -n "$LINKED_PATH" ]; then
            install_name_tool -change "$LINKED_PATH" @executable_path/../Frameworks/libsybdb.5.dylib "$APP_DIR/Contents/MacOS/SQLExplorer" 2>/dev/null || true
        fi
        codesign --force --sign - "$APP_DIR/Contents/Frameworks/libsybdb.5.dylib" 2>/dev/null || true
        echo "Bundled FreeTDS from $SYBDB"
        break
    fi
done

# Generate .icns icon from logo PNGs
ICONSET="$APP_DIR/Contents/Resources/AppIcon.iconset"
mkdir -p "$ICONSET"
LOGO_DIR="SQLExplorer/Resources"
cp "$LOGO_DIR/logo-16.png"   "$ICONSET/icon_16x16.png"
cp "$LOGO_DIR/logo-32.png"   "$ICONSET/icon_16x16@2x.png"
cp "$LOGO_DIR/logo-32.png"   "$ICONSET/icon_32x32.png"
cp "$LOGO_DIR/logo-64.png"   "$ICONSET/icon_32x32@2x.png"
cp "$LOGO_DIR/logo-128.png"  "$ICONSET/icon_128x128.png"
cp "$LOGO_DIR/logo-256.png"  "$ICONSET/icon_128x128@2x.png"
cp "$LOGO_DIR/logo-256.png"  "$ICONSET/icon_256x256.png"
cp "$LOGO_DIR/logo-512.png"  "$ICONSET/icon_256x256@2x.png"
cp "$LOGO_DIR/logo-512.png"  "$ICONSET/icon_512x512.png"
cp "$LOGO_DIR/logo-1024.png" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns -o "$APP_DIR/Contents/Resources/AppIcon.icns" "$ICONSET"
rm -rf "$ICONSET"
echo "Icon created."

# Create Info.plist
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
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
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

# Ad-hoc code sign the whole bundle
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

#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
VERSION="${1:-1.0.0}"
APP_NAME="SQL Explorer"
BUNDLE_ID="com.sqlexplorer.app"
PUBLISH_DIR="$ROOT_DIR/publish/mac"
APP_BUNDLE="$PUBLISH_DIR/$APP_NAME.app"
DMG_DIR="$ROOT_DIR/publish"
DMG_FILE="$DMG_DIR/SQLExplorer-${VERSION}-mac.dmg"

echo "=== Building SQL Explorer v${VERSION} for macOS ==="

# Clean
rm -rf "$PUBLISH_DIR"
mkdir -p "$PUBLISH_DIR"

# Detect architecture
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    RID="osx-arm64"
else
    RID="osx-x64"
fi

echo "Building for $RID..."

# Publish self-contained
dotnet publish "$ROOT_DIR/src/SqlStudio.App/SqlStudio.App.csproj" \
    -c Release \
    -r "$RID" \
    --self-contained true \
    -p:PublishSingleFile=false \
    -p:Version="$VERSION" \
    -o "$PUBLISH_DIR/bin"

echo "Creating macOS .app bundle..."

# Create .app bundle structure
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binaries
cp -R "$PUBLISH_DIR/bin/"* "$APP_BUNDLE/Contents/MacOS/"

# Create Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>SqlStudio.App</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright 2026 SQL Explorer contributors</string>
</dict>
</plist>
PLIST

# Convert PNG to icns for macOS app icon
if [ -f "$ROOT_DIR/src/SqlStudio.App/Assets/logo.png" ]; then
    echo "Creating .icns icon..."
    ICONSET="$PUBLISH_DIR/AppIcon.iconset"
    mkdir -p "$ICONSET"

    sips -z 16 16     "$ROOT_DIR/src/SqlStudio.App/Assets/logo.png" --out "$ICONSET/icon_16x16.png" 2>/dev/null
    sips -z 32 32     "$ROOT_DIR/src/SqlStudio.App/Assets/logo.png" --out "$ICONSET/icon_16x16@2x.png" 2>/dev/null
    sips -z 32 32     "$ROOT_DIR/src/SqlStudio.App/Assets/logo.png" --out "$ICONSET/icon_32x32.png" 2>/dev/null
    sips -z 64 64     "$ROOT_DIR/src/SqlStudio.App/Assets/logo.png" --out "$ICONSET/icon_32x32@2x.png" 2>/dev/null
    sips -z 128 128   "$ROOT_DIR/src/SqlStudio.App/Assets/logo.png" --out "$ICONSET/icon_128x128.png" 2>/dev/null
    sips -z 256 256   "$ROOT_DIR/src/SqlStudio.App/Assets/logo.png" --out "$ICONSET/icon_128x128@2x.png" 2>/dev/null
    sips -z 256 256   "$ROOT_DIR/src/SqlStudio.App/Assets/logo.png" --out "$ICONSET/icon_256x256.png" 2>/dev/null
    sips -z 512 512   "$ROOT_DIR/src/SqlStudio.App/Assets/logo.png" --out "$ICONSET/icon_256x256@2x.png" 2>/dev/null
    sips -z 512 512   "$ROOT_DIR/src/SqlStudio.App/Assets/logo.png" --out "$ICONSET/icon_512x512.png" 2>/dev/null
    cp "$ROOT_DIR/src/SqlStudio.App/Assets/logo.png" "$ICONSET/icon_512x512@2x.png"

    iconutil -c icns "$ICONSET" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    rm -rf "$ICONSET"
fi

# Make executable
chmod +x "$APP_BUNDLE/Contents/MacOS/SqlStudio.App"

echo "Creating .dmg installer..."

# Create a temporary DMG staging directory
DMG_STAGING="$PUBLISH_DIR/dmg-staging"
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"

# Create a symlink to /Applications for drag-and-drop install
ln -s /Applications "$DMG_STAGING/Applications"

# Create the DMG
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDZO \
    "$DMG_FILE"

# Clean up
rm -rf "$DMG_STAGING"
rm -rf "$PUBLISH_DIR/bin"

echo ""
echo "=== Build complete ==="
echo "DMG: $DMG_FILE"
echo "App Bundle: $APP_BUNDLE"
ls -lh "$DMG_FILE"

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

    ASSETS="$ROOT_DIR/src/SqlStudio.App/Assets"
    # Use pre-rendered sizes if available, otherwise resize from logo.png
    for size_pair in "16:icon_16x16" "32:icon_16x16@2x" "32:icon_32x32" "64:icon_32x32@2x" \
                     "128:icon_128x128" "256:icon_128x128@2x" "256:icon_256x256" "512:icon_256x256@2x" \
                     "512:icon_512x512" "1024:icon_512x512@2x"; do
        SIZE="${size_pair%%:*}"
        NAME="${size_pair##*:}"
        if [ -f "$ASSETS/logo-${SIZE}.png" ]; then
            cp "$ASSETS/logo-${SIZE}.png" "$ICONSET/${NAME}.png"
        else
            sips -z "$SIZE" "$SIZE" "$ASSETS/logo.png" --out "$ICONSET/${NAME}.png" 2>/dev/null
        fi
    done

    iconutil -c icns "$ICONSET" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    rm -rf "$ICONSET"
fi

# Make executable
chmod +x "$APP_BUNDLE/Contents/MacOS/SqlStudio.App"

echo "Ad-hoc code signing the app bundle..."
# Ad-hoc sign all native libraries and the main executable
# This prevents macOS Gatekeeper "damaged" errors
find "$APP_BUNDLE" -name "*.dylib" -exec codesign --force --sign - {} \; 2>/dev/null || true
find "$APP_BUNDLE" -name "*.so" -exec codesign --force --sign - {} \; 2>/dev/null || true
codesign --force --deep --sign - "$APP_BUNDLE/Contents/MacOS/SqlStudio.App" 2>/dev/null || true
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true
echo "Code signing complete."

# Remove any quarantine attributes
xattr -cr "$APP_BUNDLE" 2>/dev/null || true

echo "Creating .dmg installer..."

# Create a temporary DMG staging directory
DMG_STAGING="$PUBLISH_DIR/dmg-staging"
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"

# Create a symlink to /Applications for drag-and-drop install
ln -s /Applications "$DMG_STAGING/Applications"

# Create the one-click installer script
cat > "$DMG_STAGING/Install SQL Explorer.command" << 'INSTALL_SCRIPT'
#!/bin/bash
# SQL Explorer Installer — double-click this to install
clear
echo ""
echo "  ╔══════════════════════════════════════╗"
echo "  ║     SQL Explorer — Installing...     ║"
echo "  ╚══════════════════════════════════════╝"
echo ""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_SRC="$SCRIPT_DIR/SQL Explorer.app"
APP_DEST="/Applications/SQL Explorer.app"

if [ ! -d "$APP_SRC" ]; then
    echo "  ✗ Error: Could not find SQL Explorer.app"
    echo "    Press any key to exit..."
    read -n 1
    exit 1
fi

# Remove old version if exists
if [ -d "$APP_DEST" ]; then
    echo "  → Removing previous version..."
    rm -rf "$APP_DEST"
fi

echo "  → Copying to Applications..."
cp -R "$APP_SRC" "$APP_DEST"

echo "  → Clearing quarantine flags..."
xattr -cr "$APP_DEST" 2>/dev/null

echo "  → Signing app..."
codesign --force --deep --sign - "$APP_DEST" 2>/dev/null

echo ""
echo "  ✓ SQL Explorer installed successfully!"
echo ""
echo "  → Launching SQL Explorer..."
sleep 1
open "$APP_DEST"

echo ""
echo "  You can close this window now."
echo "  Press any key to exit..."
read -n 1
INSTALL_SCRIPT
chmod +x "$DMG_STAGING/Install SQL Explorer.command"

# Remove quarantine from staging
xattr -cr "$DMG_STAGING" 2>/dev/null || true

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

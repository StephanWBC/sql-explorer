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
    # Use -RL to dereference symlinks — prevents Error -36 in Finder copy
    cp -RL "$MSAL_FW" "$APP_DIR/Contents/Frameworks/"

    # Strip all extended attributes recursively (prevents Error -36)
    xattr -rc "$APP_DIR/Contents/Frameworks/MSAL.framework" 2>/dev/null || true

    # Fix rpath
    install_name_tool -add_rpath @executable_path/../Frameworks "$APP_DIR/Contents/MacOS/SQLExplorer" 2>/dev/null || true

    # Sign the framework
    codesign --deep --force --sign - "$APP_DIR/Contents/Frameworks/MSAL.framework" 2>/dev/null || true
else
    echo "WARNING: MSAL.framework not found!"
fi

# --- Helper: bundle a Homebrew dylib and rewrite its install name ---
bundle_lib() {
    local SRC="$1"
    local LIBNAME
    LIBNAME=$(basename "$SRC")
    if [ ! -f "$APP_DIR/Contents/Frameworks/$LIBNAME" ]; then
        cp "$SRC" "$APP_DIR/Contents/Frameworks/"
        echo "  Bundled $LIBNAME"
    fi
}

# --- Helper: rewrite all /opt/homebrew references inside a bundled dylib ---
fix_homebrew_refs() {
    local TARGET="$1"
    otool -L "$TARGET" | awk '{print $1}' | grep '/opt/homebrew' | while read -r REF; do
        local REFNAME
        REFNAME=$(basename "$REF")
        install_name_tool -change "$REF" "@executable_path/../Frameworks/$REFNAME" "$TARGET" 2>/dev/null || true
    done
}

# 1) Copy OpenSSL dylibs (transitive dep of FreeTDS)
for SSLDIR in "/opt/homebrew/opt/openssl@3/lib" "/opt/homebrew/lib"; do
    if [ -f "$SSLDIR/libssl.3.dylib" ]; then
        bundle_lib "$SSLDIR/libssl.3.dylib"
        bundle_lib "$SSLDIR/libcrypto.3.dylib"
        break
    fi
done

# 2) Copy FreeTDS dylib
SYBDB_PATHS=("/opt/homebrew/lib/libsybdb.5.dylib" "/opt/homebrew/opt/freetds/lib/libsybdb.5.dylib")
for SYBDB in "${SYBDB_PATHS[@]}"; do
    if [ -f "$SYBDB" ]; then
        bundle_lib "$SYBDB"
        # Fix reference from main binary
        LINKED_PATH=$(otool -L "$APP_DIR/Contents/MacOS/SQLExplorer" | grep sybdb | awk '{print $1}')
        if [ -n "$LINKED_PATH" ]; then
            install_name_tool -change "$LINKED_PATH" @executable_path/../Frameworks/libsybdb.5.dylib "$APP_DIR/Contents/MacOS/SQLExplorer" 2>/dev/null || true
        fi
        break
    fi
done

# 3) Copy libltdl (transitive dep of ODBC)
LTDL_PATHS=("/opt/homebrew/opt/libtool/lib/libltdl.7.dylib" "/opt/homebrew/lib/libltdl.7.dylib")
for LTDL in "${LTDL_PATHS[@]}"; do
    if [ -f "$LTDL" ]; then
        bundle_lib "$LTDL"
        break
    fi
done

# 4) Copy ODBC dylibs
for ODBCLIB in /opt/homebrew/lib/libodbc.2.dylib /opt/homebrew/lib/libodbcinst.2.dylib; do
    if [ -f "$ODBCLIB" ]; then
        LIBNAME=$(basename "$ODBCLIB")
        bundle_lib "$ODBCLIB"
        # Fix reference from main binary
        LINKED=$(otool -L "$APP_DIR/Contents/MacOS/SQLExplorer" | grep "$LIBNAME" | awk '{print $1}' || true)
        if [ -n "$LINKED" ]; then
            install_name_tool -change "$LINKED" "@executable_path/../Frameworks/$LIBNAME" "$APP_DIR/Contents/MacOS/SQLExplorer" 2>/dev/null || true
        fi
    fi
done

# 5) Rewrite all Homebrew references inside every bundled dylib and re-sign
for BUNDLED in "$APP_DIR/Contents/Frameworks/"*.dylib; do
    fix_homebrew_refs "$BUNDLED"
    codesign --force --sign - "$BUNDLED" 2>/dev/null || true
done
echo "Bundled FreeTDS, OpenSSL, ODBC, and libltdl libraries."

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

# Create entitlements for Keychain access (required for MSAL token persistence)
cat > "publish/entitlements.plist" << 'ENTITLEMENTS'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>keychain-access-groups</key>
    <array>
        <string>com.sqlexplorer.app</string>
        <string>com.microsoft.identity.universalstorage</string>
    </array>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
ENTITLEMENTS

# Ad-hoc code sign with entitlements
codesign --deep --force --sign - --entitlements "publish/entitlements.plist" "$APP_DIR" 2>/dev/null || true
echo "Code signed with Keychain entitlements."

# Create DMG — two-step: create read-write, then convert to compressed
DMG_PATH="publish/SQLExplorer-${VERSION}-mac.dmg"
STAGING="publish/dmg-staging"
RW_DMG="publish/SQLExplorer-rw.dmg"
rm -rf "$STAGING" "$RW_DMG"
mkdir -p "$STAGING"
ditto "$APP_DIR" "$STAGING/SQL Explorer.app"
ln -sf /Applications "$STAGING/Applications"

# Strip extended attributes that cause Finder Error -36
xattr -rc "$STAGING/SQL Explorer.app" 2>/dev/null || true

# Create uncompressed DMG first, then convert (avoids corruption)
hdiutil create -volname "SQL Explorer" -srcfolder "$STAGING" \
    -ov -format UDRW "$RW_DMG"
rm -rf "$STAGING"

hdiutil convert "$RW_DMG" -format UDZO -o "$DMG_PATH" -ov
rm -f "$RW_DMG"

# Strip quarantine attribute from final DMG to prevent Error -36 on drag-install
xattr -d com.apple.quarantine "$DMG_PATH" 2>/dev/null || true

echo ""
echo "=== Build complete ==="
echo "DMG: $(pwd)/$DMG_PATH"
echo "App: $(pwd)/$APP_DIR"
ls -lh "$DMG_PATH"

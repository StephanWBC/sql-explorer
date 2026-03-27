#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
VERSION="${1:-1.0.0}"
PUBLISH_DIR="$ROOT_DIR/publish/windows"
MSI_DIR="$ROOT_DIR/publish"

echo "=== Building SQL Explorer v${VERSION} for Windows ==="

# Clean
rm -rf "$PUBLISH_DIR"
mkdir -p "$PUBLISH_DIR"

# Publish self-contained for Windows x64
dotnet publish "$ROOT_DIR/src/SqlStudio.App/SqlStudio.App.csproj" \
    -c Release \
    -r win-x64 \
    --self-contained true \
    -p:PublishSingleFile=true \
    -p:IncludeNativeLibrariesForSelfExtract=true \
    -p:Version="$VERSION" \
    -o "$PUBLISH_DIR"

echo ""
echo "=== Windows build complete ==="
echo "Output: $PUBLISH_DIR"
echo ""
echo "Files:"
ls -lh "$PUBLISH_DIR/SqlStudio.App.exe" 2>/dev/null || ls -lh "$PUBLISH_DIR/"
echo ""
echo "=== To create .msi on Windows ==="
echo "1. Install WiX Toolset: dotnet tool install -g wix"
echo "2. Run: wix build build/SqlExplorer.wxs -o publish/SQLExplorer-${VERSION}-win.msi"
echo ""
echo "=== Or distribute as portable zip ==="
cd "$PUBLISH_DIR" && zip -r "$MSI_DIR/SQLExplorer-${VERSION}-win-x64.zip" . && echo "ZIP created: $MSI_DIR/SQLExplorer-${VERSION}-win-x64.zip"

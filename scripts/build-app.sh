#!/usr/bin/env bash
#
# build-app.sh — Build AI Island as a macOS .app bundle
#
# Usage:
#   ./scripts/build-app.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="AIIsland"
BUNDLE_DIR="$PROJECT_DIR/$APP_NAME.app"

echo "=== Building AI Island ==="

# ---------- 1. Build in release mode ----------

echo "Building in release mode..."
cd "$PROJECT_DIR"
swift build -c release 2>&1

RELEASE_DIR="$PROJECT_DIR/.build/release"

if [[ ! -x "$RELEASE_DIR/AIIsland" ]]; then
    echo "ERROR: AIIsland binary not found at $RELEASE_DIR/AIIsland"
    exit 1
fi

if [[ ! -x "$RELEASE_DIR/aibridge" ]]; then
    echo "ERROR: aibridge binary not found at $RELEASE_DIR/aibridge"
    exit 1
fi

# ---------- 2. Create app bundle structure ----------

echo "Creating app bundle..."
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"

# ---------- 3. Copy binaries ----------

cp "$RELEASE_DIR/AIIsland" "$BUNDLE_DIR/Contents/MacOS/AIIsland"
cp "$RELEASE_DIR/aibridge" "$BUNDLE_DIR/Contents/MacOS/aibridge"

# Copy sound resources if they exist
if [[ -d "$PROJECT_DIR/Resources/Sounds" ]]; then
    cp -R "$PROJECT_DIR/Resources/Sounds" "$BUNDLE_DIR/Contents/Resources/Sounds"
    echo "Copied sound resources."
fi

# ---------- 4. Create Info.plist ----------

cat > "$BUNDLE_DIR/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>AI Island</string>
    <key>CFBundleDisplayName</key>
    <string>AI Island</string>
    <key>CFBundleIdentifier</key>
    <string>com.aiisland.app</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>AIIsland</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
PLIST

echo "Created Info.plist"

# ---------- 5. Generate app icon ----------

echo "Generating app icon..."

# Use the matrix-style icon generator
python3 "$SCRIPT_DIR/generate-icon.py"

# Copy the pre-generated .icns to the app bundle
if [[ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]]; then
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$BUNDLE_DIR/Contents/Resources/AppIcon.icns"
    echo "Copied AppIcon.icns"
else
    echo "WARNING: AppIcon.icns not found. Run: python3 scripts/generate-icon.py"
fi

# ---------- 6. Summary ----------

echo ""
echo "=== Build complete ==="
echo ""
echo "App bundle: $BUNDLE_DIR"
echo ""
echo "To run:"
echo "  open $BUNDLE_DIR"
echo ""
echo "To install hooks after launching:"
echo "  $SCRIPT_DIR/install-hooks.sh $BUNDLE_DIR/Contents/MacOS/aibridge"
echo ""
echo "To copy to /Applications:"
echo "  cp -R $BUNDLE_DIR /Applications/"

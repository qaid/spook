#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

APP_NAME="Spook"
APP_PATH="$HOME/Applications/$APP_NAME.app"
BUILD_PATH=".build/release/$APP_NAME"

# Kill existing Spook process if running
pkill -x Spook 2>/dev/null && echo "Stopped existing Spook process." && sleep 1 || true

echo "Building $APP_NAME (release)..."
swift build -c release

if [ ! -f "$BUILD_PATH" ]; then
    echo "Error: Build failed - executable not found at $BUILD_PATH"
    exit 1
fi

echo "Creating app bundle at $APP_PATH..."

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

cp "$BUILD_PATH" "$APP_PATH/Contents/MacOS/"
cp "Resources/Info.plist" "$APP_PATH/Contents/"

if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$APP_PATH/Contents/Resources/"
fi

echo "Code signing..."
codesign --force --sign - "$APP_PATH"

echo "Registering with Launch Services..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_PATH"

echo ""
echo "Deployed to: $APP_PATH"
echo "Launching..."
open "$APP_PATH"

#!/bin/bash
set -e

APP_NAME="Spook"
APP_PATH="$HOME/Applications/$APP_NAME.app"
BUILD_PATH=".build/release/$APP_NAME"

echo "Building $APP_NAME..."
swift build -c release

if [ ! -f "$BUILD_PATH" ]; then
    echo "Error: Build failed - executable not found at $BUILD_PATH"
    exit 1
fi

echo "Creating app bundle at $APP_PATH..."

# Remove old bundle if exists
rm -rf "$APP_PATH"

# Create bundle structure
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

# Copy executable
cp "$BUILD_PATH" "$APP_PATH/Contents/MacOS/"

# Copy Info.plist
cp "Resources/Info.plist" "$APP_PATH/Contents/"

# Copy icon if it exists
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$APP_PATH/Contents/Resources/"
fi

echo "Code signing..."
codesign --force --sign - "$APP_PATH"

echo "Registering with Launch Services..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_PATH"

echo ""
echo "Successfully deployed to: $APP_PATH"
echo "Run with: open \"$APP_PATH\""

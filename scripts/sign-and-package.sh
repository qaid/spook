#!/bin/bash
set -e

APP_NAME="Spook"
BUNDLE_ID="com.spook.app"
APP_PATH="$HOME/Applications/$APP_NAME.app"
DMG_PATH="$HOME/Applications/$APP_NAME.dmg"
ENTITLEMENTS="Resources/Spook.entitlements"
SIGNING_IDENTITY="Developer ID Application: Qaid Jacobs (NC9DMTN36B)"
NOTARY_PROFILE="spook-notary"

# --- Build ---
echo "Building $APP_NAME (release)..."
swift build -c release

BUILD_PATH=".build/release/$APP_NAME"
if [ ! -f "$BUILD_PATH" ]; then
    echo "Error: Build failed - executable not found at $BUILD_PATH"
    exit 1
fi

# --- Create App Bundle ---
echo "Creating app bundle at $APP_PATH..."
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

cp "$BUILD_PATH" "$APP_PATH/Contents/MacOS/"
cp "Resources/Info.plist" "$APP_PATH/Contents/"

if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$APP_PATH/Contents/Resources/"
fi

# --- Code Sign with Hardened Runtime ---
echo "Code signing with Developer ID..."
codesign --force --deep --sign "$SIGNING_IDENTITY" \
    --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --timestamp \
    "$APP_PATH"

echo "Verifying code signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type execute --verbose=2 "$APP_PATH"

# --- Create DMG ---
echo "Creating DMG..."
rm -f "$DMG_PATH"

STAGING_DIR=$(mktemp -d)
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov -format UDZO \
    "$DMG_PATH"

rm -rf "$STAGING_DIR"

# --- Sign the DMG ---
echo "Signing DMG..."
codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG_PATH"

# --- Notarize ---
echo "Submitting for notarization..."
xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

echo "Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"

echo ""
echo "Done! Signed and notarized DMG at: $DMG_PATH"
echo "You can also run the app directly: open \"$APP_PATH\""

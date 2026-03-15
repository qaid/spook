#!/bin/bash
set -e

echo "Setting up Spook development environment..."

# Check Swift version
if ! command -v swift &> /dev/null; then
    echo "Error: Swift is not installed. Install Xcode or Xcode Command Line Tools."
    echo "  xcode-select --install"
    exit 1
fi

SWIFT_VERSION=$(swift --version 2>&1 | head -1)
echo "Found: $SWIFT_VERSION"

# Check macOS version (requires 14.0+)
MACOS_VERSION=$(sw_vers -productVersion)
MAJOR_VERSION=$(echo "$MACOS_VERSION" | cut -d. -f1)
if [ "$MAJOR_VERSION" -lt 14 ]; then
    echo "Error: macOS 14.0 (Sonoma) or later is required. You have $MACOS_VERSION."
    exit 1
fi
echo "macOS version: $MACOS_VERSION"

# Resolve dependencies
echo "Resolving Swift package dependencies..."
swift package resolve

# Build to verify everything works
echo "Building (debug)..."
swift build

echo ""
echo "Setup complete! Available scripts:"
echo "  ./scripts/dev.sh     - Build debug and run"
echo "  ./scripts/build.sh   - Build debug"
echo "  ./scripts/deploy.sh  - Build release, bundle .app, and run"

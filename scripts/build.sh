#!/bin/bash
set -e

CONFIG="${1:-debug}"

if [ "$CONFIG" = "release" ]; then
    echo "Building Spook (release)..."
    swift build -c release
else
    echo "Building Spook (debug)..."
    swift build
fi

echo "Build complete."

#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

# Kill existing Spook process if running
pkill -x Spook 2>/dev/null && echo "Stopped existing Spook process." && sleep 1 || true

echo "Building Spook (debug)..."
swift build

echo "Running Spook..."
.build/debug/Spook

#!/usr/bin/env bash
# Build the arm64 debug Android package for Video Run.
set -euo pipefail
cd "$(dirname "$0")/.."
flutter build apk --debug --target-platform android-arm64
mkdir -p dist
cp -f build/app/outputs/flutter-apk/app-debug.apk dist/video-run-arm64-debug.apk
echo "Wrote dist/video-run-arm64-debug.apk"

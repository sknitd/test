#!/bin/bash
# Builds WidgetForge.app (Release, universal, ad-hoc signed unless SIGN_IDENTITY is set) into build/.
# Usage: Scripts/build_app.sh [Debug|Release]
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIGURATION="${1:-Release}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
TEAM="${DEVELOPMENT_TEAM:-}"

xcodebuild -project WidgetForge.xcodeproj -scheme WidgetForge -configuration "$CONFIGURATION" \
  -derivedDataPath build/DerivedData -destination "generic/platform=macOS" \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" DEVELOPMENT_TEAM="$TEAM" build

APP="build/DerivedData/Build/Products/$CONFIGURATION/WidgetForge.app"
rm -rf build/WidgetForge.app
cp -R "$APP" build/WidgetForge.app
echo "Built build/WidgetForge.app"
lipo -archs build/WidgetForge.app/Contents/MacOS/WidgetForge
codesign --verify --deep --strict --verbose=2 build/WidgetForge.app

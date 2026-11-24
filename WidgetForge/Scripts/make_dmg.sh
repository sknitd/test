#!/bin/bash
# Packages build/WidgetForge.app into build/WidgetForge.dmg with an Applications shortcut.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -d build/WidgetForge.app ] || { echo "Run Scripts/build_app.sh first" >&2; exit 1; }
STAGE="$(mktemp -d)"
cp -R build/WidgetForge.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f build/WidgetForge.dmg
hdiutil create -volname "WidgetForge" -srcfolder "$STAGE" -ov -format UDZO build/WidgetForge.dmg
rm -rf "$STAGE"
hdiutil verify build/WidgetForge.dmg
echo "Created build/WidgetForge.dmg"

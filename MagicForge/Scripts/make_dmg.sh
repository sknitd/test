#!/usr/bin/env bash
# Creates a compressed DMG containing MagicForge.app and an /Applications symlink.
#
#   Scripts/make_dmg.sh [path/to/MagicForge.app]
#
# Output: $DIST_DIR/MagicForge-<version>.dmg (path printed on stdout).
# Environment: DIST_DIR (default <package>/dist), MF_VERSION, DMG_NAME (override file name).
set -euo pipefail

# shellcheck source=Scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
mf_require_macos "hdiutil"

DIST_DIR="${DIST_DIR:-$MF_ROOT/dist}"
APP="${1:-$DIST_DIR/$MF_APP_NAME.app}"
[[ -d "$APP" ]] || mf_die "$APP not found; run Scripts/build_app.sh or Scripts/build_xcode.sh first"

VERSION="$(mf_version)"
DMG="$DIST_DIR/${DMG_NAME:-$MF_APP_NAME-$VERSION.dmg}"

STAGING="$(mktemp -d -t mf-dmg.XXXXXX)"
trap 'rm -rf "${STAGING:?}"' EXIT

mf_log "Staging $APP"
ditto "$APP" "$STAGING/$MF_APP_NAME.app"
ln -s /Applications "$STAGING/Applications"

mkdir -p "$DIST_DIR"
rm -f "$DMG"
mf_log "hdiutil create $DMG"
hdiutil create -volname "$MF_APP_NAME $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" >&2
hdiutil verify "$DMG" >&2

mf_log "Created $DMG ($(du -h "$DMG" | cut -f1))"
printf '%s\n' "$DMG"

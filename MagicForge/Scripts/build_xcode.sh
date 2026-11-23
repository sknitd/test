#!/usr/bin/env bash
# Builds MagicForge.app through the Xcode project and copies it to dist/.
#
#   Scripts/build_xcode.sh                    # Release, universal, ad-hoc signed
#   CONFIGURATION=Debug Scripts/build_xcode.sh
#   CODESIGN_IDENTITY="Developer ID Application: Jane Doe (TEAMID)" DEVELOPMENT_TEAM=TEAMID Scripts/build_xcode.sh
#
# Environment:
#   CONFIGURATION        Debug | Release (default Release)
#   CODESIGN_IDENTITY    default "-" (ad-hoc), as set in the project
#   DEVELOPMENT_TEAM     team id, only needed with a real identity
#   DIST_DIR             where the .app is copied; default <package>/dist
#   DERIVED_DATA         default <package>/build/DerivedData
# Extra arguments are passed to xcodebuild.
set -euo pipefail

# shellcheck source=Scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
mf_require_macos "xcodebuild"

CONFIGURATION="${CONFIGURATION:-Release}"
DIST_DIR="${DIST_DIR:-$MF_ROOT/dist}"
DERIVED_DATA="${DERIVED_DATA:-$MF_ROOT/build/DerivedData}"
IDENTITY="${CODESIGN_IDENTITY:--}"

cd "$MF_ROOT"
settings=("CODE_SIGN_IDENTITY=$IDENTITY" "CODE_SIGN_STYLE=Manual")
if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
  settings+=("DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM")
fi
if [[ "$IDENTITY" != "-" ]]; then
  settings+=("OTHER_CODE_SIGN_FLAGS=--timestamp")
fi
if [[ -n "${MF_VERSION:-}" ]]; then settings+=("MARKETING_VERSION=$MF_VERSION"); fi
if [[ -n "${MF_BUILD_NUMBER:-}" ]]; then settings+=("CURRENT_PROJECT_VERSION=$MF_BUILD_NUMBER"); fi

mf_log "xcodebuild -scheme $MF_APP_NAME -configuration $CONFIGURATION"
xcodebuild \
  -project "$MF_ROOT/$MF_APP_NAME.xcodeproj" \
  -scheme "$MF_APP_NAME" \
  -configuration "$CONFIGURATION" \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  "$@" \
  build \
  "${settings[@]}"

BUILT_APP="$DERIVED_DATA/Build/Products/$CONFIGURATION/$MF_APP_NAME.app"
[[ -d "$BUILT_APP" ]] || mf_die "xcodebuild succeeded but $BUILT_APP is missing"

mkdir -p "$DIST_DIR"
rm -rf "${DIST_DIR:?}/${MF_APP_NAME:?}.app"
ditto "$BUILT_APP" "$DIST_DIR/$MF_APP_NAME.app"
codesign --verify --strict --verbose=2 "$DIST_DIR/$MF_APP_NAME.app"
mf_log "Architectures: $(lipo -archs "$DIST_DIR/$MF_APP_NAME.app/Contents/MacOS/$MF_APP_NAME")"
mf_log "Built $DIST_DIR/$MF_APP_NAME.app"

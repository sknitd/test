#!/usr/bin/env bash
# Builds dist/MagicForge.app with SwiftPM only (no Xcode project involved).
#
#   Scripts/build_app.sh                      # native architecture, ad-hoc signed
#   UNIVERSAL=1 Scripts/build_app.sh          # arm64 + x86_64 (needs full Xcode, not just CLT)
#   CODESIGN_IDENTITY="Developer ID Application: Jane Doe (TEAMID)" Scripts/build_app.sh
#
# Environment:
#   UNIVERSAL=1          build both architectures (`swift build --arch arm64 --arch x86_64`)
#   CODESIGN_IDENTITY    signing identity; default "-" (ad-hoc)
#   DIST_DIR             output directory; default <package>/dist
#   MF_VERSION, MF_BUILD_NUMBER   override Resources/Version.xcconfig
#   BINARY=/path         package this prebuilt executable instead of running `swift build`
set -euo pipefail

# shellcheck source=Scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

DIST_DIR="${DIST_DIR:-$MF_ROOT/dist}"
APP="$DIST_DIR/$MF_APP_NAME.app"
IDENTITY="${CODESIGN_IDENTITY:--}"
VERSION="$(mf_version)"
BUILD_NUMBER="$(mf_build_number)"

cd "$MF_ROOT"

if [[ -n "${BINARY:-}" ]]; then
  [[ -f "$BINARY" ]] || mf_die "BINARY=$BINARY does not exist"
  mf_log "Packaging prebuilt binary $BINARY"
else
  mf_require_macos "Building the app"
  SWIFT_BIN="$(mf_swift)"
  build_args=(-c release --product "$MF_SPM_PRODUCT")
  if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    build_args+=(--arch arm64 --arch x86_64)
  fi
  mf_log "swift build ${build_args[*]}"
  "$SWIFT_BIN" build "${build_args[@]}"
  BINARY="$("$SWIFT_BIN" build "${build_args[@]}" --show-bin-path)/$MF_SPM_PRODUCT"
  [[ -f "$BINARY" ]] || mf_die "expected executable not found at $BINARY"
fi

mf_log "Assembling $APP (version $VERSION, build $BUILD_NUMBER)"
rm -rf "${DIST_DIR:?}/${MF_APP_NAME:?}.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/$MF_APP_NAME"
chmod 755 "$APP/Contents/MacOS/$MF_APP_NAME"
cp "$MF_ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Substitute the Xcode build-setting references used in Resources/Info.plist.
sed \
  -e "s|\$(PRODUCT_NAME)|$MF_APP_NAME|g" \
  -e "s|\$(EXECUTABLE_NAME)|$MF_APP_NAME|g" \
  -e "s|\$(PRODUCT_BUNDLE_IDENTIFIER)|$MF_BUNDLE_ID|g" \
  -e "s|\$(MARKETING_VERSION)|$VERSION|g" \
  -e "s|\$(CURRENT_PROJECT_VERSION)|$BUILD_NUMBER|g" \
  -e "s|\$(MACOSX_DEPLOYMENT_TARGET)|$MF_DEPLOYMENT_TARGET|g" \
  "$MF_ROOT/Resources/Info.plist" > "$APP/Contents/Info.plist"
# shellcheck disable=SC2016  # literal $( is intended
if grep -q '\$(' "$APP/Contents/Info.plist"; then
  # shellcheck disable=SC2016
  grep -n '\$(' "$APP/Contents/Info.plist" >&2
  mf_die "unsubstituted build variables left in Info.plist"
fi
if command -v plutil >/dev/null 2>&1; then
  plutil -lint "$APP/Contents/Info.plist" >/dev/null
fi

# Optional: compile the asset catalog (accent colour, icon variants) when actool exists.
# The app works without Assets.car: the icon comes from AppIcon.icns.
if mf_is_macos && xcrun --find actool >/dev/null 2>&1; then
  partial="$(mktemp -t mf-actool.XXXXXX)"
  if xcrun actool "$MF_ROOT/Resources/Assets.xcassets" \
      --compile "$APP/Contents/Resources" \
      --platform macosx --minimum-deployment-target "$MF_DEPLOYMENT_TARGET" \
      --app-icon AppIcon --accent-color AccentColor \
      --output-partial-info-plist "$partial" >/dev/null 2>&1; then
    mf_log "Compiled Assets.xcassets with actool"
  else
    mf_warn "actool failed; continuing with AppIcon.icns only"
    cp "$MF_ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
  fi
  rm -f "$partial"
fi

if command -v codesign >/dev/null 2>&1; then
  sign_args=(--force --options runtime --entitlements "$MF_ENTITLEMENTS" --sign "$IDENTITY")
  if [[ "$IDENTITY" == "-" ]]; then
    sign_args+=(--timestamp=none)
  else
    sign_args+=(--timestamp)
  fi
  mf_log "codesign --sign \"$IDENTITY\" (hardened runtime)"
  codesign "${sign_args[@]}" "$APP"
  codesign --verify --strict --verbose=2 "$APP"
else
  mf_warn "codesign not available; $APP is UNSIGNED and will not launch on Apple silicon"
fi

if command -v lipo >/dev/null 2>&1; then
  mf_log "Architectures: $(lipo -archs "$APP/Contents/MacOS/$MF_APP_NAME")"
fi
mf_log "Built $APP"

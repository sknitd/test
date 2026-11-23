#!/usr/bin/env bash
# Developer ID release: build, sign, package, notarize and staple.
#
# Required environment (the script refuses to run without them):
#   DEVELOPER_ID_APPLICATION   e.g. "Developer ID Application: Jane Doe (ABCDE12345)"
#                              (must be in the login keychain: `security find-identity -v -p codesigning`)
#   NOTARY_PROFILE             name of a notarytool keychain profile, created once with:
#                                xcrun notarytool store-credentials "<profile>" \
#                                  --apple-id "<apple id>" --team-id "<TEAMID>" --password "<app-specific password>"
# Optional:
#   BUILD_WITH=spm|xcode       build path (default xcode: universal binary + compiled assets)
#   SKIP_BUILD=1               notarize the existing dist/MagicForge.app (must already be Developer ID signed)
#   DIST_DIR                   default <package>/dist
#
# No credentials are read from or written to the repository. See docs/RELEASE.md.
set -euo pipefail

# shellcheck source=Scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
missing=()
[[ -n "${DEVELOPER_ID_APPLICATION:-}" ]] || missing+=("DEVELOPER_ID_APPLICATION")
[[ -n "${NOTARY_PROFILE:-}" ]] || missing+=("NOTARY_PROFILE")
if (( ${#missing[@]} > 0 )); then
  mf_die "missing required environment: ${missing[*]} (see the header of $0)"
fi
case "$DEVELOPER_ID_APPLICATION" in
  "Developer ID Application:"*) ;;
  *) mf_die "DEVELOPER_ID_APPLICATION must be a 'Developer ID Application: …' identity; ad-hoc or development signatures cannot be notarized" ;;
esac

mf_require_macos "Notarization"

SCRIPTS="$MF_ROOT/Scripts"
DIST_DIR="${DIST_DIR:-$MF_ROOT/dist}"
APP="$DIST_DIR/$MF_APP_NAME.app"
export DIST_DIR

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  team="$(printf '%s' "$DEVELOPER_ID_APPLICATION" | sed -n 's/.*(\([A-Z0-9]*\))$/\1/p')"
  case "${BUILD_WITH:-xcode}" in
    xcode) CODESIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" DEVELOPMENT_TEAM="$team" "$SCRIPTS/build_xcode.sh" ;;
    spm) CODESIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" UNIVERSAL=1 "$SCRIPTS/build_app.sh" ;;
    *) mf_die "BUILD_WITH must be 'xcode' or 'spm'" ;;
  esac
fi
[[ -d "$APP" ]] || mf_die "$APP not found"

mf_log "Checking the app signature"
codesign --verify --deep --strict --verbose=2 "$APP"
details="$(codesign -dvv "$APP" 2>&1)"
grep -q "Authority=Developer ID Application" <<<"$details" || mf_die "$APP is not signed with a Developer ID identity"
grep -q "flags=.*runtime" <<<"$details" || mf_die "$APP is not signed with the hardened runtime"
grep -q "Timestamp=" <<<"$details" || mf_die "$APP has no secure timestamp"

DMG="$("$SCRIPTS/make_dmg.sh" "$APP")"
mf_log "Signing $DMG"
codesign --force --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$DMG"

mf_log "Submitting to the Apple notary service (profile: $NOTARY_PROFILE)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

mf_log "Stapling"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

mf_log "Gatekeeper assessment"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

mf_log "Notarized and stapled: $DMG"
printf '%s\n' "$DMG"

#!/bin/bash
# Notarises build/WidgetForge.dmg. Requires a Developer ID build (SIGN_IDENTITY="Developer ID Application: …"
# passed to build_app.sh) and a notarytool keychain profile:
#   xcrun notarytool store-credentials widgetforge --apple-id you@example.com --team-id TEAMID
# Not run in CI: it needs credentials that are never stored in this repository.
set -euo pipefail
cd "$(dirname "$0")/.."
PROFILE="${NOTARY_PROFILE:-widgetforge}"
xcrun notarytool submit build/WidgetForge.dmg --keychain-profile "$PROFILE" --wait
xcrun stapler staple build/WidgetForge.dmg
spctl --assess --type open --context context:primary-signature --verbose build/WidgetForge.dmg

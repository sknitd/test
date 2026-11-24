#!/usr/bin/env bash
# Verifies that a built MagicForge.app really targets the minimum macOS version:
#   - every architecture slice of the executable has LC_BUILD_VERSION minos == the deployment target
#   - Info.plist LSMinimumSystemVersion == the deployment target
# Usage: Scripts/check_min_os.sh path/to/MagicForge.app [more.app ...]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=Scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

if [ "$#" -eq 0 ]; then
  echo "usage: $0 path/to/App.app [...]" >&2
  exit 2
fi

want="$MF_DEPLOYMENT_TARGET"
status=0

for app in "$@"; do
  plist="$app/Contents/Info.plist"
  exe_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")"
  exe="$app/Contents/MacOS/$exe_name"
  plist_min="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$plist")"
  echo "== $app"
  echo "LSMinimumSystemVersion: $plist_min"
  if [ "$plist_min" != "$want" ]; then
    echo "ERROR: LSMinimumSystemVersion is $plist_min, expected $want" >&2
    status=1
  fi
  for arch in $(lipo -archs "$exe"); do
    minos="$(otool -arch "$arch" -l "$exe" | awk '/LC_BUILD_VERSION/ {found=1} found && $1 == "minos" {print $2; exit}')"
    echo "$arch minos: ${minos:-unknown}"
    if [ "$minos" != "$want" ]; then
      echo "ERROR: $arch slice has minos '${minos:-unknown}', expected $want" >&2
      status=1
    fi
  done
done

exit "$status"

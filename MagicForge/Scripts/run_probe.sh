#!/usr/bin/env bash
# Builds and runs mfprobe, the command-line hardware / input diagnostics tool.
#
#   Scripts/run_probe.sh --self-check
#   Scripts/run_probe.sh --help            # options are defined by mfprobe itself
#   PROBE_CONFIGURATION=release Scripts/run_probe.sh …
#
# All arguments are passed to mfprobe unchanged.
set -euo pipefail

# shellcheck source=Scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
mf_require_macos "mfprobe (IOKit HID and MultitouchSupport)"

SWIFT_BIN="$(mf_swift)"
CONFIGURATION="${PROBE_CONFIGURATION:-debug}"

cd "$MF_ROOT"
mf_log "swift build -c $CONFIGURATION --product mfprobe"
"$SWIFT_BIN" build -c "$CONFIGURATION" --product mfprobe >&2
PROBE="$("$SWIFT_BIN" build -c "$CONFIGURATION" --show-bin-path)/mfprobe"
[[ -x "$PROBE" ]] || mf_die "mfprobe was not produced at $PROBE"
exec "$PROBE" "$@"

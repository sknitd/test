#!/usr/bin/env bash
# Runs the unit tests.
#
#   Scripts/test.sh                       # `swift test` for the whole package
#   Scripts/test.sh --per-module          # each portable module in isolation (MF_ONLY=<module>)
#   Scripts/test.sh --module MFGestures   # one module in isolation
#   Scripts/test.sh -- --filter GestureTests   # arguments after -- go to `swift test`
#
# The per-module mode uses the MF_ONLY switch in Package.swift and a private scratch
# directory per module (.build-only/<module>), so one module can be tested while another
# does not compile. On Linux only the portable modules exist; that is what `swift test` runs.
set -euo pipefail

# shellcheck source=Scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

PORTABLE_MODULES=(MFCore MFGestures MFProfiles MFAutomation MFIntegrations MFEngine)

mode="all"
modules=()
extra=()
while (( $# > 0 )); do
  case "$1" in
    --per-module) mode="modules"; modules=("${PORTABLE_MODULES[@]}") ;;
    --module)
      [[ $# -ge 2 ]] || mf_die "--module needs a name (one of: ${PORTABLE_MODULES[*]})"
      mode="modules"; modules+=("$2"); shift ;;
    --) shift; extra=("$@"); break ;;
    -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) mf_die "unknown argument: $1 (see --help)" ;;
  esac
  shift
done

SWIFT_BIN="$(mf_swift)"
cd "$MF_ROOT"

if [[ "$mode" == "all" ]]; then
  mf_log "swift test ${extra[*]:-}"
  exec "$SWIFT_BIN" test ${extra[@]+"${extra[@]}"}
fi

failed=()
for module in "${modules[@]}"; do
  mf_log "MF_ONLY=$module swift test"
  if ! MF_ONLY="$module" "$SWIFT_BIN" test --scratch-path "$MF_ROOT/.build-only/$module" ${extra[@]+"${extra[@]}"}; then
    failed+=("$module")
  fi
done

if (( ${#failed[@]} > 0 )); then
  mf_die "tests failed in: ${failed[*]}"
fi
mf_log "All ${#modules[@]} module(s) passed"

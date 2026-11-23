#!/usr/bin/env bash
# Shared helpers for the MagicForge scripts. Source it; do not execute it.
# shellcheck shell=bash

MF_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export MF_ROOT

MF_APP_NAME="MagicForge"
MF_BUNDLE_ID="com.magicforge.app"
MF_DEPLOYMENT_TARGET="14.0"
MF_SPM_PRODUCT="MagicForgeApp"
MF_ENTITLEMENTS="$MF_ROOT/Resources/MagicForge.entitlements"
MF_VERSION_FILE="$MF_ROOT/Resources/Version.xcconfig"
export MF_APP_NAME MF_BUNDLE_ID MF_DEPLOYMENT_TARGET MF_SPM_PRODUCT MF_ENTITLEMENTS

mf_log() { printf '==> %s\n' "$*" >&2; }
mf_warn() { printf 'warning: %s\n' "$*" >&2; }
mf_die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# Reads `NAME = value` from Resources/Version.xcconfig.
mf_xcconfig_value() {
  local value
  value="$(sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\([^[:space:]]*\).*$/\1/p" "$MF_VERSION_FILE" | head -n 1)"
  [[ -n "$value" ]] || mf_die "$1 not found in $MF_VERSION_FILE"
  printf '%s\n' "$value"
}

# Environment overrides win, so CI can stamp builds without editing the file.
mf_version() { printf '%s\n' "${MF_VERSION:-$(mf_xcconfig_value MARKETING_VERSION)}"; }
mf_build_number() { printf '%s\n' "${MF_BUILD_NUMBER:-$(mf_xcconfig_value CURRENT_PROJECT_VERSION)}"; }

mf_is_macos() { [[ "$(uname -s)" == "Darwin" ]]; }
mf_require_macos() { mf_is_macos || mf_die "$1 needs macOS (this is $(uname -s))."; }

# Prints the swift executable to use: $SWIFT, swift on PATH, or the Linux dev toolchain.
mf_swift() {
  if [[ -n "${SWIFT:-}" ]]; then
    printf '%s\n' "$SWIFT"
  elif command -v swift >/dev/null 2>&1; then
    command -v swift
  elif [[ -x /opt/swift/usr/bin/swift ]]; then
    printf '%s\n' /opt/swift/usr/bin/swift
  else
    mf_die "swift not found; install a Swift 5.9+ toolchain or set SWIFT=/path/to/swift"
  fi
}

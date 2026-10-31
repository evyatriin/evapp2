#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
DART_OBFUSCATE="${DART_OBFUSCATE:-false}"
# apk (default) or appbundle (.aab, required for Play Store submission).
BUILD_FORMAT="${BUILD_FORMAT:-apk}"

required_vars=(
  BACKEND_URL
  SUPABASE_URL
  SUPABASE_ANON_KEY
)

for var_name in "${required_vars[@]}"; do
  if [[ -z "${!var_name:-}" ]]; then
    echo "Missing required env var: ${var_name}" >&2
    exit 1
  fi
done

cd "${ROOT_DIR}"

build_args=(
  --release
  --dart-define=BACKEND_URL="${BACKEND_URL}"
  --dart-define=SUPABASE_URL="${SUPABASE_URL}"
  --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY}"
  --dart-define=SOS_ENABLED="${SOS_ENABLED:-false}"
)

# Play Store app bundles must be a single artifact, so --split-per-abi only
# applies to the APK build.
if [[ "${BUILD_FORMAT}" == "apk" ]]; then
  build_args+=(--split-per-abi)
fi

# Forward optional defines only when set, so defaults in AppConfig stay intact.
if [[ -n "${SENTRY_DSN:-}" ]]; then
  build_args+=(--dart-define=SENTRY_DSN="${SENTRY_DSN}")
fi
if [[ -n "${ADS_ENABLED:-}" ]]; then
  build_args+=(--dart-define=ADS_ENABLED="${ADS_ENABLED}")
fi
if [[ -n "${ADMOB_BANNER_ANDROID:-}" ]]; then
  build_args+=(--dart-define=ADMOB_BANNER_ANDROID="${ADMOB_BANNER_ANDROID}")
fi
if [[ -n "${ADMOB_BANNER_IOS:-}" ]]; then
  build_args+=(--dart-define=ADMOB_BANNER_IOS="${ADMOB_BANNER_IOS}")
fi

# Android startup is stable with the standard release build, but the obfuscated
# variant has triggered a shared_preferences/Supabase startup failure on device.
if [[ "${DART_OBFUSCATE}" == "true" ]]; then
  build_args+=(
    --obfuscate
    --split-debug-info=build/app/outputs/symbols
  )
fi

case "${BUILD_FORMAT}" in
  apk|appbundle) ;;
  *)
    echo "Invalid BUILD_FORMAT: ${BUILD_FORMAT} (use 'apk' or 'appbundle')" >&2
    exit 1
    ;;
esac

"${FLUTTER_BIN}" build "${BUILD_FORMAT}" "${build_args[@]}" "$@"

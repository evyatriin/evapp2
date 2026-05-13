#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
DART_OBFUSCATE="${DART_OBFUSCATE:-false}"

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
  --split-per-abi
  --dart-define=BACKEND_URL="${BACKEND_URL}"
  --dart-define=SUPABASE_URL="${SUPABASE_URL}"
  --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY}"
)

# Android startup is stable with the standard release build, but the obfuscated
# variant has triggered a shared_preferences/Supabase startup failure on device.
if [[ "${DART_OBFUSCATE}" == "true" ]]; then
  build_args+=(
    --obfuscate
    --split-debug-info=build/app/outputs/symbols
  )
fi

"${FLUTTER_BIN}" build apk "${build_args[@]}" "$@"

#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

source scripts/flutter-sdk.sh
export CI=true
flutter --version
flutter pub get --enforce-lockfile

build_args=(build web --release)
if [[ -n "${SUPABASE_URL:-}" || -n "${SUPABASE_PUBLISHABLE_KEY:-}" ]]; then
  if [[ "${SUPABASE_URL:-}" != https://* || "${SUPABASE_PUBLISHABLE_KEY:-}" != sb_publishable_* ]]; then
    echo 'Set both SUPABASE_URL (HTTPS) and SUPABASE_PUBLISHABLE_KEY (publishable only).' >&2
    exit 1
  fi
  build_args+=("--dart-define=SUPABASE_URL=$SUPABASE_URL")
  build_args+=("--dart-define=SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY")
else
  echo 'Building the offline shell; Supabase configuration was not supplied.'
fi
flutter "${build_args[@]}"
test -s build/web/index.html
test -s build/web/flutter_bootstrap.js
test -s build/web/main.dart.js

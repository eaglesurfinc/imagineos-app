#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Match the verified development SDK rather than following a moving channel.
readonly flutter_version='3.47.2'
readonly flutter_revision='d3b14c876900e553bc736ca19295fc09e3853e8e'
sdk_dir="${IMAGINEOS_FLUTTER_SDK_DIR:-$PWD/.vercel/flutter}"

if [[ ! -d "$sdk_dir/.git" ]]; then
  git clone --depth 1 --branch "$flutter_version" https://github.com/flutter/flutter.git "$sdk_dir"
fi
if [[ "$(git -C "$sdk_dir" rev-parse HEAD)" != "$flutter_revision" ]]; then
  echo 'Flutter SDK revision differs from the verified build version.' >&2
  exit 1
fi

export PATH="$sdk_dir/bin:$PATH"
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

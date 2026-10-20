#!/usr/bin/env bash
# Source from a build/check shell; keep Vercel and GitHub on the verified SDK.
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

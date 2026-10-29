#!/bin/bash
set -euo pipefail

kam_root=$(cd "$(dirname "$0")/../.." && pwd)
kam_source="$kam_root/assets.local/toolchain/fpc-source"
kam_compiler="$kam_source/compiler/ppca64"
if [[ ! -x "$kam_compiler" ]]; then
  echo 'Run platform/macos/bootstrap.sh first.' >&2
  exit 1
fi

# Keep the pinned compiler independent of a system fpc.cfg and its RTL version.
kam_args=("-Fu$kam_source/rtl/units/aarch64-darwin")
for kam_units in "$kam_source"/packages/*/units/aarch64-darwin; do
  # Free Vision's Menus unit conflicts with Apple's Menus unit used by Cocoa.
  [[ "$kam_units" == */fv/units/* ]] && continue
  [[ -d "$kam_units" ]] && kam_args+=("-Fu$kam_units")
done
exec "$kam_compiler" -n "-XR$(xcrun --show-sdk-path)" -WM15.0 -ap -k-no_fixup_chains "$@" "${kam_args[@]}"

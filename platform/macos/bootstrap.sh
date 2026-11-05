#!/bin/bash
set -euo pipefail

kam_root=$(cd "$(dirname "$0")/../.." && pwd)
kam_tools="$kam_root/assets.local/toolchain"
kam_fpc_revision=363f31341dd584f2ab897423457717b463f702b5
kam_lcl_revision=62c14a4d18c81f222127d42ce9b89b922c63fcbf

if [[ $(uname -s) != Darwin || $(uname -m) != arm64 ]]; then
  echo 'This build requires native Apple Silicon macOS.' >&2
  exit 1
fi
kam_bootstrap=$(command -v ppca64 || true)
if [[ -z "$kam_bootstrap" || $("$kam_bootstrap" -iV) != 3.2.2 ]]; then
  echo 'Install native Free Pascal 3.2.2 first (brew install fpc).' >&2
  exit 1
fi

mkdir -p "$kam_tools/logs"
kam_checkout() {
  local kam_url=$1 kam_dir=$2 kam_revision=$3
  if [[ ! -d "$kam_dir/.git" ]]; then
    git init "$kam_dir"
    git -C "$kam_dir" remote add origin "$kam_url"
    git -C "$kam_dir" fetch --depth 1 origin "$kam_revision"
    git -C "$kam_dir" checkout --detach FETCH_HEAD
  fi
  if [[ $(git -C "$kam_dir" rev-parse HEAD) != "$kam_revision" ]]; then
    echo "Unexpected dependency revision in $kam_dir" >&2
    exit 1
  fi
}

kam_checkout https://gitlab.com/freepascal.org/fpc/source.git "$kam_tools/fpc-source" "$kam_fpc_revision"
kam_checkout https://gitlab.com/freepascal.org/lazarus/lazarus.git "$kam_tools/lazarus" "$kam_lcl_revision"
git -C "$kam_root" submodule update --init src/ext/pascalscript_submodule

# BASS is the upstream audio backend. Pin the archive rather than silently
# accepting a changed download at the vendor's stable URL.
kam_bass_archive="$kam_root/assets.local/downloads/bass24-osx.zip"
kam_bass_sha=dfadd6238896b02b144b2870655fb9ee2445fc84d5c00f7e1c56faf9343ce59c
mkdir -p "$(dirname "$kam_bass_archive")" "$kam_tools/bass"
if [[ ! -f "$kam_bass_archive" ]]; then
  curl --fail --location --retry 3 --output "$kam_bass_archive.part" https://www.un4seen.com/files/bass24-osx.zip
  mv "$kam_bass_archive.part" "$kam_bass_archive"
fi
[[ $(shasum -a 256 "$kam_bass_archive" | cut -d ' ' -f 1) == "$kam_bass_sha" ]] || {
  echo 'BASS archive checksum differs from the tested version.' >&2
  exit 1
}
unzip -oq "$kam_bass_archive" -d "$kam_tools/bass"

# The bootstrap compiler emits unaligned fixups rejected by recent Apple ld.
# Disable chained fixups; use the selected SDK explicitly for fpmake as well.
kam_options="-XR$(xcrun --show-sdk-path) -WM15.0 -ap -k-no_fixup_chains"
if ! make -C "$kam_tools/fpc-source" -j4 compiler_cycle FPC="$kam_bootstrap" OPT="$kam_options" > "$kam_tools/logs/fpc-build.log" 2>&1; then
  tail -50 "$kam_tools/logs/fpc-build.log"
  exit 1
fi
# The compiler cycle builds a private RTL with whole-program feedback.
# Rebuild the public RTL/packages without that compiler-only feedback.
for kam_target in rtl_clean packages_clean rtl_smart packages_smart; do
  if ! make -C "$kam_tools/fpc-source" -j4 "$kam_target" \
    FPC="$kam_tools/fpc-source/compiler/ppca64" \
    FPCFPMAKE="$kam_tools/fpc-source/compiler/ppca64" \
    OPT="$kam_options" FPCMAKEOPT="$kam_options" >> "$kam_tools/logs/fpc-build.log" 2>&1; then
    tail -50 "$kam_tools/logs/fpc-build.log"
    exit 1
  fi
done

# Compile the Cocoa library only. Neither Lazarus IDE nor lazbuild is needed.
for kam_component in packager/registration components/lazutils components/freetype lcl; do
  if ! make -C "$kam_tools/lazarus/$kam_component" clean all PP="$kam_root/platform/macos/fpc.sh" LCL_PLATFORM=cocoa > "$kam_tools/logs/$(basename "$kam_component").log" 2>&1; then
    tail -50 "$kam_tools/logs/$(basename "$kam_component").log"
    exit 1
  fi
done

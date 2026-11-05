#!/bin/bash
set -euo pipefail

kam_root=$(cd "$(dirname "$0")/../.." && pwd)
kam_lazarus="$kam_root/assets.local/toolchain/lazarus"
kam_build="$kam_root/assets.local/build/macos"
mkdir -p "$kam_build/units" "$kam_build/bin"

# The pinned FPC development compiler can crash while incrementally rebuilding
# this project's circular unit dependencies. A clean game rebuild is reliable;
# keep RTL/LCL and third-party units cached. Build probes after the game.
if [[ ${KAM_PASCAL_ENTRY:-KaM_Remake.dpr} == KaM_Remake.dpr ]]; then
  find "$kam_build/units" -maxdepth 1 -type f \( -name 'KM_*.ppu' -o -name 'KM_*.o' -o -name 'KM_*.s' \) -delete
fi

python3 "$kam_root/platform/macos/prepare_forms.py"
python3 "$kam_root/platform/macos/prepare_pascal_script.py"

kam_args=(-Mdelphi -dLCL -dLCLcocoa -dDBG_SKIP_SECURE_AUTH -dPUREPASCAL -k-lbass -k-framework -kUserNotifications -gl -gw -O1)
kam_args+=("-Fi$kam_root" "-Fi$kam_build/forms" "-FU$kam_build/units" "-FE$kam_build/bin")
kam_args+=("-Fu$kam_root/assets.local/toolchain/bass/delphi" "-Fl$kam_root/assets.local/toolchain/bass" -k-rpath "-k$kam_root/assets.local/toolchain/bass" -dMACOS)
kam_args+=("-Fu$kam_root/assets.local/toolchain/pascalscript/Source" "-Fi$kam_root/assets.local/toolchain/pascalscript/Source")
kam_args+=("-Fu$kam_lazarus/packager/units/aarch64-darwin")
kam_args+=("-Fu$kam_lazarus/components/lazutils/lib/aarch64-darwin")
kam_args+=("-Fu$kam_lazarus/components/freetype/lib/aarch64-darwin")
kam_args+=("-Fu$kam_lazarus/lcl/units/aarch64-darwin")
kam_args+=("-Fu$kam_lazarus/lcl/units/aarch64-darwin/cocoa")
kam_args+=("-Fu$kam_lazarus/components/opengl")

# Use the current game's units, excluding obsolete/vendored widgetsets.
while IFS= read -r kam_dir; do
  kam_args+=("-Fu$kam_dir" "-Fi$kam_dir")
done < <(find "$kam_root/src" -type d \( -path "$kam_root/src/ext" -o -path "$kam_root/src/unused" \) -prune -o -type d -print)
for kam_dir in ext ext/LNet ext/OggVorbis; do
  kam_args+=("-Fu$kam_root/src/$kam_dir" "-Fi$kam_root/src/$kam_dir")
done

cd "$kam_root"
exec "$kam_root/platform/macos/fpc.sh" "${kam_args[@]}" "$@" "${KAM_PASCAL_ENTRY:-KaM_Remake.dpr}"

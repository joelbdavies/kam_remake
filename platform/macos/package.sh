#!/bin/bash
set -euo pipefail

kam_root=$(cd "$(dirname "$0")/../.." && pwd)
kam_build="$kam_root/assets.local/build/macos"
kam_app="$kam_build/KaM Remake.app"
kam_bass="$kam_root/assets.local/toolchain/bass"

[[ -x "$kam_build/bin/KaM_Remake" ]] || { echo 'Run platform/macos/build.sh first.' >&2; exit 1; }
mkdir -p "$kam_app/Contents/MacOS" "$kam_app/Contents/Frameworks" "$kam_app/Contents/Resources"
cp "$kam_build/bin/KaM_Remake" "$kam_app/Contents/MacOS/KaM_Remake"
lipo "$kam_bass/libbass.dylib" -thin arm64 -output "$kam_app/Contents/Frameworks/libbass.dylib"
cp "$kam_bass/bass.txt" "$kam_app/Contents/Resources/BASS.txt"
install_name_tool -delete_rpath "$kam_bass" -add_rpath '@executable_path/../Frameworks' "$kam_app/Contents/MacOS/KaM_Remake"

# Reuse the upstream artwork for standard and Retina Dock/Finder sizes.
kam_iconset="$kam_build/KaMRemake.iconset"
mkdir -p "$kam_iconset"
for kam_size in 16 32 128 256 512; do
  sips --resampleHeightWidth "$kam_size" "$kam_size" "$kam_root/KaM_Remake_Icon.png" \
    --out "$kam_iconset/icon_${kam_size}x${kam_size}.png" >/dev/null
  kam_retina=$((kam_size * 2))
  sips --resampleHeightWidth "$kam_retina" "$kam_retina" "$kam_root/KaM_Remake_Icon.png" \
    --out "$kam_iconset/icon_${kam_size}x${kam_size}@2x.png" >/dev/null
done
iconutil --convert icns "$kam_iconset" --output "$kam_app/Contents/Resources/KaMRemake.icns"

python3 - "$kam_app/Contents/Info.plist" <<'PY'
import plistlib
import sys

with open(sys.argv[1], 'wb') as output:
    plistlib.dump({
        'CFBundleIdentifier': 'org.kamremake.native.mvp',
        'CFBundleName': 'KaM Remake',
        'CFBundleDisplayName': 'KaM Remake',
        'CFBundleExecutable': 'KaM_Remake',
        'CFBundleIconFile': 'KaMRemake.icns',
        'CFBundlePackageType': 'APPL',
        'CFBundleVersion': '16406',
        'CFBundleShortVersionString': '0.1',
        'LSMinimumSystemVersion': '15.0',
        'NSHighResolutionCapable': True,
    }, output)
PY

codesign --force --sign - "$kam_app/Contents/Frameworks/libbass.dylib"
codesign --force --sign - "$kam_app"
codesign --verify --deep --strict "$kam_app"
echo "$kam_app"

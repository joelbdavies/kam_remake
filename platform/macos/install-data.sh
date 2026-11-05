#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo 'Usage: platform/macos/install-data.sh /path/to/staged-game-data' >&2
  exit 1
fi
kam_source=$(cd "$1" && pwd)
kam_destination="${KAM_DATA_DIR:-$HOME/Library/Application Support/KaM Remake}"

for kam_required in \
  'data/Sprites' \
  'Campaigns/The Shattered Kingdom/TSK01/TSK01.dat' \
  'Campaigns/The Peasants Rebellion/TPR01/TPR01.dat' \
  'Music'; do
  [[ -e "$kam_source/$kam_required" ]] || { echo "Missing game data: $kam_required" >&2; exit 1; }
done

mkdir -p "$kam_destination"
# Keep existing saves, settings, and user edits. Only seed missing game assets.
for kam_directory in data Campaigns Maps MapsMP Music Sounds Tutorials 'Modding graphics'; do
  if [[ -d "$kam_source/$kam_directory" ]]; then
    rsync -a --ignore-existing "$kam_source/$kam_directory" "$kam_destination/"
  fi
done
echo "Game data installed in: $kam_destination"

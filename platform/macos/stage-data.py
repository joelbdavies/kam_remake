#!/usr/bin/env python3
"""Assemble locally owned KaM data in the overlay order required by upstream."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

root = Path(__file__).resolve().parents[2]
resources = ['data', 'Campaigns', 'Maps', 'MapsMP', 'Tutorials', 'Music', 'Sounds', 'Modding graphics']
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--gog-data', type=Path, required=True, help='Extracted original data/ directory')
parser.add_argument('--remake-data', type=Path, required=True, help='Extracted Remake app/ directory')
parser.add_argument('--output', type=Path, required=True, help='New or empty staging directory')
args = parser.parse_args()
original, remake, output = (path.resolve() for path in (args.gog_data, args.remake_data, args.output))
if not (original / 'sfx').is_dir() or not (original / 'gfx').is_dir():
    parser.error('--gog-data must point to the original game data directory')
if not (remake / 'Campaigns').is_dir() or not (remake / 'data/sprites').is_dir():
    parser.error('--remake-data must point to the extracted Remake app directory')
if output.exists() and any(output.iterdir()):
    parser.error('--output must be empty; use install-data.sh to seed an existing player installation')
output.mkdir(parents=True, exist_ok=True)
shutil.copytree(original, output / 'data', dirs_exist_ok=True)
for directory in resources:
    if (remake / directory).exists():
        shutil.copytree(remake / directory, output / directory, dirs_exist_ok=True)
# The checkout defines/text/fonts must match the executable, not the RC installer.
tracked = subprocess.check_output(['git', '-C', str(root), 'ls-files', '-z', '--', *resources])
for name in tracked.decode().split('\0'):
    if not name:
        continue
    destination = output / name
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(root / name, destination)
# The engine uses Sprites; a two-step rename also works on case-insensitive APFS.
if (output / 'data/sprites').is_dir():
    (output / 'data/sprites').rename(output / 'data/sprites-renaming')
    (output / 'data/sprites-renaming').rename(output / 'data/Sprites')
for title, code, count in [('The Shattered Kingdom', 'TSK', 20), ('The Peasants Rebellion', 'TPR', 14)]:
    for number in range(1, count + 1):
        name = f'{code}{number:02d}'
        for extension in ['dat', 'map', 'script', 'eng.mp3']:
            path = output / 'Campaigns' / title / name / f'{name}.{extension}'
            if not path.is_file():
                raise SystemExit(f'Missing retail campaign asset: {path}')
files = []
for path in sorted(output.rglob('*')):
    if path.is_file():
        files.append({'path': str(path.relative_to(output)), 'bytes': path.stat().st_size,
                      'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
manifest = {'checkout': subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip(),
            'overlay_order': ['owned original data', 'Remake resources', 'tracked checkout resources'],
            'files': files}
(output / 'asset-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(f'Staged {len(files)} files, all 34 retail missions, in {output}')

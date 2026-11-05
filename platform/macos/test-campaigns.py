#!/usr/bin/env python3
"""Exercise retail campaigns using disposable local data, through the native game."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import time

root = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--data-dir', type=Path, required=True,
                    help='Staged test data; this writes saves and campaign progress here')
parser.add_argument('--output', type=Path, default=root / 'assets.local/campaign-tests')
parser.add_argument('--ticks', type=int, default=600)
parser.add_argument('--seed', type=int, help='Positive game RNG seed for reproducing a simulation')
parser.add_argument('--missions', nargs='+', help='Optional selection such as TSK1 TPR14')
args = parser.parse_args()
if args.ticks < 120:
    parser.error('--ticks must be at least 120 to cover initial script events')
if args.seed is not None and not 1 <= args.seed <= 2147483647:
    parser.error('--seed must be a positive signed 32-bit integer')
data = args.data_dir.resolve()
if data == Path.home() / 'Library/Application Support/KaM Remake':
    parser.error('Use staged test data, not the player installation')
if not (data / 'Campaigns').is_dir():
    parser.error('The data directory must contain Campaigns')
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)
missions = args.missions or [f'{campaign}{number}' for campaign, count in [('TSK', 20), ('TPR', 14)]
                                    for number in range(1, count + 1)]
environment = dict(os.environ, KAM_DATA_DIR=str(data))
results = []
for name in missions:
    match = re.fullmatch(r'(TSK|TPR)([1-9][0-9]?)', name)
    if not match:
        parser.error(f'Invalid mission: {name}')
    campaign, number = match.groups()
    if int(number) > (20 if campaign == 'TSK' else 14):
        parser.error(f'Invalid mission: {name}')
    started = time.monotonic()
    command = [str(root / 'assets.local/build/macos/bin/KM_MacCampaignProbe'),
               campaign, number, str(output), str(args.ticks)]
    if args.seed is not None:
        command.append(str(args.seed))
    with (output / f'{name}.log').open('w') as log:
        try:
            run = subprocess.run(command,
                                 env=environment, stdout=log, stderr=subprocess.STDOUT, timeout=180)
            code = run.returncode
        except subprocess.TimeoutExpired:
            code = 'timeout'
    log_text = (output / f'{name}.log').read_text(errors='replace')
    passed = code == 0 and f'PASS: {campaign} mission {number}:' in log_text
    results.append({'mission': name, 'passed': passed, 'returncode': code,
                    'ticks': args.ticks, 'seed': args.seed,
                    'seconds': round(time.monotonic() - started, 2)})
    (output / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
    print(f'{"PASS" if passed else "FAIL"}: {name} ({results[-1]["seconds"]}s)', flush=True)
    if not passed:
        print(log_text[-6000:], flush=True)
        raise SystemExit(1)
print(f'PASS: {len(results)} retail missions', flush=True)

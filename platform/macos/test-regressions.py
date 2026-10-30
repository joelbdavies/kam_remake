#!/usr/bin/env python3
"""Test native save/resume fidelity, save collections and Cocoa input handling."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time

root = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--data-dir', type=Path, required=True)
parser.add_argument('--output', type=Path, default=root / 'assets.local/regression-tests')
parser.add_argument('--missions', nargs='+', default=['TSK2', 'TPR3'])
parser.add_argument('--cut-tick', type=int, default=1500)
parser.add_argument('--end-tick', type=int, default=6000)
parser.add_argument('--only', choices=['all', 'trajectory', 'collections', 'keyboard', 'mouse', 'cursor', 'upstream'], default='all')
args = parser.parse_args()
data = args.data_dir.resolve()
if root / 'assets.local' not in data.parents or not (data / 'Campaigns').is_dir():
    parser.error('Use disposable staged data under this checkout\'s assets.local directory')
if not 100 < args.cut_tick < args.end_tick or args.end_tick % 100:
    parser.error('Require 100 < cut-tick < end-tick and end-tick divisible by 100')
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)
environment = dict(os.environ, KAM_DATA_DIR=str(data))
results = []
for suite, executable, expected_checks in [('upstream', 'KM_MacUpstreamProbe', 6),
                                          ('collections', 'KM_MacCollectionProbe', 13),
                                          ('keyboard', 'KM_MacKeyboardProbe', 1),
                                          ('cocoa-events', 'KM_MacCocoaEventProbe', 2),
                                          ('mouse', 'KM_MacMouseProbe', 4),
                                          ('cursor', 'KM_MacCursorProbe', 28)]:
    selection = 'keyboard' if suite == 'cocoa-events' else suite
    if args.only not in ('all', selection):
        continue
    log_path = output / f'{suite}.log'
    if log_path.exists():
        parser.error(f'Use a fresh output directory: {log_path.parent}')
    started = time.monotonic()
    with log_path.open('w') as log:
        try:
            command = [str(root / 'assets.local/build/macos/bin' / executable)]
            if suite == 'cursor':
                command.append(str(output / 'cursor-images'))
            run = subprocess.run(command,
                                 env=environment, stdout=log, stderr=subprocess.STDOUT, timeout=240)
            code = run.returncode
        except subprocess.TimeoutExpired:
            code = 'timeout'
    log_text = log_path.read_text(errors='replace')
    checks = len(re.findall(r'^PASS:', log_text, re.MULTILINE))
    passed = code == 0 and checks == expected_checks
    results.append({'suite': suite, 'passed': passed, 'checks': checks, 'returncode': code,
                    'seconds': round(time.monotonic() - started, 2)})
    (output / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
    print(f"{'PASS' if passed else 'FAIL'}: {suite}, {checks}/{expected_checks} checks", flush=True)
    if not passed:
        print(log_text[-5000:])
        raise SystemExit(1)

for mission in (args.missions if args.only in ('all', 'trajectory') else []):
    match = re.fullmatch(r'(TSK|TPR)([1-9][0-9]?)', mission)
    if not match:
        parser.error(f'Invalid mission: {mission}')
    campaign, number = match.groups()
    if int(number) > (20 if campaign == 'TSK' else 14):
        parser.error(f'Invalid mission: {mission}')
    result = {'suite': 'trajectory', 'mission': mission, 'phases': [], 'differences': []}
    results.append(result)
    for phase in ('start', 'save', 'resume'):
        directory = output / mission / phase
        directory.mkdir(parents=True, exist_ok=True)
        # Reject stale evidence instead of mixing it with a previous execution.
        if list(directory.glob('*.bin')):
            parser.error(f'Use a fresh output directory: {directory}')
        command = [str(root / 'assets.local/build/macos/bin/KM_MacTrajectoryProbe'),
                   phase, campaign, number, str(args.cut_tick), str(args.end_tick), str(directory)]
        started = time.monotonic()
        with (directory / 'run.log').open('w') as log:
            try:
                run = subprocess.run(command, env=environment, stdout=log,
                                     stderr=subprocess.STDOUT, timeout=240)
                code = run.returncode
            except subprocess.TimeoutExpired:
                code = 'timeout'
        result['phases'].append({'phase': phase, 'returncode': code,
                                 'seconds': round(time.monotonic() - started, 2)})
        if code:
            print((directory / 'run.log').read_text(errors='replace')[-5000:])
            (output / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
            raise SystemExit(1)
    resumed = output / mission / 'resume'
    expected = output / mission / 'start'
    files = sorted(resumed.glob('*.bin'))
    expected_ticks = {tick for tick in range(args.cut_tick, args.end_tick + 1)
                      if tick <= args.cut_tick + 10 or tick % 100 == 0}
    components = ['rng-ids', 'terrain', 'hands', 'ai-fields', 'pathfinding',
                  'projectiles', 'script', 'script-sounds', 'custom-resources']
    expected_names = {f'{tick}-{part}.bin' for tick in expected_ticks for part in components}
    if {path.name for path in files} != expected_names:
        raise RuntimeError('Missing or unexpected resumed simulation snapshots')
    if {path.name for path in expected.glob('*.bin')} != expected_names:
        raise RuntimeError('Missing or unexpected continuous simulation snapshots')
    def orders(directory):
        return [line for line in (directory / 'run.log').read_text().splitlines()
                if (match := re.match(r'ORDER tick=(\d+) ', line))
                and int(match.group(1)) >= args.cut_tick]
    if not orders(resumed) or orders(resumed) != orders(expected):
        raise RuntimeError('Resumed run did not receive the same nonempty command sequence')
    for path in files:
        baseline = (expected / path.name).read_bytes()
        actual = path.read_bytes()
        if baseline != actual:
            offset = next((i for i, (a, b) in enumerate(zip(baseline, actual)) if a != b),
                          min(len(baseline), len(actual)))
            result['differences'].append({'file': path.name, 'first_offset': offset,
                                          'baseline_size': len(baseline), 'resumed_size': len(actual),
                                          'baseline_sha256': hashlib.sha256(baseline).hexdigest(),
                                          'resumed_sha256': hashlib.sha256(actual).hexdigest()})
    result['snapshots_compared'] = len(files)
    result['orders_after_reload'] = len(orders(resumed))
    result['passed'] = not result['differences']
    (output / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
    print(f"{'PASS' if result['passed'] else 'FAIL'}: {mission}, {len(files)} component snapshots, "
          f"{len(result['differences'])} differences", flush=True)
    if result['differences']:
        print(json.dumps(result['differences'][:12], indent=2))
        raise SystemExit(1)

#!/usr/bin/env python3
"""Check copies of original native MVP saves without changing player files."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time

root = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--data-dir', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--saves', nargs='+', required=True, help='Original r16406 save names in the disposable data directory')
parser.add_argument('--replay', help='Also replay this original save and its resaved copy from their base state')
parser.add_argument('--replay-tick', type=int, help='Original save tick; the resaved copy is checked 100 ticks later')
args = parser.parse_args()
data = args.data_dir.resolve()
if root / 'assets.local' not in data.parents or not (data / 'Campaigns').is_dir():
    parser.error('Use disposable staged data under this checkout\'s assets.local directory')
if any(Path(name).name != name or name in ('', '.', '..') for name in args.saves):
    parser.error('Save names must not include a path')
if args.replay and (args.replay not in args.saves or not args.replay_tick or args.replay_tick < 1):
    parser.error('--replay must name one of --saves and requires a positive --replay-tick')
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=False)
environment = dict(os.environ, KAM_DATA_DIR=str(data))
executable = root / 'assets.local/build/macos/bin/KM_MacCompatibilityProbe'
cases = [('save', name, []) for name in args.saves]
if args.replay:
    cases += [('replay', args.replay, [str(args.replay_tick)]),
              ('replay', 'mac-compat-' + args.replay, [str(args.replay_tick + 100)])]
results = []
for index, (mode, name, extra) in enumerate(cases):
    log_path = output / f'{index:02d}-{mode}.log'
    started = time.monotonic()
    with log_path.open('w') as log:
        try:
            run = subprocess.run([str(executable), mode, name, *extra], env=environment,
                                 stdout=log, stderr=subprocess.STDOUT, timeout=300)
            code = run.returncode
        except subprocess.TimeoutExpired:
            code = 'timeout'
    log_text = log_path.read_text(errors='replace')
    passed = code == 0 and f'PASS: legacy {mode} {name} ' in log_text
    results.append({'mode': mode, 'save': name, 'passed': passed, 'returncode': code,
                    'seconds': round(time.monotonic() - started, 2), 'log': log_path.name})
    (output / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
    print(f"{'PASS' if passed else 'FAIL'}: {mode} {name}", flush=True)
    if not passed:
        print(log_text[-6000:])
        raise SystemExit(1)

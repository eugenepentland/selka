#!/usr/bin/env python3
"""Run all cases in bounded shared timing leases; this owns admission."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--resume', action='store_true', help='Reuse completed chunks; preserve and stop at interrupted chunks for explicit recovery.')
    parser.add_argument('--group', choices=('eda', 'tree', 'vm', 'all'), default='all')
    args = parser.parse_args()
    result = HERE / 'runtime'
    result.mkdir(exist_ok=True)
    specs = sorted((HERE / 'specs').glob('*.json'))
    assert len(specs) == 60 and os.environ.get('MYLANG_SLOT_DIR')
    env = dict(os.environ)
    for name in ('MYLANG_COUNTERS', 'MYL_CORE_LEAKCHECK'):
        env.pop(name, None)
    groups = ('eda', 'tree', 'vm') if args.group == 'all' else (args.group,)
    for group in groups:
        selected = [p for p in specs if p.stem.startswith(group + '-')]
        assert len(selected) == (34 if group == 'eda' else 13)
        for source in selected:
            base = json.loads(source.read_text())
            chunks = [(0, 9, 2, 3)] if group == 'eda' else [(0, 3, 2, 0), (3, 3, 0, 0), (6, 3, 0, 0), (9, 0, 0, 3)]
            previous = None
            for start, rounds, warmups, rss in chunks:
                name = source.stem + f'.r{start}-{start+rounds}.w{warmups}.rss{rss}'
                receipt = result / (name + '.json')
                if receipt.exists():
                    assert args.resume
                    existing = json.loads(receipt.read_text())
                    assert existing['spec']['cell'] == base['cell'] and existing['spec']['arms'] == base['arms']
                    for path, identity in existing['identities'].items():
                        assert hashlib.sha256(Path(path).read_bytes()).hexdigest() == identity
                    previous = receipt
                    continue
                spec = dict(base)
                if previous:
                    spec['prior_receipt'] = str(previous.resolve())
                generated = result / (name + '.spec.json')
                if generated.exists():
                    raise RuntimeError(f'Interrupted chunk preserved at {generated}. Inspect its progress journal before recovery; '
                                       'automatic retry could conceal a recorded cutoff or selectively replace samples.')
                generated.write_text(json.dumps(spec, indent=2) + '\n')
                command = [str(ROOT / 'scripts/build-slot.sh'), 'timing', sys.executable, '-B', str(HERE / 'measure_cell.py'),
                           str(generated), str(receipt), '--cpu', '8', '--round-start', str(start), '--rounds', str(rounds),
                           '--warmups', str(warmups), '--rss-rounds', str(rss), '--guest-timeout', '120']
                print('measuring', base['cell'], name, flush=True)
                with (result / (name + '.log')).open('w') as stream:
                    subprocess.run(command, cwd=ROOT, env=env, stdout=stream, stderr=subprocess.STDOUT, check=True)
                previous = receipt
                d = json.loads(receipt.read_text())
                failed = {arm: status['status'] for arm, status in d['arm_status'].items() if status['status'] != 'ok'}
                print('completed', base['cell'], name, 'failures', failed, flush=True)
    print('FINISHED', args.group, flush=True)


if __name__ == '__main__':
    main()

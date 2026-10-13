#!/usr/bin/env python3
"""Run the frozen measurement chunks in bounded admission windows.

Guest commands, round order, warmups, deadlines and receipts match pipeline.py.
An admitted window finishes its current chunk before yielding after 55 seconds;
the existing per-guest deadline still bounds that final chunk. No nested admission.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
CHUNKS = [(0, 0, 2, 0)] + [(i, 1, 0, 0) for i in range(9)] + [(9 + i, 0, 0, 1) for i in range(3)]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + '\n')


def validate_pins(destination, freeze):
    pin_file = destination / 'pins.json'
    assert json.loads(freeze.read_text())['pins_sha256'] == sha(pin_file)
    for name, digest in json.loads(pin_file.read_text()).items():
        assert sha(Path(name)) == digest, ('identity changed', name)


def pending(destination):
    """Require a complete receipt prefix, including the exact prior-receipt chain."""
    result = []
    pins = json.loads((destination / 'pins.json').read_text())
    for path in sorted((destination / 'specs').glob('*.json')):
        base = json.loads(path.read_text())
        prior = None
        missing = False
        for index, settings in enumerate(CHUNKS):
            stem = f'{path.stem}.chunk{index:02d}'
            output = destination / 'runtime' / (stem + '.json')
            generated = destination / 'runtime' / (stem + '.spec.json')
            spec = dict(base)
            if prior is not None:
                spec['prior_receipt'] = str(prior)
            if output.exists():
                assert not missing, ('receipt gap', output)
                receipt = json.loads(output.read_text())
                assert receipt['spec'] == spec, ('changed execution spec', output)
                assert receipt['spec_sha256'] == sha(generated)
                assert json.loads(generated.read_text()) == spec
                start, rounds, warmups, rss = settings
                assert (receipt['round_start'], receipt['rounds'], receipt['warmups']) == (start, rounds, warmups)
                assert receipt['measurement_harness_sha256'] == sha(HERE / 'measure.py')
                assert all(pins.get(name) == digest for name, digest in receipt['identities'].items()), ('changed receipt identities', output)
                if prior is not None:
                    assert receipt['prior_receipt'] == {'path': str(prior), 'sha256': sha(prior)}
            else:
                missing = True
                result.append((stem, generated, output, spec, settings))
            prior = output
    return result


def window(args, destination, evidence):
    validate_pins(destination, args.freeze)
    started = time.monotonic()
    jobs = pending(destination)
    receipt = {'harness_sha256': sha(Path(__file__).resolve()), 'window_seconds': args.window_seconds,
               'policy': 'Yield after current chunk when elapsed window reaches limit; unchanged guest deadlines bound each chunk.',
               'measurements': [], 'complete': not jobs}
    environment = dict(os.environ)
    environment.pop('MYLANG_COUNTERS', None)
    environment.pop('MYL_CORE_LEAKCHECK', None)
    for stem, generated, output, spec, settings in jobs:
        # An interrupted generated spec is admissible only with an explicit
        # cancellation record proving the old queue never ran the measurer.
        if generated.exists():
            recovery = destination / 'schedule-recovery.json'
            assert recovery.exists(), ('unreviewed interrupted chunk', generated)
            record = json.loads(recovery.read_text())
            assert record['spec'] == str(generated) and record['spec_sha256'] == sha(generated)
            assert record['status'] == 'cancelled-before-measurement'
            assert json.loads(generated.read_text()) == spec
            assert not output.with_suffix(output.suffix + '.progress.jsonl').exists()
        else:
            save(generated, spec)
        start, rounds, warmups, rss = settings
        command = [sys.executable, '-B', str(HERE / 'measure.py'), str(generated), str(output),
                   '--cpu', str(args.cpu), '--round-start', str(start), '--rounds', str(rounds),
                   '--warmups', str(warmups), '--rss-rounds', str(rss), '--calibration-rounds', '5',
                   '--calibration-warmups', '2', '--guest-timeout', '120']
        chunk_started = time.monotonic()
        with (destination / 'runtime' / (stem + '.windowed.log')).open('x') as log:
            process = subprocess.run(command, cwd=args.root, env=environment, stdout=log, stderr=subprocess.STDOUT)
        receipt['measurements'].append({'stem': stem, 'command': command, 'returncode': process.returncode,
                                        'elapsed_seconds': time.monotonic() - chunk_started})
        receipt['elapsed_seconds'] = time.monotonic() - started
        save(evidence / 'progress.json', receipt)
        assert process.returncode == 0, ('measurement failed', stem)
        if time.monotonic() - started >= args.window_seconds:
            break
    validate_pins(destination, args.freeze)
    receipt['complete'] = not pending(destination)
    receipt['elapsed_seconds'] = time.monotonic() - started
    save(evidence / 'result.json', receipt)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--attempt', required=True)
    parser.add_argument('--freeze', type=Path, required=True)
    parser.add_argument('--cpu', type=int, default=8)
    parser.add_argument('--window-seconds', type=float, default=55)
    parser.add_argument('--admitted', type=int)
    args = parser.parse_args()
    args.root = args.root.resolve()
    args.freeze = args.freeze.resolve()
    assert 0 < args.window_seconds <= 55
    assert args.cpu in os.sched_getaffinity(0)
    destination = HERE / 'attempts' / args.attempt
    validate_pins(destination, args.freeze)
    if args.admitted is not None:
        orchestrator = json.loads((destination / 'windows/orchestrator.json').read_text())
        assert orchestrator['harness_sha256'] == sha(Path(__file__).resolve())
        window(args, destination, destination / 'windows' / f'{args.admitted:03d}')
        return
    assert os.environ.get('MYLANG_SLOT_DIR'), 'source shared development environment'
    orchestrator = destination / 'windows' / 'orchestrator.json'
    assert not orchestrator.exists(), 'inspect earlier orchestration before restarting'
    save(orchestrator, {'harness_sha256': sha(Path(__file__).resolve()), 'existing_chunks': len(list((destination / 'runtime').glob('*.chunk[0-9][0-9].json'))),
                        'pins_sha256': sha(destination / 'pins.json'), 'window_seconds': args.window_seconds})
    index = 0
    while pending(destination):
        evidence = destination / 'windows' / f'{index:03d}'
        evidence.mkdir(parents=True, exist_ok=False)
        command = [str(args.root / 'scripts/build-slot.sh'), 'timing', sys.executable, '-B', str(Path(__file__).resolve()),
                   '--root', str(args.root), '--attempt', args.attempt, '--freeze', str(args.freeze), '--cpu', str(args.cpu),
                   '--window-seconds', str(args.window_seconds), '--admitted', str(index)]
        save(evidence / 'command.json', command)
        with (evidence / 'admission.log').open('x') as log:
            result = subprocess.run(command, cwd=args.root, stdout=log, stderr=subprocess.STDOUT)
        assert result.returncode == 0, ('window failed', index)
        assert (evidence / 'result.json').exists()
        index += 1
    validate_pins(destination, args.freeze)


if __name__ == '__main__':
    main()

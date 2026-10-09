#!/usr/bin/env python3
"""Run every parity arm and both Lox benchmark engines once, without timing.

Uses the unchanged tax registry/inputs/expected bytes but no timing CPU or lock.
All guest compiles use the shared build-slot wrapper through ce.run.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import subprocess

import ce
import tax_corpora


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--tag', required=True)
    args = parser.parse_args()
    directory = ce.ROOT / '.mylang-cache/concurrency-p1/correctness' / args.tag
    directory.mkdir(parents=True, exist_ok=False)
    log_dir = ce.AREA / 'r3/logs' / (args.tag + '-parity-correctness')
    log_dir.mkdir(parents=True, exist_ok=False)
    parity = tax_corpora.cells('parity')
    assert len(parity) == 45

    def build(cell):
        command = [args.compiler, 'build', cell['source'], '--release', '-o', directory / cell['program'],
                   '--cache-dir', directory / 'cache']
        status, stdout, stderr = ce.run(command, cwd=cell['cwd'], slot=True,
                                       extra_env={'MYLANG_SLOT_SETTLE': '0'})
        (log_dir / (cell['program'] + '.log')).write_text(
            json.dumps(list(map(str, command))) + '\n' + stdout.decode() + stderr.decode() + f'\nexit={status}\n')
        assert status == 0, (cell['program'], status)

    with ThreadPoolExecutor(max_workers=2) as pool:
        list(pool.map(build, parity.values()))
    result = {'source': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ce.ROOT, text=True).strip(),
              'compiler_sha256': ce.digest(args.compiler), 'mode': 'correctness only: one execution per cell',
              'cells': {}, 'pass': False}
    output = ce.AREA / 'r3/results' / (args.tag + '-corpus-correctness.json')
    lox = tax_corpora.cells('lox')
    assert len(lox) == 26
    for group, cells in [('parity', parity), ('lox', lox)]:
        for name, cell in cells.items():
            binary = (directory / cell['program'] if group == 'parity' else
                      ce.CACHE / 'bin' / args.tag / 'lox-plain')
            command = [binary, *cell['args']]
            status, stdout, stderr = ce.run(command, cwd=cell['cwd'], timeout=900)
            record = {'command': list(map(str, command)), 'status': status,
                      'stdout': stdout.decode(errors='replace'), 'stderr': stderr.decode(errors='replace'),
                      'expected_sha256': hashlib.sha256(cell['expected']).hexdigest(),
                      'stdout_sha256': hashlib.sha256(stdout).hexdigest(), 'binary_sha256': ce.digest(binary),
                      'matches_expected': stdout == cell['expected']}
            result['cells'][group + '/' + name] = record
            output.write_text(json.dumps(result, indent=2) + '\n')
            assert status == 0 and stdout == cell['expected'] and not stderr, (name, record)
        print(group, len(cells), 'expected outputs pass', flush=True)
    result['pass'] = True
    output.write_text(json.dumps(result, indent=2) + '\n')


if __name__ == '__main__':
    main()

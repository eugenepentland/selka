#!/usr/bin/env python3
"""Native static-query correctness matrix; contains no performance measurements."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

MAIN = '''import helper

func idle(n: int) -> int:
    return n % 5

func main(args: str[], out: Stream) -> int:
    out.print(idle(len(args) + 9), helper.shared(len(args) + 7))
    return 0
'''
HELPER = '''public func shared(n: int) -> int:
    return n % 3
'''


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, default=Path('zig-out/bin/mylang'))
    parser.add_argument('--output', type=Path, default=Path('experiments/cache-wave5-20261010/cost-native'))
    parser.add_argument('--workspace', type=Path, default=Path('.mylang-cache/cache-wave5/cost-qualification'))
    options = parser.parse_args()
    compiler = options.compiler.resolve()
    output = options.output.resolve()
    workspace = options.workspace.resolve()
    if workspace.exists() or output.exists():
        raise SystemExit('qualification requires fresh workspace and output paths')
    workspace.mkdir(parents=True)
    output.mkdir(parents=True)
    source = workspace / 'main.my'
    helper = workspace / 'helper.my'
    source.write_text(MAIN)
    helper.write_text(HELPER)
    cache = workspace / 'cache'
    env = dict(os.environ)
    records = []

    def run(label, flags=()):
        command = [str(compiler), 'cost', str(source), '--json', '--cache-dir', str(cache), '--cache-report', *map(str, flags)]
        completed = subprocess.run(command, capture_output=True, env=env, timeout=120)
        (output / f'{label}.stdout.json').write_bytes(completed.stdout)
        (output / f'{label}.stderr.txt').write_bytes(completed.stderr)
        if completed.returncode:
            raise AssertionError((label, completed.returncode, completed.stderr.decode(errors='replace')))
        report = json.loads(completed.stdout)
        assert report['version'] == 'cost-v1', report
        documents = [json.loads(line) for line in completed.stderr.splitlines() if line.startswith(b'{')]
        work = next(value for value in documents if value.get('version') == 'cost-query-work-v1')
        record = {'label': label, 'command': command, 'exit': completed.returncode,
                  'report_sha256': sha(completed.stdout), 'stderr_sha256': sha(completed.stderr),
                  'inputs': {path.name: sha(path.read_bytes()) for path in (source, helper)},
                  'work': work, 'functions': len(report['functions'])}
        records.append(record)
        return report, record

    def parity(left, right):
        assert left[0] == right[0], (left[1]['label'], right[1]['label'])

    cold = run('cold')
    assert cold[1]['work']['cost']['computed'] > 0
    assert cold[1]['work']['llvm']['processes'] == 1
    warm = run('warm')
    parity(cold, warm)
    assert warm[1]['work']['cost']['computed'] == 0
    assert warm[1]['work']['cost']['reused'] == warm[1]['functions']
    assert warm[1]['work']['lowering']['reused'] > 0
    assert warm[1]['work']['llvm'] == {'processes': 0, 'reused': 1}
    source.write_text(MAIN.replace('n % 5', 'n % 6'))
    private = run('private-edit')
    assert private[1]['work']['cost']['computed'] > 0
    assert private[1]['work']['cost']['reused'] > 0
    parity(private, run('private-fresh', ['--no-cache']))
    helper.write_text(HELPER.replace('n % 3', 'n % 4'))
    shared = run('shared-helper-edit')
    assert shared[1]['work']['cost']['computed'] >= 2
    assert shared[1]['work']['cost']['reused'] > 0
    parity(shared, run('shared-helper-fresh', ['--no-cache']))
    verified = run('verified', ['--verify-cache'])
    parity(shared, verified)
    assert verified[1]['work']['cost']['verified'] == verified[1]['functions']
    assert verified[1]['work']['llvm']['processes'] == 1
    packs = sorted((cache / 'stages-packed-v1').glob('*.pack'))
    journals = sorted((cache / 'stages-packed-v1').glob('*.journal'))
    damaged = packs + journals
    assert damaged, 'no persisted compiler-query records'
    for artifact in damaged:
        artifact.write_bytes(b'corrupt qualification artifact')
    repaired = run('corrupt-fallback')
    parity(shared, repaired)
    assert repaired[1]['work']['cost']['computed'] > 0
    parity(repaired, run('corrupt-fresh', ['--no-cache']))
    repair_warm = run('corrupt-repair-warm')
    parity(repaired, repair_warm)
    assert repair_warm[1]['work']['cost']['computed'] == 0
    assert repair_warm[1]['work']['llvm']['processes'] == 0
    shutil.rmtree(cache / 'stages-packed-v1')
    missing = run('missing-fallback')
    parity(shared, missing)
    assert missing[1]['work']['cost']['computed'] > 0
    assert missing[1]['work']['llvm']['processes'] == 1

    remarks = workspace / 'remarks.yaml'
    counters = workspace / 'counters.json'
    remarks.write_text('')
    counters.write_text(json.dumps({'version': 'mylang-counters-v1', 'functions': [], 'sites': []}))
    flags = ['--llvm-remarks', remarks, '--counters', counters]
    before = run('external-before', flags)
    name = before[0]['functions'][0]['name']
    remarks.write_text(f"--- !Passed\nPass: loop-vectorize\nName: Vectorized\nFunction: '{name}'\n...\n")
    counters.write_text(json.dumps({'version': 'mylang-counters-v1', 'functions': [{'name': name, 'calls': 17}], 'sites': []}))
    external = run('external-edit', flags)
    assert external[0]['functions'][0]['counts']['llvm_vectorized_loops'] == 1
    assert external[0]['counters'][0]['run']['calls'] == 17
    assert external[1]['work']['cost']['reused'] > 0
    assert external[1]['work']['llvm']['processes'] == 0
    parity(external, run('external-fresh', [*flags, '--no-cache']))
    for mode in ('--debug', '--no-facts', '--verify-facts'):
        label = mode.removeprefix('--')
        first = run(label, [mode])
        again = run(f'{label}-warm', [mode])
        parity(first, again)
        assert again[1]['work']['cost']['computed'] == 0
        assert again[1]['work']['llvm']['processes'] == 0
        parity(first, run(f'{label}-fresh', [mode, '--no-cache']))
    summary = {'version': 'wave5-cost-qualification-v1', 'completed_utc': datetime.now(timezone.utc).isoformat(),
               'compiler': str(compiler), 'compiler_sha256': sha(compiler.read_bytes()),
               'invocations': len(records), 'success': True, 'damaged_records': len(damaged),
               'scope': 'native static compiler-query correctness; no performance claims', 'records': records}
    (output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    (output / 'initial-main.my').write_text(MAIN)
    (output / 'initial-helper.my').write_text(HELPER)
    print(json.dumps({'success': True, 'invocations': len(records), 'output': str(output)}))


if __name__ == '__main__':
    main()

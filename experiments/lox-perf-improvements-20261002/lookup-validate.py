#!/usr/bin/env python3
"""Check all Lox smoke scripts and historical diagnostics with both collectors stressed."""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import subprocess


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    work = args.work.resolve()
    repo = Path(__file__).resolve().parents[2]
    manifest = json.loads((work / 'binaries.json').read_text())
    binaries = manifest['binaries']
    hashes = {k: sha(v) for k, v in binaries.items()}
    env = {k: v for k, v in os.environ.items()
           if not k.startswith('MYLANG_') and k != 'LD_PRELOAD'}
    inputs = work / 'validation-inputs'
    inputs.mkdir(exist_ok=True)
    doc = {'manifest': manifest, 'binary_sha256': hashes, 'samples': []}

    def save():
        pending = args.out.with_suffix('.pending')
        pending.write_text(json.dumps(doc, indent=2) + '\n')
        pending.replace(args.out)

    def check(name, source, engine, expected, tier):
        path = inputs / f'{name}.{engine}.{tier}.lox'
        path.write_text(source)
        for runtime in ['rc', 'gc']:
            for backend in ['llvm', 'qbe']:
                for stress in [False, True]:
                    observed = []
                    for arm in ['control', 'candidate']:
                        key = f'{arm}-{backend}' if runtime == 'rc' else f'{arm}-gc-{backend}'
                        command = [binaries[key], f'--engine={engine}']
                        launch_env = dict(env)
                        if runtime == 'gc':
                            launch_env['MYLANG_OPTIONS'] = '--gc-stress'
                        if stress:
                            command.append('--gc-stress')
                        command.append(str(path))
                        result = subprocess.run(command, stdout=subprocess.PIPE,
                                                stderr=subprocess.PIPE, env=launch_env, timeout=120)
                        actual = {'status': result.returncode,
                                  'stdout': result.stdout.decode(),
                                  'stderr': result.stderr.decode()}
                        assert actual == expected, (name, engine, key, stress, actual, expected)
                        observed.append(actual)
                        doc['samples'].append({'name': name, 'tier': tier, 'engine': engine,
                                               'arm': key, 'native_gc_stress': runtime == 'gc',
                                               'lox_gc_stress': stress, 'command': command,
                                               'script_sha256': sha(path),
                                               'expected': expected, 'actual': actual})
                        save()
                    assert observed[0] == observed[1]
        print(f'passed {tier} {engine}/{name}', flush=True)

    bench = work / 'reference/benchmarks/lox/bench'
    sizes = json.loads((bench / 'sizes.json').read_text())
    for engine in ['vm', 'tree']:
        for path in sorted((bench / 'scripts').glob('*.lox')):
            name = path.stem
            first, rest = path.read_text().split('\n', 1)
            assert first.startswith('var N = ')
            source = f"var N = {sizes[name]['smoke']};\n{rest}"
            expected = {'status': 0,
                        'stdout': (bench / 'expected' / f'{name}.smoke.out').read_text(),
                        'stderr': ''}
            check(name, source, engine, expected, 'smoke')

    # The previous VM and tree lanes recorded complete source and stderr for
    # the same 23 runtime-error cases. Retain their exact engine-specific trace.
    files = {'vm': 'd9-lox-class-method-runs.json.gz',
             'tree': 'd9-lox-env-reads-runs.json.gz'}
    for engine, filename in files.items():
        recorded = json.load(gzip.open(repo / 'docs/audits/evidence' / filename))
        seen = set()
        for row in recorded['traces']:
            if row['name'] in seen:
                continue
            seen.add(row['name'])
            check(row['name'], row['source'], engine, row['expected'], 'errors')
        assert len(seen) == 23, (engine, seen)

    for key, binary in binaries.items():
        assert sha(binary) == hashes[key], key
    doc['verified_after'] = True
    save()
    print(f"{len(doc['samples'])} output/diagnostic observations passed", flush=True)


if __name__ == '__main__':
    main()

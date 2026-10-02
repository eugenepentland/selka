#!/usr/bin/env python3
"""Check all Lox smoke scripts and historical diagnostics with both collectors stressed."""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import fcntl
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
    parser.add_argument('--jobs', type=int, default=1)
    parser.add_argument('--resume', action='store_true')
    parser.add_argument('--native-tree-cases', default='',
                        help='Restrict native-GC-stressed tree smoke cases; empty runs all')
    args = parser.parse_args()
    work = args.work.resolve()
    args.out.parent.mkdir(parents=True, exist_ok=True)
    output_lock = args.out.with_suffix('.lock').open('w')
    fcntl.flock(output_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    repo = Path(__file__).resolve().parents[2]
    manifest = json.loads((work / 'binaries.json').read_text())
    binaries = manifest['binaries']
    hashes = {k: sha(v) for k, v in binaries.items()}
    env = {k: v for k, v in os.environ.items()
           if not k.startswith('MYLANG_') and k != 'LD_PRELOAD'}
    inputs = work / 'validation-inputs'
    inputs.mkdir(exist_ok=True)
    doc = {'manifest': manifest, 'binary_sha256': hashes, 'samples': []}
    native_tree_cases = set(filter(None, args.native_tree_cases.split(',')))
    if args.resume:
        doc = json.loads(args.out.read_text())
        assert doc['binary_sha256'] == hashes, 'resume requires the same binaries'
        if doc['manifest'] != manifest:
            doc['manifest_metadata_at_resume'] = manifest
        doc.setdefault('resume_history', []).append({
            'input_receipt_sha256': sha(args.out), 'jobs': args.jobs,
            'native_tree_cases': sorted(native_tree_cases),
            'manifest_patch_sha256': manifest.get('patch_sha256')})
    done = {(s['name'], s['tier'], s['engine'], s['arm'], s['lox_gc_stress']): s
            for s in doc['samples']}
    skipped = {(s['name'], s['tier'], s['engine'], s['arm'], s['lox_gc_stress']): s
               for s in doc.get('skipped_observations', [])}
    assert len(done) == len(doc['samples']), 'duplicate observation in receipt'

    def save():
        pending = args.out.with_suffix('.pending')
        pending.write_text(json.dumps(doc, indent=2) + '\n')
        pending.replace(args.out)

    def check(name, source, engine, expected, tier):
        path = inputs / f'{name}.{engine}.{tier}.lox'
        path.write_text(source)
        def observe(runtime, backend, arm, stress):
            key = f'{arm}-{backend}' if runtime == 'rc' else f'{arm}-gc-{backend}'
            identity = (name, tier, engine, key, stress)
            if identity in done:
                recorded = done[identity]
                assert recorded['script_sha256'] == sha(path), identity
                assert recorded['actual'] == expected, identity
                return None
            if runtime == 'gc' and engine == 'tree' and tier == 'smoke' and \
                    native_tree_cases and name not in native_tree_cases:
                if identity in skipped:
                    return None
                return {'name': name, 'tier': tier, 'engine': engine, 'arm': key,
                        'lox_gc_stress': stress, 'script_sha256': sha(path),
                        'skipped_reason': 'bounded native-stress corpus; representative cases and joined qualification cover this path'}
            command = [binaries[key], f'--engine={engine}']
            launch_env = dict(env)
            if runtime == 'gc':
                launch_env['MYLANG_OPTIONS'] = '--gc-stress'
            if stress:
                command.append('--gc-stress')
            command.append(str(path))
            result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                    env=launch_env, timeout=120)
            actual = {'status': result.returncode, 'stdout': result.stdout.decode(),
                      'stderr': result.stderr.decode()}
            assert actual == expected, (name, engine, key, stress, actual, expected)
            return {'name': name, 'tier': tier, 'engine': engine, 'arm': key,
                    'native_gc_stress': runtime == 'gc', 'lox_gc_stress': stress,
                    'MYLANG_OPTIONS': launch_env.get('MYLANG_OPTIONS'), 'command': command,
                    'script_sha256': sha(path), 'expected': expected, 'actual': actual}

        with ThreadPoolExecutor(max_workers=args.jobs) as pool:
            pending = [pool.submit(observe, runtime, backend, arm, stress)
                       for runtime in ['rc', 'gc'] for backend in ['llvm', 'qbe']
                       for stress in [False, True] for arm in ['control', 'candidate']]
            for future in as_completed(pending):
                sample = future.result()
                if sample is not None:
                    if 'skipped_reason' in sample:
                        identity = (name, tier, engine, sample['arm'], sample['lox_gc_stress'])
                        skipped[identity] = sample
                        doc.setdefault('skipped_observations', []).append(sample)
                        save()
                        continue
                    identity = (name, tier, engine, sample['arm'], sample['lox_gc_stress'])
                    assert identity not in done
                    done[identity] = sample
                    doc['samples'].append(sample)
                    save()
        print(f'checked selected observations {tier} {engine}/{name}', flush=True)

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
    still_unrun = {key: sample for key, sample in skipped.items() if key not in done}
    doc['unique_skipped_observations'] = list(still_unrun.values())
    save()
    print(f"{len(doc['samples'])} output/diagnostic observations passed; "
          f"{len(still_unrun)} explicitly unrun", flush=True)


if __name__ == '__main__':
    main()

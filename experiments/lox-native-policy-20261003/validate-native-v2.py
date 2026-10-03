#!/usr/bin/env python3
"""Compare bounded tree/VM output, exact diagnostics, and Lox collector work."""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import gzip
import hashlib
import json
import os
from pathlib import Path
import subprocess


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--work', type=Path, required=True)
    p.add_argument('--bench', type=Path, required=True)
    p.add_argument('--manifest', type=Path, required=True,
                   help='JSON mapping binary names to paths, with control-llvm/control-qbe')
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--resume', type=Path,
                   help='Preserve the prior receipt and resume its identical binaries')
    p.add_argument('--jobs', type=int, default=2)
    p.add_argument('--cases', type=Path,
                   help='Additional regression JSON with name/source/stdout entries')
    p.add_argument('--native-cases', default='',
                   help='Native GC stress smoke cases; focused regressions and diagnostics always run')
    a = p.parse_args()
    repo, work = Path(__file__).resolve().parents[2], a.work.resolve()
    bins = json.loads(a.manifest.read_text())['binaries']
    hashes = {name: sha(path) for name, path in bins.items()}
    inputs = work / 'validation-inputs'
    inputs.mkdir(exist_ok=True)
    env = {k: v for k, v in os.environ.items()
           if not k.startswith('MYLANG_') and k != 'LD_PRELOAD'}
    selected = set(a.native_cases.split(','))
    cases = []
    sizes = json.loads((a.bench / 'sizes.json').read_text())
    for path in sorted((a.bench / 'scripts').glob('*.lox')):
        _, body = path.read_text().split('\n', 1)
        source = f"var N = {sizes[path.stem]['smoke']};\n{body}"
        for engine in ['tree', 'vm']:
            cases.append({'name': path.stem, 'tier': 'smoke', 'source': source,
                          'engine': engine, 'expected_stdout':
                          (a.bench / 'expected' / f'{path.stem}.smoke.out').read_text()})
    if a.cases:
        for row in json.loads(a.cases.read_text()):
            for engine in ['tree', 'vm']:
                cases.append({'name': row['name'], 'tier': 'regression',
                              'source': row['source'], 'engine': engine,
                              'expected_stdout': row['stdout']})
    for engine, file in [('tree', 'd9-lox-env-reads-runs.json.gz'),
                         ('vm', 'd9-lox-class-method-runs.json.gz')]:
        seen = set()
        with gzip.open(repo / 'docs/audits/evidence' / file) as stream:
            rows = json.load(stream)['traces']
        for row in rows:
            if row['name'] in seen:
                continue
            seen.add(row['name'])
            cases.append({'name': row['name'], 'tier': 'error', 'source': row['source'],
                          'engine': engine, 'expected': row['expected']})
        assert len(seen) == 23
    receipt = {'manifest_sha256': sha(a.manifest), 'binary_sha256': hashes,
               'native_smoke_cases': sorted(selected), 'samples': [],
               'unrun': []}
    if a.resume:
        prior = json.loads(a.resume.read_text())
        assert prior['binary_sha256'] == hashes, 'resume requires identical binaries'
        receipt['samples'] = prior['samples']
        receipt['unrun'] = prior['unrun']
        receipt['resume_provenance'] = {'path': str(a.resume.resolve()),
                                      'sha256': sha(a.resume),
                                      'prior_native_smoke_cases': prior['native_smoke_cases'],
                                      'reason': 'bound expensive corpus native stress; focused regressions and exact errors remain selected'}

    def identity(row):
        return (row['name'], row['tier'], row['engine'], row['arm'], row['lox_gc_stress'])

    done = {identity(row): row for row in receipt['samples']}
    unrun = {identity(row): row for row in receipt['unrun']}

    def save():
        a.out.write_text(json.dumps(receipt, indent=2) + '\n')

    def observe(binary, source, engine, stress, native):
        argv = [binary, '--engine=' + engine, '--stats']
        if stress:
            argv.append('--gc-stress')
        argv.append(str(source))
        launch = dict(env)
        if native:
            launch['MYLANG_OPTIONS'] = '--gc-stress'
        result = subprocess.run(argv, env=launch, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=240)
        return {'status': result.returncode, 'stdout': result.stdout.decode(),
                'stderr': result.stderr.decode()}, argv

    for case in cases:
        source = inputs / f"{case['name']}.{case['engine']}.{case['tier']}.lox"
        source.write_text(case['source'])
        controls = {}
        for backend in ['llvm', 'qbe']:
            for stress in [False, True]:
                expected, _ = observe(bins['control-' + backend], source,
                                      case['engine'], stress, False)
                if case['tier'] != 'error':
                    assert expected['status'] == 0 and expected['stdout'] == case['expected_stdout'], case
                else:
                    historical = case['expected']
                    assert expected['status'] == historical['status']
                    assert expected['stdout'] == historical['stdout']
                    assert expected['stderr'].startswith(historical['stderr'])
                controls[backend, stress] = expected

        def check(key):
            native = '-gc-' in key
            backend = key.rsplit('-', 1)[1]
            rows = []
            for stress in [False, True]:
                meta = {'name': case['name'], 'tier': case['tier'], 'engine': case['engine'],
                        'arm': key, 'lox_gc_stress': stress, 'native_gc_stress': native,
                        'source_sha256': sha(source)}
                if identity(meta) in done:
                    assert done[identity(meta)]['source_sha256'] == sha(source)
                    continue
                if native and case['tier'] == 'smoke' and case['name'] not in selected:
                    if identity(meta) in unrun:
                        continue
                    rows.append(dict(meta, unrun_reason='bounded native stress; selected allocation/property/closure cases cover collector roots'))
                    continue
                actual, cmd = observe(bins[key], source, case['engine'], stress, native)
                expected = controls[backend, stress]
                assert actual == expected, (meta, actual, expected)
                rows.append(dict(meta, command=cmd, expected=expected, actual=actual))
            return rows

        candidates = [key for key in bins if not key.startswith('control-')]
        with ThreadPoolExecutor(max_workers=a.jobs) as pool:
            for future in as_completed([pool.submit(check, key) for key in candidates]):
                for row in future.result():
                    target = 'unrun' if 'unrun_reason' in row else 'samples'
                    receipt[target].append(row)
                    (unrun if target == 'unrun' else done)[identity(row)] = row
                save()
        print(f"PASS {case['engine']}/{case['tier']}/{case['name']}", flush=True)
    assert {name: sha(path) for name, path in bins.items()} == hashes
    receipt['verified_after'] = True
    save()
    print(f"{len(receipt['samples'])} observations passed, {len(receipt['unrun'])} explicitly unrun", flush=True)


if __name__ == '__main__':
    main()

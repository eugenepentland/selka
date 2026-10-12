#!/usr/bin/env python3
"""Validate frozen application inputs and prepare a new 60-case run."""
import hashlib
import json
from pathlib import Path
from receipts import build_path, qualified, validate_build

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OLD = ROOT / 'experiments/lox-eda-zero-rc-20261012/bench'
WORK = ROOT / '.tmp/lox-eda-improvements-20261012'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    destination = HERE / 'specs'
    assert not destination.exists()
    old = json.loads((OLD / 'full-final/full-runtime-summary.json').read_text())
    refs = json.loads((OLD / 'frozen-references.json').read_text())
    for ref in refs['binaries'].values():
        assert sha(ref['frozen']) == ref['sha256']
    manifests = {app: build_path(app) for app in ('lox', 'eda')}
    builds = {app: validate_build(path) for app, path in manifests.items()}
    files = set()
    for app, build in builds.items():
        assert len(build['binaries']) == 6
        qualified(app, manifests[app])
        for binary in build['binaries'].values():
            assert binary['status'] == 'ok' and sha(binary['path']) == binary['sha256']
        files.add(str(manifests[app].resolve()))
        files.add(str((HERE / 'qualification' / app / 'qualified.json').resolve()))
        for source in build['sources'].values():
            for name, identity in source['files'].items():
                path = Path(source['root']) / name
                assert sha(path) == identity
                files.add(str(path))
    specifications = []
    validated_inputs = {}
    for path in sorted((OLD / 'frozen-specs').glob('*.json')):
        spec = json.loads(path.read_text())
        cell = spec['cell']
        if cell == 'lox/vm/step':
            continue
        previous = old['cells'][cell]['identities']
        inputs = set(spec['files'])
        for folder in spec.get('identity_dirs', []):
            inputs.update(str(p) for p in Path(folder).rglob('*') if p.is_file())
        for name in inputs:
            identity = sha(name)
            assert previous[name] == identity, ('historical input changed', cell, name)
            validated_inputs[name] = identity
        app = cell.split('/')[0]
        if spec.get('out_dir'):
            former = spec['out_dir']
            replacement = str(WORK / 'outputs' / cell)
            spec['out_dir'] = replacement
            spec['arms'] = {name: [part.replace(former, replacement) for part in argv] for name, argv in spec['arms'].items()}
            spec['artifacts'] = [name.replace(former, replacement) for name in spec.get('artifacts', [])]
        example = spec['arms']['zig-safe']
        for label in ('original-rc', 'migrated-rc', 'zero-rc'):
            spec['arms']['mylang-' + label] = [builds[app]['binaries'][label]['path'], *example[1:]]
        prior_build_path = ROOT / 'experiments/lox-eda-rerun-20261012/build' / ('lox' if app == 'lox' else 'eda-2') / 'build-receipt.json'
        prior_build = json.loads(prior_build_path.read_text())
        baseline = prior_build['binaries']['zero-rc']
        assert sha(baseline['path']) == baseline['sha256']
        spec['arms']['mylang-before'] = [baseline['path'], *example[1:]]
        spec['relative_timeout_arms'] = ['mylang-zero-rc', 'mylang-before']
        files.add(str(prior_build_path))
        spec['files'] = sorted(set(spec['files']) | files | {str(HERE / 'measure.py'), str(HERE / 'measure_cell.py')})
        spec['env_by_arm'] = {'go': {'GOMAXPROCS': '1', 'GOGC': '100', 'GOMEMLIMIT': 'off'}}
        spec['provenance'] = {'previous_spec': str(path), 'previous_spec_sha256': sha(path),
                              'measurement': 'Fresh runtime/RSS; changed candidate application sources, unchanged compiler, inputs and foreign reference bytes. mylang-before is the frozen checked source before these five changes.',
                              'historical_environment_note': 'Older full-application receipts did not pin Go override variables. This run pins GOMAXPROCS=1, GOGC=100, GOMEMLIMIT=off; cross-run comparisons are observational.'}
        specifications.append((path.name, spec))
    assert len(specifications) == 60
    destination.mkdir()
    for name, spec in specifications:
        (destination / name).write_text(json.dumps(spec, indent=2) + '\n')
    (HERE / 'input-validation.json').write_text(json.dumps({'cells': 60, 'reference_binaries': refs,
         'inputs_matching_previous_run': validated_inputs, 'manifests': {k: str(v) for k, v in manifests.items()}}, indent=2) + '\n')
    print('Prepared all 60 cells; historical inputs and eight reference binary hashes match.')


if __name__ == '__main__':
    main()

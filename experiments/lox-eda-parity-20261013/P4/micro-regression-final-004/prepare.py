#!/usr/bin/env python3
"""Read-only inventory, then explicit final-compiler build and fresh spec creation."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
TOOLS = ROOT / 'experiments/text-gaps-20261012/bench/tools'
ORIGINAL = ROOT / 'experiments/text-gaps-20261012/bench/runs/common-final-002'
SCRATCH = ROOT / '.tmp/lox-eda-parity/P4/micro-regression-final-004'
CASES = ('string_split', 'json_transform', 'csv_aggregate')
FOREIGN = ('zig-safe', 'zig-fast', 'rust', 'go')


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_new(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('x') as stream:
        json.dump(value, stream, indent=2)
        stream.write('\n')


def inventory():
    cells = {}
    pinned = {str(p.resolve()): digest(p) for p in ORIGINAL.rglob('*') if p.is_file()}
    for case in CASES:
        for profile in ('small', 'large'):
            path = ORIGINAL / 'specs' / f'{case}.{profile}.json'
            spec = json.loads(path.read_text())
            assert (spec['warmups'], spec['rounds'], spec['rss_rounds']) == (3, 15, 3)
            for entry in [*spec['arms'].values(), *spec['counted'].values()]:
                assert digest(entry['binary']) == entry['sha256'], entry['binary']
                assert digest(entry['source']) == entry['source_sha256'], entry['source']
                pinned[entry['binary']] = entry['sha256']
                pinned[entry['source']] = entry['source_sha256']
            for name in spec['files']:
                pinned[name] = digest(name)
            cells[path.stem] = {'original_spec': str(path), 'original_spec_sha256': digest(path),
                               'case': case, 'profile': profile, 'size': spec['size'], 'seed': spec['seed'],
                               'protocol': {k: spec[k] for k in ('warmups', 'rounds', 'rss_rounds', 'target_fastest_kernel_ms', 'max_slowest_kernel_ms', 'max_iterations')},
                               'foreign': {name: spec['arms'][name] for name in FOREIGN},
                               'common002_runtime': spec['arms']['checked-candidate'],
                               'common002_counted': spec['counted']['checked-candidate']}
    for path in TOOLS.glob('*.py'):
        pinned[str(path)] = digest(path)
    return {'status': 'prepared; waiting for coordinator final compiler prefix', 'cells': cells,
            'pinned_original_files': pinned,
            'writes': {'inventory': str(HERE / 'inputs.json'), 'build_artifacts': str(SCRATCH),
                       'specs': str(HERE / 'specs'), 'results': str(HERE / 'results'),
                       'reports': str(HERE / 'reports')},
            'protocol': 'Seven arms: C0 checked-baseline, common002 checked-common, final checked-candidate, ZigSafe/ZigFast/Rust/Go. Same three warmups, fifteen rotated/reversed paired rounds, three separate RSS observations and separate three counted checked binaries. CPU8 exclusive lease per cell, fresh calibration and host snapshot; no historical sample pooling.'}


def validate_original(pins):
    for path, sha in pins['pinned_original_files'].items():
        assert digest(path) == sha, path


def build(prefix, expected_sha, pins):
    validate_original(pins)
    compiler = prefix.resolve() / 'bin/mylang'
    assert digest(compiler) == expected_sha, 'final compiler pin mismatch'
    install_pins = {str(p): digest(p) for p in prefix.resolve().rglob('*') if p.is_file()}
    original_spec = json.loads(Path(next(iter(pins['cells'].values()))['original_spec']).read_text())
    source = Path(original_spec['arms']['checked-candidate']['source'])
    clock = Path(original_spec['arms']['checked-candidate']['flags'][original_spec['arms']['checked-candidate']['flags'].index('--link') + 1])
    assert not (HERE / 'builds.json').exists() and not (HERE / 'specs').exists()
    SCRATCH.mkdir(parents=True, exist_ok=True)
    entries = {}
    for kind in ('runtime', 'counted'):
        binary = SCRATCH / f'text-{kind}'
        assert not binary.exists()
        flags = ['--release', '--experimental-zero-rc', '--cache-dir', str(SCRATCH / f'cache-{kind}'), '-o', str(binary), '--link', str(clock)]
        if kind == 'counted':
            flags.append('--counters')
        command = [str(ROOT / 'scripts/build-slot.sh'), 'build', str(compiler), 'build', str(source), *flags]
        with (HERE / f'build-{kind}.log').open('x') as log:
            subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
        entries[kind] = dict(kind=kind, binary=str(binary), sha256=digest(binary), source=str(source),
                             source_sha256=digest(source), flags=flags, command=command, status='ok', zero_rc=True)
    assert install_pins == {str(p): digest(p) for p in prefix.resolve().rglob('*') if p.is_file()}, 'installation changed during builds'
    validate_original(pins)
    manifest = dict(compiler=str(compiler), compiler_sha256=expected_sha, installation=str(prefix.resolve()),
                    installation_files=install_pins, entries=list(entries.values()), original_inputs_sha256=digest(HERE / 'inputs.json'))
    write_new(HERE / 'builds.json', manifest)
    for stem, cell in pins['cells'].items():
        spec = json.loads(Path(cell['original_spec']).read_text())
        spec['arms'] = {'checked-baseline': spec['arms']['checked-baseline'], 'checked-common': spec['arms']['checked-candidate'],
                        'checked-candidate': entries['runtime'], **{name: spec['arms'][name] for name in FOREIGN}}
        spec['counted'] = {'checked-baseline': spec['counted']['checked-baseline'], 'checked-common': spec['counted']['checked-candidate'], 'checked-candidate': entries['counted']}
        before = Path('/home/epentland/ai/canopy/mylang-lox-runtime-stack-20261013-p7/.tmp/lox-eda-parity/P7-micro-windows/final-004') / stem / 'cell.host-before.json'
        spec['cell'] = f'lox-eda-parity/P4/micro-regression-final-004/{cell["case"]}/{cell["profile"]}'
        spec['files'] = sorted(set(spec['files']) | set(install_pins) | {str(HERE / 'inputs.json'), str(HERE / 'builds.json'), str(Path(__file__)), str(HERE / 'README.md'), str(HERE / 'README.md'), str(before), str(TOOLS / 'observe_cell.py'), str(TOOLS / 'schedule_observed.py')})
        spec['provenance'] = {'original_common002_spec': cell['original_spec'], 'original_common002_spec_sha256': cell['original_spec_sha256'],
                              'foreign_reused': True, 'timing_fresh': True, 'arm_order': list(spec['arms']), 'measurement_protocol': pins['protocol'],
                              'host_snapshot': {'path': str(before), 'protocol': 'Read-only snapshot inside CPU8 exclusive lease before calibration/warmup.'}}
        write_new(HERE / 'specs' / f'{stem}.json', spec)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler-prefix', type=Path)
    parser.add_argument('--compiler-sha256')
    args = parser.parse_args()
    if args.compiler_prefix:
        assert args.compiler_sha256, 'explicit coordinator compiler hash required'
        build(args.compiler_prefix, args.compiler_sha256, json.loads((HERE / 'inputs.json').read_text()))
    else:
        assert not args.compiler_sha256
        write_new(HERE / 'inputs.json', inventory())
    print('prepared', len(CASES) * 2, 'cells; no timing submitted')


if __name__ == '__main__':
    main()

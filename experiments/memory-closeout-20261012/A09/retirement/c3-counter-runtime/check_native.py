#!/usr/bin/env python3
"""Qualify unapplied counter hooks against the combined runtime retirement draft."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

import contract
import prepare

HERE = Path(__file__).resolve().parent


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def run(command, output, *, env=None):
    result = subprocess.run(list(map(str, command)), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            env=env, timeout=120)
    output.with_suffix('.stdout').write_bytes(result.stdout)
    output.with_suffix('.stderr').write_bytes(result.stderr)
    record = {'command': list(map(str, command)), 'status': result.returncode,
              'stdout_sha256': hashlib.sha256(result.stdout).hexdigest(),
              'stderr_sha256': hashlib.sha256(result.stderr).hexdigest()}
    output.with_suffix('.json').write_text(json.dumps(record, indent=2) + '\n')
    if result.returncode:
        raise RuntimeError(f'{output}: status {result.returncode}')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--combined-runtime', type=Path, required=True)
    parser.add_argument('--zig', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--audit-existing', action='store_true', help='audit preserved native outputs without rerunning tools')
    args = parser.parse_args()
    if not args.audit_existing and os.environ.get('MYLANG_ADMISSION_KIND') != 'build':
        parser.error('run inside one ordinary build admission')
    if args.output.exists() and not args.audit_existing:
        parser.error('preserve existing qualification evidence')
    if (args.output / 'results.json').exists():
        parser.error('preserve existing audited results')
    args.output.mkdir(parents=True, exist_ok=args.audit_existing)
    driver = subprocess.check_output(['git', 'show', f'{prepare.BASE}:src/core/driver.zig'], cwd=prepare.ROOT).decode()
    runtime_expression = driver.split('pub const runtime_source = ', 1)[1].split(';', 1)[0]
    parts = re.findall(r'@embedFile\("([^"]+)"\)', runtime_expression)
    baseline = b'\n'.join(subprocess.check_output(['git', 'show', f'{prepare.BASE}:src/core/{part}'], cwd=prepare.ROOT)
                           for part in parts)
    combined = args.combined_runtime.read_bytes()
    assert b'MYL_ZERO_RC' not in combined
    records = {}
    for label, runtime in [('before', baseline), ('prepared', combined)]:
        directory = args.output / label
        directory.mkdir(exist_ok=args.audit_existing)
        (directory / 'runtime').mkdir(exist_ok=args.audit_existing)
        source = prepare.SCRATCH / label / 'src/core'
        for name in ('count_runtime.zig', 'runtime/core_count.h', 'runtime/core_count.c'):
            if args.audit_existing:
                assert (source / name).read_bytes() == (directory / name).read_bytes()
            else:
                shutil.copy2(source / name, directory / name)
        if args.audit_existing:
            assert (directory / 'base.c').read_bytes() == runtime
        else:
            (directory / 'base.c').write_bytes(runtime)
        prefix = '#define MYL_ZERO_RC 1\\n' if label == 'before' else ''
        exporter = ('const std=@import("std");\nconst count=@import("count_runtime.zig");\n'
                    'pub fn main(init:std.process.Init)!void {\n'
                    'const text=try count.source(init.arena.allocator(),@embedFile("base.c"));\n'
                    f'try std.Io.File.stdout().writeStreamingAll(init.io,"{prefix}");\n'
                    'try std.Io.File.stdout().writeStreamingAll(init.io,text);\n}\n')
        if args.audit_existing:
            assert (directory / 'export.zig').read_text() == exporter
            exported = (directory / 'export-run.stdout').read_bytes()
            assert (directory / 'counted.c').read_bytes() == exported + b'\n' + (HERE / 'native_control.c').read_bytes()
            nm = (directory / 'nm.stdout').read_text()
        else:
            (directory / 'export.zig').write_text(exporter)
            run([args.zig, 'build-exe', directory / 'export.zig', '-O', 'ReleaseFast',
                 '-femit-bin=' + str(directory / 'export')], directory / 'export-build')
            exported = run([directory / 'export'], directory / 'export-run').stdout
            (directory / 'counted.c').write_bytes(exported + b'\n' + (HERE / 'native_control.c').read_bytes())
            run([args.zig, 'cc', '-std=c11', '-O2', '-g0', '-fno-sanitize=all', '-ffunction-sections',
                 '-fdata-sections', '-Wl,--gc-sections', directory / 'counted.c', '-pthread', '-lm',
                 '-o', directory / 'control'], directory / 'native-build')
            nm = run(['nm', '-a', directory / 'control'], directory / 'nm').stdout.decode()
        forbidden = re.findall(r'\bmyl_core_(?:retain(?:_slow)?|release(?:_slow)?|free_block|share)\b', nm)
        if forbidden:
            raise ValueError('linked legacy helpers: ' + repr(forbidden))
        observations = []
        for length in (128, 65537):
            for workers in (1, 2, 8):
                stem = directory / f'control-{length}-{workers}'
                counts = stem.with_suffix('.counts.json')
                env = dict(os.environ, MYLANG_COUNTERS=str(counts))
                if args.audit_existing:
                    assert json.loads(stem.with_suffix('.json').read_text())['status'] == 0
                    assert stem.with_suffix('.stdout').read_bytes() == b'native counter control passed\n'
                    assert not stem.with_suffix('.stderr').read_bytes()
                else:
                    ran = run([directory / 'control', workers, length], stem, env=env)
                    assert ran.stdout == b'native counter control passed\n' and not ran.stderr
                audited = contract.audit(counts, guest_abi=contract.ABI)
                raw = json.loads(counts.read_text())
                assert audited['managed_leak_free'] and audited['direct_frees'] == 2 * workers
                assert raw['totals']['allocs'] == raw['totals']['frees']
                assert raw['totals']['alloc_bytes'] + raw['totals']['realloc_added_bytes'] == raw['totals']['free_bytes']
                assert raw['totals']['calls'] == workers
                assert raw['totals']['list_copies'] == workers
                assert raw['totals']['list_copy_bytes'] == length * 8 * workers
                assert raw['kinds']['list_copy']['count'] == workers
                assert raw['kinds']['list_push']['count'] == length * workers
                assert raw['kinds']['list_push']['bytes'] == length * 8 * workers
                assert raw['totals']['list_grows'] > 0 and raw['totals']['peak_live_bytes'] > 0
                if length > 128:
                    assert raw['totals']['reallocs'] > 0 and raw['totals']['realloc_added_bytes'] > 0
                observations.append({'length': length, 'workers': workers, 'counts_sha256': sha(counts),
                                     'totals': raw['totals'], 'kinds': raw['kinds'], 'passed': True})
        records[label] = {'runtime_sha256': hashlib.sha256(runtime).hexdigest(),
                          'instrumented_runtime_sha256': hashlib.sha256(exported).hexdigest(),
                          'binary_sha256': sha(directory / 'control'), 'runs': observations}
    # Allocator rounding and realloc placement under concurrent native threads
    # can change usable byte traffic, while counter events remain identical.
    placement = {'peak_live_bytes', 'realloc_moves', 'realloc_moved_bytes'}
    for old, new in zip(records['before']['runs'], records['prepared']['runs']):
        excluded = placement | ({'alloc_bytes', 'free_bytes', 'realloc_added_bytes'}
                                if old['length'] > 128 and old['workers'] > 1 else set())
        assert {k: v for k, v in old['totals'].items() if k not in excluded} == {
            k: v for k, v in new['totals'].items() if k not in excluded}
        for kind in old['kinds']:
            for field in ('count', 'bytes'):
                assert old['kinds'][kind][field] == new['kinds'][kind][field]
    result = {'scope': 'Native scratch-runtime telemetry controls; no production retirement or final guest ABI claim',
              'base': prepare.BASE, 'combined_runtime_path': str(args.combined_runtime),
              'combined_runtime_sha256': sha(args.combined_runtime), 'control_source_sha256': sha(HERE / 'native_control.c'),
              'counter_patch_sha256': sha(HERE / 'counters.patch'),
              'audit_of_preserved_executions': args.audit_existing,
              'zig_sha256': sha(args.zig), 'records': records, 'passed': True,
              'limitations': ['C3 parser ABI argument is synthetic for these native controls; no guest LLVM was emitted.',
                              'Core task scheduler synchronization is unchanged by the counter patch; native controls use pthread join.',
                              'Peak and moved bytes vary across separately scheduled allocator runs.',
                              'Large multithreaded usable allocation bytes vary with allocator rounding; every run still balances alloc+realloc bytes against frees.',
                              'Small-list and serial-large traffic, all event counts and element-copy traffic agree exactly before/after.']}
    (args.output / 'results.json').write_text(json.dumps(result, indent=2) + '\n')
    print('12 native telemetry controls passed; deterministic before/after traffic agrees')


if __name__ == '__main__':
    main()

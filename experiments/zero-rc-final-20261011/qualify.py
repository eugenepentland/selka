#!/usr/bin/env python3
"""Exercise packaged compiler cache modes and survey unmodified library fixtures."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time
sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE.parent / 'zero-rc-20261011'))
import measure as common

def run(argv, prefix, env):
    prefix.parent.mkdir(parents=True, exist_ok=True)
    start = time.perf_counter_ns()
    result = subprocess.run(list(map(str, argv)), cwd=ROOT, env=env, capture_output=True, timeout=300)
    prefix.with_suffix('.stdout').write_bytes(result.stdout)
    prefix.with_suffix('.stderr').write_bytes(result.stderr)
    record = {'argv': list(map(str, argv)), 'status': result.returncode, 'elapsed_ns': time.perf_counter_ns() - start,
              'stdout': result.stdout.decode(), 'stderr': result.stderr.decode()}
    common.save(prefix.with_suffix('.json'), record)
    return record

def report(record):
    return next(json.loads(line) for line in record['stderr'].splitlines() if line.startswith('{') and 'cache-report-v1' in line)

def cache(args, env):
    directory = args.output / 'cache-qualification'
    directory.mkdir(parents=True, exist_ok=True)
    source, binary, store = directory / 'sample.my', directory / 'program', directory / 'cache'
    template = '''func make(n: int) -> int[]:
    mut values: int[] = []
    for i in range(n):
        values.append(i)
    return values
func main(out: Stream) -> int:
    const values = make(SIZE)
    out.print(len(values))
    return 0
'''
    source.write_text(template.replace('SIZE', '5'))
    records = []
    def build(label, mode, llvm=False, expected='5\n'):
        flags = [] if mode == 'rc' else ['--experimental-' + mode]
        emitted = directory / (label + '.ll')
        command = [args.compiler, 'build', source, '--counters', '--zig', args.zig,
                   '--cache-dir', store, '-o', binary, '--report', *flags, *(['--emit-llvm', emitted] if llvm else [])]
        compiled = run(command, directory / (label + '-build'), env)
        assert compiled['status'] == 0, compiled
        counts = directory / ('counts-' + label + '.json')
        executed = run([binary], directory / (label + '-run'), dict(env, MYLANG_COUNTERS=str(counts)))
        assert executed['status'] == 0 and executed['stdout'] == expected and not executed['stderr'], executed
        audit = common.audit.audit(counts)
        assert audit['managed_leak_free'], audit
        symbols = subprocess.run(['nm', binary], capture_output=True, text=True, check=True).stdout
        if mode == 'zero-rc':
            assert audit['observed_rc_free'], audit
            assert not any(symbol in symbols for symbol in ('myl_core_retain', 'myl_core_release', 'myl_core_share'))
        else:
            assert 'myl_core_release' in symbols
        record = {'label': label, 'mode': mode, 'build_ns': compiled['elapsed_ns'], 'report': report(compiled),
                  'audit': audit, 'binary_sha256': common.digest(binary), 'source_sha256': common.digest(source)}
        records.append(record)
        return record
    for i, mode in enumerate(('rc', 'zero-rc', 'single-owner', 'zero-rc', 'rc', 'single-owner')):
        build('mode-' + str(i), mode, llvm=True)
    assert records[3]['report']['stages']['lowering']['reused'] > 0
    build('native-first', 'zero-rc')
    build('native-replay', 'zero-rc')
    # Preserve replay records, then exercise emission/native caches independently.
    # Zero-RC intentionally keeps eager ownership validation and loads Core bodies.
    saved = directory / 'replay-records'
    saved.mkdir(exist_ok=True)
    for path in (store / 'replay-v1').glob('*'):
        path.rename(saved / path.name)
    restored = build('native-no-replay', 'zero-rc')
    assert restored['report']['stages']['emission']['reused'] > 0, restored
    assert restored['report']['reused'] > 0, restored
    source.write_text(template.replace('SIZE', '6'))
    build('source-changed', 'zero-rc', expected='6\n')
    source.write_text('''func main(out: Stream) -> int:
    mut a = [1, 2]
    const b = a
    out.print(len(a), len(b))
    return 0
''')
    rejected = run([args.compiler, 'build', source, '--experimental-zero-rc', '--release', '--zig', args.zig,
                    '--cache-dir', store, '-o', binary], directory / 'invalid-owner', env)
    assert rejected['status'] != 0 and 'moved' in rejected['stderr'], rejected
    return {'runs': records, 'changed_invalid_source': rejected}

def library(args, env):
    results = {}
    for source in sorted((ROOT / 'src/stdlib/fixtures').glob('*.my')):
        if source.stem == 'time_random_provider':
            continue # Requires an injected native provider; resource fixtures cover that boundary.
        directory = args.output / 'library' / source.stem
        directory.mkdir(parents=True, exist_ok=True)
        entry_source = directory / 'main.my'
        entry_source.write_bytes(source.read_bytes())
        lanes = {}
        for mode in ('rc', 'zero-rc'):
            binary = directory / mode
            compiled = run([args.compiler, 'build', entry_source, '--release', '--counters', '--zig', args.zig,
                            '--cache-dir', args.output / 'library-cache', '-o', binary,
                            *(['--experimental-zero-rc'] if mode == 'zero-rc' else [])], directory / (mode + '-build'), env)
            entry = {'build': compiled}
            if compiled['status'] == 0:
                counts = directory / ('counts-' + mode + '.json')
                entry['run'] = run([binary], directory / (mode + '-run'), dict(env, MYLANG_COUNTERS=str(counts)))
                expected = 0 if source.stem == 'time_random' else 42
                assert entry['run']['status'] == expected and not entry['run']['stderr'], entry
                entry['audit'] = common.audit.audit(counts)
                assert entry['audit']['managed_leak_free'], entry
                if mode == 'zero-rc':
                    assert entry['audit']['observed_rc_free'], entry
            elif mode == 'rc':
                raise RuntimeError(compiled)
            lanes[mode] = entry
        results[source.stem] = {'source_sha256': common.digest(source), 'lanes': lanes}
        print('library', source.stem, 'supported' if lanes['zero-rc']['build']['status'] == 0 else 'refused', flush=True)
        common.save(args.output / 'library-partial.json', results)
    return results

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ('compiler', 'zig', 'output'):
        parser.add_argument('--' + key, type=Path, required=True)
    args = parser.parse_args()
    for key in ('compiler', 'zig', 'output'):
        setattr(args, key, getattr(args, key).resolve())
    env = dict(os.environ, MYLANG_ZIG=str(args.zig), ZIG=str(args.zig), MYL_CORE_LEAKCHECK='1')
    env.pop('MYLANG_COUNTERS', None)
    result = {'schema': 'zero-rc-final-qualification-v1', 'compiler_sha256': common.digest(args.compiler), 'harness_sha256': common.digest(__file__)}
    result['cache'] = cache(args, env)
    common.save(HERE / 'qualification.json', result)
    print('cache: passed', flush=True)
    result['library'] = library(args, env)
    assert result['compiler_sha256'] == common.digest(args.compiler)
    common.save(HERE / 'qualification.json', result)

if __name__ == '__main__':
    main()

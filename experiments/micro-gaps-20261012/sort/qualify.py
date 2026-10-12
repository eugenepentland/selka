#!/usr/bin/env python3
"""Build/qualify sort guests; caller holds build admission, never timing admission."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def run(command, **kwargs):
    result = subprocess.run(list(map(str, command)), capture_output=True, text=True, **kwargs)
    if result.returncode or result.stderr:
        raise RuntimeError(f'{command}: rc={result.returncode}\n{result.stdout}{result.stderr}')
    return result.stdout


def check_counts(path):
    counters = json.loads(path.read_text())
    totals = counters['totals']
    assert totals['live_bytes_at_exit'] == 0, totals
    for name in ('runtime_retains', 'runtime_releases', 'shared_retains', 'shared_releases', 'share_marks'):
        assert totals[name] == 0, (name, totals[name])
    for site in counters['sites']:
        if site['kind'] in ('retain', 'release', 'unique_test', 'uniqueness'):
            assert site['count'] == 0, site
    return totals


def oracle(case, size, iterations, seed):
    checksum = 0
    for batch in range(iterations):
        values = [(seed + batch + j * 13) % 1009 for j in range(size)]
        if case == 'sort_int':
            part = sum((j + 1) * value for j, value in enumerate(sorted(values)))
        else:
            rows = sorted(enumerate(values), key=lambda row: row[1] % 17)
            part = sum((j + 1) * (value * 17 + ordinal) for j, (ordinal, value) in enumerate(rows))
        checksum = (checksum + part) % 1000000007
    return checksum


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    source = root / 'experiments/micro-ownership-20261012/expanded/migrated/collections.my'
    clock = root / 'benchmarks/runtime/ports/native_clock.c'
    records = []
    for counted in (False, True):
        binary = output / ('collections-counted' if counted else 'collections')
        llvm = binary.with_suffix('.ll')
        command = [args.compiler, 'build', source, '-o', binary, '--release', '--experimental-zero-rc', '--link', clock,
                   '--cache-dir', output / 'cache', '--emit-llvm', llvm]
        if counted:
            command.append('--counters')
        run(command)
        symbols = run(['nm', '--defined-only', binary])
        forbidden = ('myl_core_retain', 'myl_core_release', 'myl_core_ensure_unique')
        defined_names = {line.split()[-1] for line in symbols.splitlines() if line.split()}
        assert not set(forbidden) & defined_names, set(forbidden) & defined_names
        emitted = llvm.read_text()
        assert '@myl_core_owned_sort_keyed' in emitted
        for symbol in ('@myl_core_retain(', '@myl_core_release(', '@myl_core_ensure_unique('):
            assert symbol not in emitted, symbol
        for case in ('sort_int', 'sort_records'):
            for size in (64, 4096):
                counts = output / f'{case}-{size}-counts.json'
                environment = dict(os.environ, MYL_CORE_LEAKCHECK='1')
                if counted:
                    environment['MYLANG_COUNTERS'] = str(counts)
                # Qualification only: discard the guest's native clock duration.
                stdout = run([binary, case, size, 3, 42], env=environment)
                expected = oracle(case, size, 3, 42)
                assert int(stdout.split()[0]) == expected, (case, size, stdout, expected)
                item = dict(case=case, size=size, iterations=3, seed=42, checksum=expected,
                            counted=counted, binary=str(binary), binary_sha256=digest(binary),
                            llvm_sha256=digest(llvm), build_command=list(map(str, command)), native_forbidden_symbols=list(forbidden),
                            additional_raw_scratch_bytes_per_sort=size * 24 if case == 'sort_records' else 0,
                            additional_raw_scratch_malloc_free_pairs=3 if case == 'sort_records' else 0)
                if counted:
                    item['counts'] = str(counts)
                    item['totals'] = check_counts(counts)
                    item['counts_sha256'] = digest(counts)
                records.append(item)
    receipt = dict(schema='micro-gap-sort-qualification-v1', compiler=str(args.compiler.resolve()),
                   compiler_sha256=digest(args.compiler), source=str(source), source_sha256=digest(source),
                   clock_sha256=digest(clock), build_jobs=os.environ.get('MYLANG_JOBS'), records=records,
                   limitation='Qualification clocks discarded; parent supplies exclusive paired runtime/RSS measurements. Raw scratch is source-derived requested bytes, excluding allocator overhead.')
    (output / 'qualification.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps(dict(qualified=len(records), receipt=str(output / 'qualification.json'))))


if __name__ == '__main__':
    main()

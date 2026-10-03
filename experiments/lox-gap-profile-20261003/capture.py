#!/usr/bin/env python3
"""Freeze completed sampled profiles without running new guest measurements."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import shutil
import subprocess


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text())


def save(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--receipt', type=Path, required=True)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    work, archive = args.work.resolve(), args.archive.resolve()
    guards = read(work / 'guards.json')
    binaries = read(work / 'binaries.json')
    sources = read(repo / 'experiments/lox-ast-constant-20261003/sources.json')['ast']
    assert len(guards) == 102 and len(sources) == 37
    for path, digest in guards.items():
        assert sha(Path(path)) == digest, path
    for name, digest in sources.items():
        assert sha(work / 'ast' / name) == digest, name
    decoded = read(work / 'profiles/ast-qbe/decoded-summary.json')
    modules = decoded['same_build_module_manifests']
    symbols = {}
    for item in modules:
        path = Path(item['path'])
        assert sha(path) == item['sha256'], path
        for function in read(path)['functions']:
            symbol, name = function['symbol'], function['name']
            assert symbol not in symbols or symbols[symbol] == name
            symbols[symbol] = name
    assert symbols == decoded['symbol_map']
    arms = ('ast-llvm', 'ast-qbe', 'rust')
    expected_cases = {'vm/fib', 'vm/string_equality', 'tree/binary_trees', 'tree/closures'}
    jobs = []
    for arm in arms:
        summary = read(work / 'profiles' / arm / 'summary.json')
        completion = read(work / 'profiles' / arm / 'complete.json')
        assert completion['verified_after'] and completion['cases'] == 4
        assert {row['case'] for row in summary} == expected_cases
        assert len(summary) == 4
        for row in summary:
            assert row['arm'] == arm
            assert row['binary_sha256'] == binaries['binary_sha256'][arm]
            assert row['binary_sha256'] == completion['binary_sha256']
            argv = row['command']
            assert argv[:12] == ['taskset', '-c', '10', 'perf', 'record', '-q',
                                '-F', '499', '-e', 'cycles:u', '--call-graph', 'dwarf,8192']
            assert sha(Path(argv[-1])) == row['script_sha256']
            assert sha(Path(row['symbols_path'])) == row['symbols_sha256']
            engine, name = row['case'].split('/')
            expected = work / 'reference/benchmarks/lox/bench/expected' / f'{name}.{engine}.out'
            assert row['verification']['stdout_sha256'] == sha(expected)
            assert row['verification']['status'] == 0
            assert row['verification']['stderr'] == ''
            assert row['record_stderr'] == ''
            assert row['quiet_waits']
            assert max(row['quiet_waits'][-1]['busy'].values()) < .25
            jobs.append({'arm': arm, 'case': row['case'],
                         'top_self_samples': row['rows'][:9]})
    raw_qbe = read(work / 'profiles/ast-qbe/summary.json')
    assert len(decoded['rows']) == len(raw_qbe)
    for raw, mapped in zip(raw_qbe, decoded['rows']):
        assert raw['case'] == mapped['case']
        assert len(raw['rows']) == len(mapped['rows'])
        for before, after in zip(raw['rows'], mapped['rows']):
            assert before['symbol'] == after['symbol'] and before['self_pct'] == after['self_pct']
            assert after['name'] == before['name']
            mapped_name = after['decoded_name_from_qbe_module_manifests']
            assert mapped_name == symbols.get(before['symbol'], before['symbol'])
    for arm in binaries['binaries']:
        assert sha(Path(binaries['binaries'][arm])) == binaries['binary_sha256'][arm]
    archive.mkdir(parents=True, exist_ok=False)
    payloads = {}

    def copy(path, relative):
        target = archive / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
        digest = sha(path)
        assert sha(target) == digest
        payloads[relative] = {'original_path': str(path), 'sha256': digest,
                              'bytes': target.stat().st_size}

    for path in sorted(work.rglob('*')):
        if path.is_file():
            copy(path, 'work/' + str(path.relative_to(work)))
    for item in modules:
        path = Path(item['path'])
        copy(path, 'same-build-qbe-modules/' + path.name)
    for name in ('experiments/lox-parity-20261003/profile.py',
                 'experiments/lox-performance-audit-20261002/audit.py',
                 'experiments/lox-ast-constant-20261003/sources.json',
                 'experiments/lox-gap-profile-20261003/capture.py',
                 'docs/audits/lox-ast-carrier-sealed-2026-10-03.json'):
        copy(repo / name, 'helpers/' + name)
    for path, digest in guards.items():
        assert sha(Path(path)) == digest, path
    for item in modules:
        assert sha(Path(item['path'])) == item['sha256']
    for name, digest in sources.items():
        assert sha(work / 'ast' / name) == digest
    manifest = {'created_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                'root_commit_at_capture': subprocess.check_output(
                    ['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip(),
                'purpose': 'completed selected-AST sampled profile diagnosis; no new measurements',
                'original_guards': guards, 'verified_after_copy': True, 'payloads': payloads}
    save(archive / 'MANIFEST.json', manifest)
    for relative, item in payloads.items():
        assert sha(archive / relative) == item['sha256'], relative
    receipt = {'archive': str(archive), 'manifest_sha256': sha(archive / 'MANIFEST.json'),
               'payloads': len(payloads), 'payload_bytes': sum(x['bytes'] for x in payloads.values()),
               'stable_guarded_inputs': len(guards), 'selected_source_files': len(sources),
               'completed_profile_jobs': len(jobs), 'arms': list(arms),
               'copied_but_not_profiled': ['go'], 'binary_sha256': binaries['binary_sha256'],
               'qbe_same_build_module_manifests': len(modules), 'mapped_symbols': len(symbols),
               'all_rehashed_after_copy': True,
               'perf_version_at_capture': subprocess.check_output(['perf', '--version'], text=True).strip(),
               'sampling': {'event': 'cycles:u', 'frequency_hz': 499,
                            'callgraph': 'dwarf,8192', 'cpu': 10,
                            'report': 'self overhead, no children, percent limit 0.1',
                            'cases': sorted(expected_cases)},
               'limits': ['One sampled profile per arm/case; no timing or counter selection matrix.',
                          'Self percentages are within each process and affected by inlining.',
                          'No absolute cross-language overhead is inferred from percentages.',
                          'QBE final sidecar has no functions; names decoded from same-build module manifests.',
                          'Raw perf.data, reports, original summaries and all decode inputs are retained.',
                          'Expected stdout files retained; successful helper comparisons recorded hashes, not duplicate streams.',
                          'No new Guardian, public-test, native-GC or compiler qualification from profiling.'],
               'jobs': jobs}
    save(args.receipt, receipt)
    print(json.dumps({k: receipt[k] for k in ('archive', 'manifest_sha256', 'payloads',
                                            'stable_guarded_inputs', 'completed_profile_jobs')}))


if __name__ == '__main__':
    main()

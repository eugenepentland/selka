#!/usr/bin/env python3
"""Validate and summarize the frozen three-arm deferred paired measurements."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import statistics


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def keys(row):
    return {t['name']: t.get('cache', {}).get('key') for t in row['report']['tests']}


def verdicts(row):
    return {t['name']: ('passed' if t['status'] == 'cached' else t['status'],
                        t.get('reason', ''), t.get('at', '')) for t in row['report']['tests']}


def numeric_tree_sum(values):
    result = {}
    for value in values:
        for name, field in value.items():
            if isinstance(field, dict):
                result[name] = numeric_tree_sum([result.get(name, {}), field])
            elif isinstance(field, (int, float)):
                result[name] = result.get(name, 0) + field
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--benchmark', type=Path, required=True)
    parser.add_argument('--admission', type=Path, required=True)
    parser.add_argument('--original-hashes', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report_path = args.benchmark / 'results.json'
    report = json.loads(report_path.read_text())
    assert report.get('completed_utc') and len(report['records']) == 69
    records = report['records']
    fixture = 'synthetic-510436'
    variants = ['baseline', 'comparison', 'candidate-zlib']
    original = {v: next(r for r in records if r['variant'] == v and r['phase'] == 'cold') for v in variants}
    reference = verdicts(original['baseline'])
    assert len(reference) == 662
    assert all(r['exit'] == 0 and verdicts(r) == reference for r in records)
    assert {r['fixture'] for r in records} == {fixture}
    oracle_pairs = 0
    restored_pairs = 0
    for variant in variants:
        expected_keys = keys(original[variant])
        for phase in ['private', 'helper', 'three-file']:
            edits = [r for r in records if r['variant'] == variant and r['phase'] == phase]
            assert sorted(r['sample'] for r in edits) == [0, 1, 2]
            signatures = set()
            for row in edits:
                actual_keys = keys(row)
                assert any(key is not None and key != expected_keys.get(test) for test, key in actual_keys.items())
                assert row['counts'].get('passed', 0) > 0
                signature = tuple(sorted(actual_keys.items()))
                assert signature not in signatures
                signatures.add(signature)
                restored = next(r for r in records if (r['variant'], r['phase'], r['sample']) == (variant, 'restore-' + phase, row['sample']))
                assert keys(restored) == expected_keys and restored['counts'] == {'cached': 662}
                restored_pairs += 1
                if variant == 'candidate-zlib':
                    forced = next(r for r in records if (r['variant'], r['phase'], r['sample']) == (variant, phase + '-forced', row['sample']))
                    assert keys(forced) == actual_keys and forced['counts'] == {'passed': 662}
                    oracle_pairs += 1
    original_hashes = json.loads(args.original_hashes.read_text())
    source = Path(original_hashes['source'])
    current = {str(p.relative_to(source)): digest(p) for p in sorted(source.iterdir()) if p.is_file()}
    assert current == original_hashes['files'], 'source was not restored byte-for-byte'
    corpus_sha256 = hashlib.sha256(json.dumps(current, sort_keys=True).encode()).hexdigest()
    assert corpus_sha256 == original_hashes['corpus_sha256']
    admission_path = args.admission / 'results.json'
    admission = json.loads(admission_path.read_text())
    assert admission['wrapper_exit'] == 0 and admission['kind'] == 'gate'
    summary = {'scope': 'Frozen historical Wave2 optimization; independent of current-main follow-up changes',
               'started_utc': report['started_utc'], 'completed_utc': report['completed_utc'],
               'compilers': report['compilers'], 'execution_context': report['execution_context'],
               'fixture': report['fixtures'][fixture], 'corpus_sha256': corpus_sha256,
               'correctness': {'successful_invocations': len(records), 'normalized_verdicts_agree': True,
                               'tests_per_invocation': len(reference), 'candidate_forced_key_pairs': oracle_pairs,
                               'restored_original_key_pairs': restored_pairs, 'fresh_edit_signatures': 27,
                               'source_restored': True},
               'admission': {k: admission[k] for k in ['queue_s', 'held_s', 'command_wall_s', 'wrapper_exit']},
               'summed_compiler_wall_s': sum(r['wall_s'] for r in records), 'measurements': {},
               'evidence': {str(p): digest(p) for p in [report_path, admission_path, args.original_hashes]},
               'limitations': ['Three first-edit samples per phase, with reversed arm order on alternating rounds; no significance claim.',
                               'Cold application/native/Zig stores, with existing installed toolchain and operating-system page cache.',
                               'GNU time RSS is maximum individual process RSS, not concurrent process-tree memory.',
                               'Unrelated focused builds may execute on CPUs excluding reserved timing CPUs; no parallel gate.',
                               'Aggregate held time includes oracle, inventory, serialization and harness overhead; it is not a direct compiler speedup measure.']}
    for variant in variants:
        summary['measurements'][variant] = {}
        for phase in ['cold', 'noop', 'private', 'helper', 'three-file', 'restore-private', 'restore-helper', 'restore-three-file']:
            rows = sorted([r for r in records if r['variant'] == variant and r['phase'] == phase], key=lambda r: r['sample'])
            item = {'samples': len(rows), 'counts': [r['counts'] for r in rows], 'raw': []}
            for metric in ['wall_s', 'user_s', 'system_s', 'peak_rss_kb']:
                values = [r[metric] for r in rows]
                item[metric] = {'median': statistics.median(values), 'min': min(values), 'max': max(values), 'samples': values}
            for row in rows:
                item['raw'].append({'label': row['label'], 'new_native_objects': row['new_native_objects'],
                                    'new_guest_unit_objects': row['new_guest_unit_objects'], 'new_runtime_objects': row['new_runtime_objects'],
                                    'retained_cache': row['retained_cache'],
                                    'work_totals': numeric_tree_sum(row['work'].values())})
            summary['measurements'][variant][phase] = item
    summary['optimized_over_comparison_wall_ratio'] = {phase: summary['measurements']['candidate-zlib'][phase]['wall_s']['median'] / summary['measurements']['comparison'][phase]['wall_s']['median'] for phase in summary['measurements']['comparison']}
    args.output.write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps({'output': str(args.output), 'correctness': summary['correctness'], 'ratios': summary['optimized_over_comparison_wall_ratio']}))


if __name__ == '__main__':
    main()

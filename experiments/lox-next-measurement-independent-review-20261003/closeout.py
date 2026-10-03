#!/usr/bin/env python3
"""Audit later completed phases without replacing the initial observation."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
import audit


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    assert not args.out.exists(), 'choose a new path; preserve earlier observations'
    root = args.root.resolve()
    initial_path = Path(__file__).with_name('review.json')
    initial = audit.load(initial_path)
    assert audit.sha(initial_path) == '464ce3d42329714fe034e7a138dfe203f44a30b3437d3e5284250162982500d6'
    manifests = {}
    manifest_reports = []
    for old in initial['manifests']:
        path = Path(old['path'])
        assert audit.sha(path) == old['sha256']
        doc, report = audit.manifest(path)
        manifests[path.parent] = doc
        manifest_reports.append(report)
    for old in initial['completed_measurements']:
        path = Path(old['path'])
        assert audit.sha(path) == old['sha256']
        assert audit.sha(path.with_suffix('.command.json')) == old['command_sha256']
        assert audit.sha(path.with_suffix('.log')) == old['log_sha256']
    for old in initial['analyses']:
        assert audit.sha(old['path']) == old['sha256']
    for old in initial['helpers']:
        assert audit.sha(old['path']) == old['sha256']
    measured = set().union(*(set(m['binary_sha256'].values()) for m in manifests.values()))
    build_reports = []
    nextwork = root / '.tmp-lox-next'
    writework = root / '.tmp-lox-write-screen'
    for work, labels in [(nextwork, ['baseline', 'vmcallee', 'tableentries', 'combined']),
                         (writework, ['write-baseline', 'write-combined'])]:
        for label in labels:
            source = manifests[work]['candidate_sources'][label]
            path = Path(source.get('build_receipt', str(root / '.tmp-lox-parity/carrier-final-sweep-build.json')))
            old = next(r for r in initial['guest_builds'] if r['receipt'] == str(path))
            assert audit.sha(path) == old['receipt_sha256']
            build_reports.append(audit.builds(path, source, measured))
    old_paths = {r['path'] for r in initial['completed_measurements']}
    completed = []
    docs = {}
    pending = []
    for work in [nextwork, writework]:
        for path in sorted((work / 'measurements').glob('*.json')):
            if str(path) in old_paths:
                continue
            # Ongoing atomic sample snapshots can change; never certify/hash
            # their prefix as a completed measurement.
            current = json.loads(path.read_bytes())
            if 'phase' not in current or 'samples' not in current:
                continue
            if current.get('verified_after'):
                doc, report = audit.measurement(path, manifests[work])
                if path.stem == 'combined-counters':
                    assert doc['phase'] == 'counters' and doc['rounds'] == 3
                    assert len(doc['samples']) == 468
                    assert set(doc['binary_sha256']) == {
                        'baseline-llvm', 'baseline-qbe', 'combined-llvm', 'combined-qbe', 'rust', 'go'}
                    report['scope'] = 'full source/reference counter comparison'
                elif path.stem == 'write-attribution-timing':
                    assert doc['phase'] == 'time' and doc['rounds'] == 3
                    assert len(doc['samples']) == 312
                    assert set(doc['binary_sha256']) == {
                        'combined-llvm', 'combined-qbe', 'write-combined-llvm', 'write-combined-qbe'}
                    report['scope'] = 'compiler attribution on exact source84; no new Rust/Go parity comparison'
                else:
                    report['scope'] = 'later phase with exact command-declared coverage'
                completed.append(report)
                docs[path.stem] = doc
            else:
                count = len(current['cases']) * len(current['binary_sha256']) * current['rounds']
                pending.append({'path': str(path), 'scope': 'partial, no complete pass claimed',
                                'observed_samples': len(current['samples']), 'target_samples': count,
                                'observed_utc': datetime.datetime.now(datetime.timezone.utc).isoformat()})
    assert 'combined-counters' in docs
    analyses = [audit.analysis(nextwork / 'measurements/combined-counter-analysis.json', docs['combined-counters'])]
    attribution = writework / 'measurements/write-attribution-wall-analysis.json'
    if attribution.exists() and 'write-attribution-timing' in docs:
        analyses.append(audit.analysis(attribution, docs['write-attribution-timing']))
        recorded = audit.load(attribution)
        assert recorded['sha256'] == audit.sha(writework / 'measurements/write-attribution-timing.json')
        assert recorded['coverage_verified'] and recorded['compiler_only_attribution']
        copied = root / 'experiments/lox-callee-table-checkpoint-20261003/write-attribution.json'
        assert audit.read(copied) == audit.read(attribution)
        analyses[-1]['tracked_copy'] = str(copied)
        analyses[-1]['tracked_copy_sha256'] = audit.sha(copied)
    elif 'write-attribution-timing' in docs:
        # Recompute pairs even if the root's final analysis file is not ready.
        doc = docs['write-attribution-timing']
        comparisons = {}
        for backend in ['llvm', 'qbe']:
            comparisons[backend] = audit.compare(doc, 'combined-' + backend,
                                                 'write-combined-' + backend, 'wall_s')
        analyses.append({'scope': 'independent compiler-attribution paired arithmetic',
                         'comparisons': {k: v['engines'] for k, v in comparisons.items()}})
    for path, digest in list(audit.READS.items()):
        assert hashlib.sha256(Path(path).read_bytes()).hexdigest() == digest, ('changed during review', path)
    result = {
        'recorded_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'outcome': 'new completed phases pass provenance, full coverage, output and paired arithmetic checks',
        'primary_review_commit': '2a3d750d27d06487306228b337a5b1a1a38ee502',
        'primary_review_sha256': audit.sha(initial_path),
        'primary_observation_retained_unchanged': True,
        'primary_completed_rows_unchanged': 1300,
        'manifests': manifest_reports,
        'guest_builds_reverified': build_reports,
        'completed_measurements': completed,
        'analyses': analyses,
        'pending': pending,
        'stable_read_input_count': len(audit.READS),
        'stable_read_inputs_identity_sha256': hashlib.sha256(json.dumps(audit.READS, sort_keys=True).encode()).hexdigest(),
        'guest_executions': 0,
        'perf_executions': 0,
        'source_or_root_mutations': 0,
        'limits': [
            'Raw stdout was checked by the producer and only hashes are retained; expected output hashes independently match.',
            'Every completed new stderr sample is empty ASCII text; the producer 1500-character tail therefore contains its complete decoded diagnostic.',
            'PMU values and all four running rates are independently checked in retained rows; per-sample raw CSV was not archived.',
            'Primary retention, statistical interpretation and build-provenance limits still apply.',
            'Compiler attribution timing excludes Rust and Go and does not create a new parity claim.',
            'Active phases are observations only; unfinished cells are never certified as passed.'
        ]}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'out': str(args.out), 'sha256': hashlib.sha256(args.out.read_bytes()).hexdigest(),
                      'new_completed_samples': sum(r['actual_samples'] for r in completed),
                      'pending': pending}, indent=2))


if __name__ == '__main__':
    main()

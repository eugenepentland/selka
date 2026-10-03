#!/usr/bin/env python3
"""Close a completed diagnostic screen with immutable full input/row evidence."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    work, archive = args.work.resolve(), args.archive.resolve()
    repo = Path(__file__).resolve().parents[2]
    guards = json.loads((work / 'guards.json').read_text())
    for path, digest in guards.items():
        assert sha(Path(path)) == digest, path
    smoke = json.loads((work / 'smoke.json').read_text())
    counters = json.loads((work / 'instruction-screen.json').read_text())
    analysis = json.loads((work / 'instruction-analysis.json').read_text())
    assert smoke['verified_after'] and len(smoke['samples']) == 156 and smoke['rounds'] == 1
    assert len({(x['case'], x['arm'], x['round']) for x in smoke['samples']}) == 156
    assert all(x['status'] == 0 for x in smoke['samples'])
    for case in smoke['cases']:
        samples = [x for x in smoke['samples'] if x['case'] == case['id']]
        assert len(samples) == 6
        assert all(x['stdout_sha256'] == sha(Path(case['expected'])) for x in samples)
        assert all(x['collector_stats'] == samples[0]['collector_stats'] for x in samples)
    assert counters['verified_after'] and len(counters['samples']) == 104
    assert analysis['screen_only'] and analysis['coverage_verified']
    assert analysis['receipt_sha256'] == sha(work / 'instruction-screen.json')
    assert analysis['stable_guards_after'] == len(guards)
    archive.mkdir(parents=True, exist_ok=False)
    inputs = dict(guards)
    for p in sorted(work.rglob('*')):
        if p.is_file() and not str(p.relative_to(work)).startswith('cache-'):
            inputs[str(p)] = sha(p)
    inputs[str(Path(__file__).resolve())] = sha(Path(__file__).resolve())
    payloads = {}
    for original, digest in inputs.items():
        p = Path(original)
        assert sha(p) == digest, p
        target = archive / 'objects' / digest
        if not target.exists():
            target.parent.mkdir(exist_ok=True)
            shutil.copy2(p, target)
        assert sha(target) == digest
        payloads[original] = {'sha256': digest, 'object': 'objects/' + digest,
                              'bytes': p.stat().st_size}
    manifest = {'root_commit_at_capture': subprocess.check_output(
                    ['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip(),
                'payloads': payloads, 'all_rehashed_after_copy': True,
                'preserves_original_absolute_paths_as_identity_keys': True}
    (archive / 'MANIFEST.json').write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
    for original, item in payloads.items():
        assert sha(Path(original)) == item['sha256']
        assert sha(archive / item['object']) == item['sha256']
    receipt = {'archive': str(archive), 'manifest_sha256': sha(archive / 'MANIFEST.json'),
               'original_files': len(payloads), 'unique_objects': len({x['object'] for x in payloads.values()}),
               'stable_original_guards': len(guards), 'all_rehashed_after_copy': True,
               'smoke_observations': 156, 'diagnostic_counter_cells': 104,
               'PMU_running_percentage_checks': 416,
               'measurement_manifest_sha256': sha(work / 'binaries.json'),
               'counter_receipt_sha256': sha(work / 'instruction-screen.json'),
               'instruction_analysis_sha256': sha(work / 'instruction-analysis.json'),
               'no_full_wall_or_counter_matrix': True, 'selected': False,
               'comparisons': analysis['comparisons']}
    args.out.write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({k: receipt[k] for k in ('archive', 'manifest_sha256', 'original_files', 'unique_objects')}))


if __name__ == '__main__':
    main()

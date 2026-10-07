#!/usr/bin/env python3
"""Archive final S4-V performance evidence without changing measured files."""
import hashlib
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = Path(__file__).resolve().parent
CACHE = ROOT / '.mylang-cache/s4-v/final-all46-v2'


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    measured = json.loads((EVIDENCE / 'final-all46-v2.json').read_text())
    frozen = json.loads((EVIDENCE / 'final-frozen-source-v3.json').read_text())
    assert measured['valid'] and measured['all_within_both_limits']
    assert len(measured['rows']) == 46
    for relative, expected in frozen['frozen_inputs'].items():
        assert sha256(ROOT / relative) == expected, relative
    for name, tool in frozen['tools'].items():
        assert sha256(Path(tool['path'])) == tool['sha256'], name
    archive = EVIDENCE / 'final-performance-artifacts-v2'
    archive.mkdir()
    files = {}
    for category in ('build-logs', 'llvm'):
        for original in sorted((CACHE / category).rglob('*')):
            if not original.is_file():
                continue
            relative = original.relative_to(CACHE)
            target = archive / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(original, target)
            files[str(relative)] = {'sha256': sha256(original), 'bytes': original.stat().st_size}
    binaries = {}
    rows = {}
    for row, result in measured['rows'].items():
        rows[row] = {}
        for size, sample in result['sizes'].items():
            assert sample['within_both_limits'], (row, size)
            rows[row][size] = {key: sample[key] for key in (
                'iterations', 'checksum', 'new_over_old', 'new_over_zig',
                'new_over_rust', 'within_old_limit', 'within_zig_limit', 'within_both_limits')}
            for config, data in sample['configurations'].items():
                for run in data['runs']:
                    assert run['status'] == 0 and run['checksum'] == sample['checksum'], (row, size, config)
                    candidates = [Path(arg) for arg in run['command'] if Path(arg).is_absolute() and Path(arg).is_file()]
                    assert len(candidates) == 1 and candidates[0].is_file(), run['command']
                    binary = candidates[0]
                    if str(binary) not in binaries:
                        binaries[str(binary)] = {'sha256': sha256(binary), 'bytes': binary.stat().st_size}
    summary = {
        'qualified': True,
        'scope': '46-row performance gate; Release trap-frame provenance remains an integration blocker',
        'implementation_source': '3c86c3122fdcc186aa777b52bbcf7f25b03c172f',
        'core_sha256': frozen['tools']['mylang-core']['sha256'],
        'tools': frozen['tools'],
        'cpu': measured['cpu'], 'rounds': measured['rounds'],
        'row_count': len(rows), 'rows': rows,
        'max_new_over_old': max(sample['new_over_old'] for row in rows.values() for sample in row.values()),
        'max_new_over_zig': max(sample['new_over_zig'] for row in rows.values() for sample in row.values()),
        'misses': measured['speed_gate_misses'],
        'all_within_both_limits': measured['all_within_both_limits'],
        'binaries': binaries,
        'artifact_manifest': str((archive / 'manifest.json').relative_to(EVIDENCE)),
    }
    (archive / 'manifest.json').write_text(json.dumps(files, indent=2) + '\n')
    target = EVIDENCE / 'performance_summary_v2.json'
    with target.open('x') as output:
        output.write(json.dumps(summary, indent=2) + '\n')
    print(json.dumps({key: summary[key] for key in ('row_count', 'max_new_over_old', 'max_new_over_zig', 'misses')}))
    print(f'archived {len(files)} source/log files and {len(binaries)} binary hashes')


if __name__ == '__main__':
    main()

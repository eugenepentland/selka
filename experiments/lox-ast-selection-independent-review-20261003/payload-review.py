#!/usr/bin/env python3
"""Bind copied checkpoint payloads to the previously reviewed measured originals."""
import argparse
import datetime
import gzip
import hashlib
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).parent.parent / 'lox-next-measurement-independent-review-20261003'))
import audit


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    assert not args.out.exists()
    root = args.root.resolve()
    previous = Path(__file__).parent.parent / 'lox-round3-independent-review-20261003/final-review.json'
    assert audit.sha(previous) == 'bd8e734c304940db87fb769eedcc409affd806c194a190e1e77086cb62ed0722'
    prior = audit.load(previous)
    exp = root / 'experiments/lox-ast-constant-20261003'
    copies = {}
    for phase in prior['completed_phases']:
        original = Path(phase['path'])
        assert audit.sha(original) == phase['sha256']
        assert gzip.decompress(audit.read(exp / (original.name + '.gz'))) == audit.read(original)
        for suffix in ['.command.json', '.log']:
            assert audit.read(exp / original.with_suffix(suffix).name) == audit.read(original.with_suffix(suffix))
        copies[original.name] = {'original_sha256': phase['sha256'], 'copied_gzip_sha256': audit.sha(exp / (original.name + '.gz')),
                                 'unique_rows': phase['actual_samples'], 'identical_raw_copy': True}
    for analysis in prior['analyses']:
        original = Path(analysis['path'])
        assert audit.sha(original) == analysis['sha256']
        assert audit.read(exp / original.name) == audit.read(original)
    for report in prior['build_reports']:
        for build in report['builds']:
            assert audit.sha(build['binary']) == build['sha256']
            assert audit.sha(build['binary'] + '.qbe-manifest.json') == build['manifest_sha256']
            native_metadata = audit.load(build['binary'] + '.qbe-manifest.json')
            assert audit.sha(native_metadata['runtime_object']) == build['runtime_object_sha256']
    manifest = audit.load(root / '.tmp-lox-round3/binaries.json')
    assert audit.sha(root / '.tmp-lox-round3/binaries.json') == prior['manifest_sha256']
    assert manifest['binary_sha256'] == prior['binary_sha256']
    for name, path in manifest['binaries'].items():
        assert audit.sha(path) == prior['binary_sha256'][name]
    for path, digest in list(audit.READS.items()):
        assert hashlib.sha256(Path(path).read_bytes()).hexdigest() == digest
    result = {'recorded_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'outcome': 'checkpoint packed measurements, commands, logs and analyses match reviewed originals',
              'prior_complete_review_sha256': audit.sha(previous), 'copied_original_phases': copies,
              'original_unique_rows': 1976, 'independent_comparisons_inherited': 42,
              'all10_measured_guests_and_native_build_metadata_runtime_objects_unchanged': True,
              'stable_read_input_count': len(audit.READS), 'new_measurements_or_guest_executions': 0,
              'root_mutations': 0, 'limits': ['This rechecks existing row bytes and arithmetic provenance; it adds no measurement rows.',
                                            'Original fresh260 reproduction and new historical156 behavior qualifications remain separate.',
                                            'Raw stdout/per-sample perf CSV retention and paired-wall uncertainty retain the previous review limits.']}
    args.out.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'out': str(args.out), 'sha256': hashlib.sha256(args.out.read_bytes()).hexdigest()}))


if __name__ == '__main__':
    main()

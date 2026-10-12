#!/usr/bin/env python3
"""Freeze C0 originals and report per-source burden without hiding refusals."""
from pathlib import Path
import difflib
import gzip
import hashlib
import json
import re
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
C0 = 'fbfcaa7a923186a8e773c3760f81c10aa345a432'


def main():
    originals = json.loads((HERE / 'originals.json').read_text())
    current = {}
    for directory in ['after-certain-copies', 'after-manual-copies', 'after-manual-second',
                      'after-manual-third', 'after-live-iteration', 'after-final-copies', 'after-site-binding', 'after-support3', 'after-support4-copies', 'after-support4-final', 'after-support5', 'after-support5-copies', 'after-support5-writeback', 'after-support5-writeback-final', 'after-support5-writeback-evaluation', 'after-support5-writeback-publication']:
        for path in sorted((HERE / directory).glob('batch-*.json')):
            report = json.loads(path.read_text())
            for row in report['cases']:
                current[row['source']] = dict(row, report=str(path.relative_to(ROOT)),
                                             compiler_sha256=report['compiler_sha256'])
    rows = []
    archive = HERE / 'original-sources'
    archive.mkdir(exist_ok=True)
    for item in originals:
        source = item['source']
        if source == 'tests/lang/frontend_type_helpers.my':
            continue
        original = subprocess.check_output(['git', 'show', C0 + ':' + source], cwd=ROOT)
        assert hashlib.sha256(original).hexdigest() == item['original_sha256'], source
        old, new = original.decode(), (ROOT / source).read_text()
        # Assertions and test registrations are invariants of source migration.
        assertions = r'(?m)^\s*assert .*$'
        exports = r'(?m)^public func (\w+)'
        assert re.findall(assertions, old) == re.findall(assertions, new), source
        assert re.findall(exports, old) == re.findall(exports, new), source
        compressed = archive / (source.replace('/', '__') + '.gz')
        compressed.write_bytes(gzip.compress(original, mtime=0))
        before, after = old.splitlines(), new.splitlines()
        added = removed = 0
        for tag, a, b, c, d in difflib.SequenceMatcher(a=before, b=after, autojunk=False).get_opcodes():
            if tag != 'equal':
                removed += b - a
                added += d - c
        result = current.get(source)
        digest = hashlib.sha256(new.encode()).hexdigest()
        rows.append(dict(source=source, original_sha256=item['original_sha256'],
                         original_archive=str(compressed.relative_to(ROOT)), migrated_sha256=digest,
                         changed=old != new, removed_lines=removed, added_lines=added,
                         original_copy_sites=old.count('.copy()'), migrated_copy_sites=new.count('.copy()'),
                         public_test_functions=len(re.findall(exports, old)),
                         assertions_preserved=True, public_functions_preserved=True,
                         source_check=result,
                         source_check_matches_current=result is not None and result['source_sha256'] == digest))
    passed = sum(row['source_check_matches_current'] and row['source_check']['status'] == 0 for row in rows)
    report = dict(base=C0, reserved_sources=len(rows), source_admitted_current=passed,
                  not_yet_admitted_or_recheck_required=len(rows) - passed,
                  changed_sources=sum(row['changed'] for row in rows),
                  added_copy_sites=sum(row['migrated_copy_sites'] - row['original_copy_sites'] for row in rows),
                  added_lines=sum(row['added_lines'] for row in rows), removed_lines=sum(row['removed_lines'] for row in rows),
                  scope='Exploratory source admission only. Native five-mode execution and cleanup remain required on frozen integrated compiler.',
                  sources=rows)
    (HERE / 'ledger.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({key: value for key, value in report.items() if key != 'sources'}, indent=2))


if __name__ == '__main__':
    main()

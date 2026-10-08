#!/usr/bin/env python3
"""Report all integrated guest runtime-image differences against explicit controls."""
import argparse
from datetime import datetime, timezone
import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
HELPER = ROOT / 'experiments/runtime-goal110-bounded-rem-llvm-20261004/compare-executables.py'
spec = importlib.util.spec_from_file_location('runtime_images', HELPER)
images = importlib.util.module_from_spec(spec)
spec.loader.exec_module(images)


def loads(image):
    return [dict(metadata=segment, sha256=images.digest(image[0][segment[2]:segment[2] + segment[5]]))
            for segment in image[3] if segment[0] == 1]


def differences(before_path, after_path):
    before, after = images.elf(before_path), images.elf(after_path)
    names = set(before[2]) | set(after[2])
    sections = []
    for name in sorted(names):
        left, right = before[2].get(name), after[2].get(name)
        if left != right:
            sections.append(dict(name=name, before=left, after=right))
    header_only = []
    mapped_equal = before[3] == after[3]
    if mapped_equal:
        for segment in before[3]:
            if segment[0] != 1:
                continue
            offset, size = segment[2], segment[5]
            left, right = before[0][offset:offset + size], after[0][offset:offset + size]
            changed = [offset + i for i, pair in enumerate(zip(left, right)) if pair[0] != pair[1]]
            permitted = set(changed) <= set(range(40, 48)) and (not changed or (offset == 0 and not segment[1] & 1))
            mapped_equal = mapped_equal and len(left) == len(right) and permitted
            if permitted:
                header_only.extend(changed)
    entry_equal = before[1][4] == after[1][4]
    return dict(before_path=str(before_path), after_path=str(after_path),
                before_sha256=images.digest(before[0]), after_sha256=images.digest(after[0]),
                runtime_image_equal=not sections and entry_equal and mapped_equal,
                entry_before=before[1][4], entry_after=after[1][4],
                changed_allocated_sections=sections,
                program_headers_before=before[3], program_headers_after=after[3],
                loads_before=loads(before), loads_after=loads(after),
                permitted_mapped_header_differences=header_only)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate-manifest', type=Path, required=True)
    parser.add_argument('--index-manifest', type=Path, required=True)
    parser.add_argument('--expected-index-manifest-sha256', required=True)
    parser.add_argument('--publication-manifest', type=Path, required=True)
    parser.add_argument('--expected-publication-manifest-sha256', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    candidate, candidate_binding = images.manifest(args.candidate_manifest)
    index, index_binding = images.manifest(args.index_manifest)
    publication, publication_binding = images.manifest(args.publication_manifest)
    assert candidate_binding['source_revision'] == '1a3980631e79bc65f048acd063d7250800f01901'
    assert index_binding['source_revision'] == '14ffa2c0f385a11e5216bbdec5bdff429f9f981b'
    assert publication_binding['source_revision'] == '64fb7e62732db9cea46414248fd59ba362e31b56'
    assert index_binding['sha256'] == args.expected_index_manifest_sha256
    assert publication_binding['sha256'] == args.expected_publication_manifest_sha256
    rows = []
    for group in images.GROUPS:
        for backend in ('llvm', 'qbe'):
            control = index if group in ('compute', 'legacy') else publication
            name = group + '/my-' + backend
            row = differences(Path(control['identity']['binary_paths'][name]),
                              Path(candidate['identity']['binary_paths'][name]))
            assert row['before_sha256'] == control['binary_hashes'][name]
            assert row['after_sha256'] == candidate['binary_hashes'][name]
            row.update(group=group, backend=backend, expected_equal=not (group == 'collections' and backend == 'llvm'))
            rows.append(row)
    result = dict(status='comparison_complete', reviewed_utc=datetime.now(timezone.utc).isoformat(),
                  candidate=candidate_binding, index_control=index_binding, publication_control=publication_binding,
                  script_sha256=images.digest(Path(__file__).read_bytes()), helper_sha256=images.digest(HELPER.read_bytes()),
                  rows=rows, equal_images=sum(row['runtime_image_equal'] for row in rows),
                  limitations=['Differences are reported, including unexpected ones; no assumed composition equivalence.',
                               'Only nonexecutable e_shoff bytes40..47 are excluded from mapped runtime comparison.',
                               'No timing or normal goal confirmation.'])
    with args.output.open('x') as output:
        output.write(json.dumps(result, indent=2) + '\n')
    for row in rows:
        print(row['group'], row['backend'], 'equal' if row['runtime_image_equal'] else 'DIFFERENT',
              'sections:', ','.join(section['name'] for section in row['changed_allocated_sections']))


if __name__ == '__main__':
    main()

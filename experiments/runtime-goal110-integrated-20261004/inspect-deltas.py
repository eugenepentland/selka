#!/usr/bin/env python3
"""Read-only LLVM compute/legacy attribution across isolated and composed sources."""
import argparse
import difflib
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT.parent
CONTROLS = {
    'g4': ('goal110-g4-rf-20261004', 'goal110-g4-rf', '4757812159060d11f035115d40fbf94e894bc08030e961fa7c2fdd8d955f4479'),
    '5e': ('goal110-bounded-rem-20261004', 'goal110-bounded-rem-debug', 'f146075f014c345f0b73016685188d54ca73703fba21fdc96292dfb090344bdb'),
    'df09': ('goal110-bounded-rem-llvm-20261004', 'goal110-bounded-rem-llvm-debug', 'f676f9954ae56e2d773f1939f917266781910cb89bd746628e9714207a1c9462'),
    'index': ('goal110-index-forward-rf-20261004', 'goal110-index-forward-rf', 'e02fd8476ee7b36d04e74a46287dcdbcc0fade79156f40b4e0de2d9e6674a171'),
    'integrated': ('goal110-integrated-20261004', 'goal110-integrated-debug', 'a64af04cdb495d00c49d562789fcb6341349bf3f411d7783ba7400ba4cbe92ce'),
}


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', type=Path, required=True)
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    static_path = ROOT / 'experiments/runtime-goal110-bounded-rem-20261004/static-qbe-nested.py'
    image_path = ROOT / 'experiments/runtime-goal110-bounded-rem-llvm-20261004/compare-executables.py'
    static = module('static', static_path)
    image = module('image', image_path)
    documents, bindings, binaries = {}, {}, {}
    for label, (directory, work, expected) in CONTROLS.items():
        path = BASE / directory / '.mylang-cache' / work / 'runner/manifest.json'
        assert image.digest(path.read_bytes()) == expected
        documents[label], bindings[label] = image.manifest(path)
        for group in ('compute', 'legacy'):
            key = label + '-' + group
            static.PINS.setdefault('llvm', {})[key] = documents[label]['binary_hashes'][group + '/my-llvm']
            binaries[key] = static.inspect(Path(documents[label]['identity']['binary_paths'][group + '/my-llvm']), 'llvm', key)
            (args.output_dir / (key + '.asm')).write_text(binaries[key]['assembly'])
    rows = []
    for group in ('compute', 'legacy'):
        pairs = [('g4', '5e'), ('5e', 'df09'), ('df09', 'integrated'), ('index', 'integrated')]
        if group == 'legacy':
            pairs.append(('g4', 'index'))
        for before, after in pairs:
            left, right = binaries[before + '-' + group], binaries[after + '-' + group]
            common = left['functions'].keys() & right['functions'].keys()
            changed = []
            for name in sorted(common):
                if static.signature(left['functions'][name], 2) == static.signature(right['functions'][name], 2):
                    continue
                changed.append(dict(name=name, before_address=left['symbols'][name][0], after_address=right['symbols'][name][0],
                                    before_bytes=left['symbols'][name][1], after_bytes=right['symbols'][name][1],
                                    before_instructions=len(left['functions'][name]), after_instructions=len(right['functions'][name])))
                diff = difflib.unified_diff([line[2] + '\n' for line in left['functions'][name]],
                                           [line[2] + '\n' for line in right['functions'][name]], before, after)
                (args.output_dir / (group + '-' + before + '-' + after + '-' + name + '.diff')).write_text(''.join(diff))
            row = dict(group=group, before=before, after=after, whole_text_before=left['whole_text_bytes'],
                       whole_text_after=right['whole_text_bytes'], named_functions=len(common), changed_functions=changed,
                       added=sorted(right['functions'].keys() - left['functions'].keys()),
                       removed=sorted(left['functions'].keys() - right['functions'].keys()))
            try:
                row['exact_runtime_image'] = image.compare(Path(left['path']), Path(right['path']))
                row['runtime_equal'] = True
            except AssertionError as error:
                row.update(runtime_equal=False, first_runtime_difference=str(error))
            rows.append(row)
            print(group, before, after, 'runtime_equal', row['runtime_equal'], 'changed_functions', len(changed))
    result = dict(source_revision=documents['integrated']['identity']['source_revision'], manifest_bindings=bindings,
                  helper_sha256={str(path): image.digest(path.read_bytes()) for path in (Path(__file__), static_path, image_path)},
                  binaries={key: dict(path=value['path'], sha256=value['sha256'],
                                     assembly_sha256=image.digest(value['assembly'].encode())) for key, value in binaries.items()},
                  comparisons=rows, limitations=['Read-only nm/objdump/readelf; no objcopy or ELF mutation.',
                  'Function normalization preserves registers and stack slots, normalizing symbol addresses only.',
                  'Runtime identity checks all allocated section bytes/metadata, program headers and mapped LOAD bytes/placement;',
                  'only nonexecutable ELF e_shoff bytes40..47 may differ.',
                  'Main-only source changes can alter timed-body allocation and placement; timing controls remain necessary.'])
    (args.output_dir / 'function-deltas.json').write_text(json.dumps(result, indent=2) + '\n')


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Write exact artifacts, producer recipes and qualified native producer metadata.

Record version 3 writes an artifact with a producer recipe as
`artifacts[label] = {"path": ..., "producer": {...}}` (the compile-time input
recipes, optimize mode, Zig version and test runner `build_verification.zig`
exports) and keeps the reviewed closure metadata in `producers` as version 2
did (docs/tooling/development-loop.md, "Prepared artifact inventory").
"""
import json
import os
from pathlib import Path
import sys
import tempfile

from verification_producers import producer_metadata


PRODUCER_FIELDS = {'recipes', 'optimize', 'zig_version', 'test_runner'}


def read_producers(path):
    """Load `[{label, producer}]` from build_verification.zig as a label map."""
    entries = json.loads(path.read_text())
    if not isinstance(entries, list):
        raise SystemExit('producer recipes must be a list')
    result = {}
    for entry in entries:
        producer = entry.get('producer') if isinstance(entry, dict) else None
        label = entry.get('label') if isinstance(entry, dict) else None
        runner = producer.get('test_runner') if isinstance(producer, dict) else None
        if (not isinstance(label, str) or not label or label in result
                or not isinstance(producer, dict) or set(producer) != PRODUCER_FIELDS
                or not isinstance(producer['recipes'], list) or not producer['recipes']
                or not all(isinstance(recipe, str) and recipe for recipe in producer['recipes'])
                or len(set(producer['recipes'])) != len(producer['recipes'])
                or any(recipe.startswith('/') for recipe in producer['recipes'])
                or not isinstance(producer['optimize'], str) or not producer['optimize']
                or not isinstance(producer['zig_version'], str) or not producer['zig_version']
                or runner in (None, '', [], {})):
            raise SystemExit('malformed producer recipe: ' + repr(label))
        result[label] = producer
    return result


def main(argv):
    if not argv:
        raise SystemExit('usage: verification_artifacts.py OUTPUT [--producers FILE] [--qualify LABEL MODE] LABEL PATH ...')
    output, qualifiers, pairs, recipes = argv[0], {}, [], None
    index = 1
    while index < len(argv):
        if argv[index] == '--producers':
            if index + 1 >= len(argv) or recipes is not None:
                raise SystemExit('--producers takes one FILE, once')
            recipes = read_producers(Path(argv[index + 1]))
            index += 2
        elif argv[index] == '--qualify':
            if index + 2 >= len(argv) or argv[index + 1] in qualifiers:
                raise SystemExit('producer qualifiers require unique LABEL MODE pairs')
            qualifiers[argv[index + 1]] = argv[index + 2]
            index += 3
        else:
            if index + 1 >= len(argv):
                raise SystemExit('native artifacts require LABEL PATH pairs')
            pairs.append(argv[index:index + 2])
            index += 2
    if not pairs:
        raise SystemExit('at least one native artifact is required')
    artifacts, producers = {}, {}
    for label, raw in pairs:
        if not label or label in artifacts:
            raise SystemExit('native artifact labels must be nonempty and unique')
        path = Path(raw).resolve(strict=True)
        if not path.is_file():
            raise SystemExit(f'native artifact is not a regular file: {path}')
        artifacts[label] = str(path)
        if label in qualifiers:
            metadata = producer_metadata(Path.cwd(), label, path, qualifiers[label])
            if metadata is not None:
                producers[label] = metadata
    if qualifiers.keys() - artifacts.keys():
        raise SystemExit('producer qualifier names an unavailable native artifact')
    if recipes is not None and recipes.keys() != artifacts.keys():
        raise SystemExit('producer recipes must name exactly the native artifacts')
    for label, producer in (recipes or {}).items():
        artifacts[label] = {'path': artifacts[label], 'producer': producer}
    record = {'version': 3, 'artifacts': artifacts, 'producers': producers}
    destination = Path(output)
    destination.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.artifacts-', dir=destination.parent)
    try:
        with os.fdopen(fd, 'w') as handle:
            handle.write(json.dumps(record, indent=2) + '\n')
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, destination)
    finally:
        Path(temporary).unlink(missing_ok=True)


if __name__ == '__main__':
    main(sys.argv[1:])

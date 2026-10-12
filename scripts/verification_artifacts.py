#!/usr/bin/env python3
"""Write exact artifacts and explicitly qualified native producer metadata."""
import json
import os
from pathlib import Path
import sys
import tempfile

from verification_producers import producer_metadata


def main(argv):
    if not argv:
        raise SystemExit('usage: verification_artifacts.py OUTPUT [--qualify LABEL MODE] LABEL PATH ...')
    output, qualifiers, pairs = argv[0], {}, []
    index = 1
    while index < len(argv):
        if argv[index] == '--qualify':
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
    record = {'version': 2, 'artifacts': artifacts, 'producers': producers}
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

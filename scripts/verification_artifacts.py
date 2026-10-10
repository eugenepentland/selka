#!/usr/bin/env python3
"""Write exact native artifact locations for explicit verification preparation."""
import json
from pathlib import Path
import sys


def main(argv):
    if len(argv) < 3 or len(argv) % 2 != 1:
        raise SystemExit('usage: verification_artifacts.py OUTPUT LABEL PATH [LABEL PATH ...]')
    artifacts = {}
    for index in range(1, len(argv), 2):
        label, raw = argv[index:index + 2]
        if not label or label in artifacts:
            raise SystemExit('native artifact labels must be nonempty and unique')
        path = Path(raw).resolve(strict=True)
        if not path.is_file():
            raise SystemExit(f'native artifact is not a regular file: {path}')
        artifacts[label] = str(path)
    Path(argv[0]).write_text(json.dumps({'version': 1, 'artifacts': artifacts}, indent=2) + '\n')


if __name__ == '__main__':
    main(sys.argv[1:])

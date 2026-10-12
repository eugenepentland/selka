#!/usr/bin/env python3
"""Show why one-call stat memo cannot replace metadata-only change detection."""
from contextlib import ExitStack
import json
from pathlib import Path
import sys
import tempfile
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'scripts'))
from verification_snapshot import Snapshot


def main():
    with tempfile.TemporaryDirectory(prefix='rejected-memo-') as scratch:
        root = Path(scratch)
        path = root / 'input'
        path.write_bytes(b'original')
        with Snapshot(root, ['input']) as first, Snapshot(root, ['input']) as second:
            original = Path.lstat
            cache = {}
            def memoized(candidate, *arguments, **keywords):
                if candidate not in cache:
                    cache[candidate] = original(candidate, *arguments, **keywords)
                return cache[candidate]
            # Model a host whose mutation has metadata but no local watcher event.
            with ExitStack() as stack:
                stack.enter_context(patch.object(first._watcher, 'drain', side_effect=lambda: not first._watcher.dirty))
                stack.enter_context(patch.object(second._watcher, 'drain', side_effect=lambda: not second._watcher.dirty))
                with patch.object(Path, 'lstat', memoized):
                    first_valid = first.unchanged()
                    path.write_bytes(b'metadata-only mutation')
                    unsafe_second_valid = second.unchanged()
                conservative_second_valid = second.unchanged()
            result = {'first_valid': first_valid, 'unsafe_memo_second_valid': unsafe_second_valid,
                      'fresh_metadata_second_valid': conservative_second_valid,
                      'accepted': False, 'production_memo_present': False,
                      'scope': 'mocked absent watcher events; persistent metadata change',
                      'reason': 'Independent watch drains cannot certify metadata-only host changes.'}
            print(json.dumps(result, indent=2, sort_keys=True))
            return 0 if first_valid and unsafe_second_valid and not conservative_second_valid else 1


if __name__ == '__main__':
    raise SystemExit(main())

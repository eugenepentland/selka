#!/usr/bin/env python3
"""Replay the dictionary publication sanitizer receipt against its final source."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
TREE = ROOT.parent / 'goal110-dict-read-20261004'
CACHE = TREE / '.mylang-cache/goal110-dict-probe'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    receipt_path = CACHE / 'native-proof/receipt.json'
    receipt = json.loads(receipt_path.read_text())
    binding_path = CACHE / 'final-native-source-binding.json'
    binding = json.loads(binding_path.read_text())
    assert receipt['status'] == 'pass' and not receipt['timing']
    assert sha(receipt_path) == binding['native_receipt']['sha256']
    for item in (receipt['compiler'], receipt['driver']):
        assert sha(item['path']) == item['sha256']
    reconstructed = {row['path']: row for row in binding['rows']}
    checked = 0
    for name, expected in receipt['sources'].items():
        if name == 'SPEC.md':
            continue  # Reviewed separately as a documentation-only change.
        data = (TREE / name).read_bytes()
        if name in reconstructed:
            assert sha(TREE / name) == reconstructed[name]['final_sha256']
            data = data.replace(b'PY-DICT-4', b'DICT-PROBE-FOUND-1')
            assert expected == reconstructed[name]['tested_sha256']
        assert hashlib.sha256(data).hexdigest() == expected, name
        checked += 1
    expected_stdout = {
        'native_rc_stats': '',
        'native_rc_collections': 'native RC collections: 53 passed\n',
        'native_text_dictionary': 'native text and dictionary tests passed\n',
        'native_dictionary_probe': 'native dictionary probe state tests passed\n',
    }
    builds, runs = {}, {}
    for invocation in receipt['invocations']:
        command = invocation['command']
        assert invocation['exit_status'] == 0
        assert sha(invocation['executable']) == invocation['sha256_before'] == invocation['sha256_after']
        if command[0] == receipt['compiler']['path']:
            assert all(flag in command for flag in ('-O2', '-fsanitize=undefined,address', '-Wall', '-Wextra', '-Werror'))
            assert invocation['stdout'] == invocation['stderr'] == ''
            assert command[-2] == '-o'
            builds[Path(command[-1]).name] = command[-1]
        else:
            assert len(command) == 1
            name = Path(command[0]).name
            assert name not in runs and builds[name] == command[0]
            assert invocation['stdout'] == expected_stdout[name]
            if name == 'native_rc_stats':
                prefix, payload = invocation['stderr'].split(' ', 1)
                assert prefix == 'MYLANG_RC_COUNTS'
                assert json.loads(payload) == dict(version=1, runtime='rc-v5-counting', saturated=False,
                    owner_acquire=1, owner_release=2, hold_acquire=1, hold_release=1,
                    owner_limit=0, hold_limit=0, heap_allocate=1, arena_allocate=0,
                    retire=1, clone_shell=0, unique_check=2)
            else:
                assert invocation['stderr'] == ''
            runs[name] = invocation['sha256_after']
    assert set(builds) == set(runs) == set(expected_stdout)
    assert len(receipt['invocations']) == 8
    result = dict(status='pass', reviewed_utc=datetime.now(timezone.utc).isoformat(),
                  source_revision='64fb7e62732db9cea46414248fd59ba362e31b56',
                  tested_source_bindings=checked, comment_only_reconstructions=len(reconstructed),
                  sanitizer_builds=4, exact_process_outcomes=4, binaries=runs,
                  receipt_sha256=sha(receipt_path), source_binding_sha256=sha(binding_path),
                  script_sha256=sha(__file__),
                  limitations=['Saved process replay; no new native executions.',
                               'SPEC documentation change reviewed separately; C comment tags reconstructed exactly.',
                               'No guest timing or goal confirmation.'])
    with Path(sys.argv[1]).open('x') as target:
        target.write(json.dumps(result, indent=2) + '\n')
    print(f'PASS four ASan/UBSan suites, {checked} source bindings and two comment-only reconstructions')


if __name__ == '__main__':
    main()

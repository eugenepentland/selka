#!/usr/bin/env python3
"""Read-only validation after coordinator-admitted two-case diagnostics."""
import hashlib
import json
from pathlib import Path
import sys


def main():
    spec = json.loads(Path(sys.argv[1]).read_text())
    receipt = json.loads(Path(sys.argv[2]).read_text())
    assert receipt['spec'] == spec
    assert receipt['warmups'] == 2 and receipt['rounds'] == 9
    assert receipt['relative_timeout_policy']['factor'] == 3
    expected = spec['expected_output']
    journal = Path(sys.argv[2] + '.progress.jsonl')
    rows = [json.loads(line) for line in journal.read_text().splitlines()]
    for row in [r for r in rows if 'output' in r]:
        assert row['output']['stdout_sha256'] == expected['stdout_sha256']
        assert row['output']['golden_tree'] == expected['golden_tree']
        assert hashlib.sha256(row['stderr'].encode()).hexdigest() == expected['stderr_sha256']
    for arm, status in receipt['arm_status'].items():
        if status['status'] == 'ok':
            assert sum(r['arm'] == arm for r in receipt['wall_samples']) == 9
    print(json.dumps({'status': receipt['arm_status'], 'output_oracles_checked': True,
                      'scope': 'two-case diagnostic; no full EDA parity claim'}, indent=2))


if __name__ == '__main__':
    main()

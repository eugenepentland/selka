#!/usr/bin/env python3
"""Keep compact gate receipts while scratch retains the complete logs."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase')
    parser.add_argument('log', type=Path)
    parser.add_argument('status', type=int)
    parser.add_argument('command')
    args = parser.parse_args()
    raw = args.log.read_bytes()
    text = raw.decode(errors='replace')
    summaries = re.findall(r'^Build Summary:.*$', text, re.M)
    results = [json.loads(row) for row in re.findall(r'guardian/test: RESULT (.*)', text)]
    receipt = {'phase': args.phase, 'command': args.command,
               'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
               'status': args.status, 'summary': summaries[-1] if summaries else None,
               'test_verdicts': {key: sum(row.get(key, 0) for row in results) for key in ('passed', 'failed', 'skipped')},
               'failures': re.findall(r"^error: '([^']+)' failed:", text, re.M),
               'log_sha256': hashlib.sha256(raw).hexdigest(), 'log_bytes': len(raw)}
    output = Path(__file__).with_name('gates.json')
    records = json.loads(output.read_text()) if output.exists() else []
    records.append(receipt)
    output.write_text(json.dumps(records, indent=2) + '\n')
    print(receipt['phase'], receipt['status'], receipt['summary'])


if __name__ == '__main__':
    main()

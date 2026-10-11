"""Compare two immutable qualified B3 deployments under one timing reservation."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

root = Path('/home/epentland/.codex/worktrees/selka-selfhost-pilots/mylang')
work = Path('/home/epentland/.cache/mylang-tmp/selka-selfhost-pilots')
experiment = Path('/home/epentland/.codex/worktrees/selka-compiler-probes/mylang/.tmp/b3-release-experiment')
report = json.loads((experiment / 'full-qualification.json').read_text())
assert report['workflows'] == 234 and report['comparisons'] == 468
assert report['failed'] == report['skipped'] == 0
results = {}
for label, prefix in [('standard', work / 'body-list-release'), ('release-producer', experiment / 'candidate-release')]:
    output = work / 'performance-ratio' / ('b3-' + label + '.json')
    command = [sys.executable, str(root / 'selfhost/tests/measure_performance_ratio.py'),
               '--isolated', '--baseline-prefix', str(work / 'body-managed-release'),
               '--candidate-prefix', str(prefix), '--candidate-mode', 'BODY_CHECK=component',
               '--candidate-body-schema', '3', '--zig',
               '/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig',
               '--output', str(output)]
    if output.exists():
        raise RuntimeError('refusing to overwrite an earlier completed measurement')
    result = subprocess.run(command, cwd=root, pass_fds=(30,))
    if not output.is_file():
        raise RuntimeError(f'{label}: measurement did not produce complete evidence, status {result.returncode}')
    evidence = json.loads(output.read_text())
    assert len(evidence['verdict']['rows']) == 18
    assert result.returncode == (0 if evidence['verdict']['passed'] else 1)
    results[label] = {'command': command, 'exit_status': result.returncode,
                      'report': str(output), 'sha256': hashlib.sha256(output.read_bytes()).hexdigest(),
                      'verdict': evidence['verdict']}
receipt = work / 'performance-ratio' / 'b3-sweep.json'
receipt.write_text(json.dumps(results, indent=2) + '\n')
print('Both complete strict timing reports retained; failed budget rows remain failures.', flush=True)
sys.exit(0 if all(value['verdict']['passed'] for value in results.values()) else 1)

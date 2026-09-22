#!/usr/bin/env python3
"""Reject an exhausted native memory budget under both allocation policies."""
import json
import subprocess
from run import ARMS, BASE, DOCS, OUT, ROOT, WORK, environment, sha

def main():
    evidence = {}
    for name in ('gc-o3', 'arena-o3'):
        output, issue = WORK / f'{name}-small-budget.svg', WORK / f'{name}-small-budget.issue'
        output.write_bytes(b'')
        issue.write_bytes(b'')
        env = environment()
        env.update(MYLANG_MEMORY_LIMIT='4096',
                   MYLANG_SCHEMATIC_DECLARED='io::circuit_input,io::pinout_input,io::interface_input,io::length,io::byte,io::put,io::issue',
                   MYLANG_SCHEMATIC_OUTPUT=str(output), MYLANG_SCHEMATIC_ISSUE=str(issue))
        env.update({f'MYLANG_SCHEMATIC_INPUT_{i}': str(BASE / 'projects/fixture' / path)
                    for i, path in enumerate(DOCS)})
        result = subprocess.run([str(ARMS[name]), '--print-result'], cwd=ROOT, env=env,
                                capture_output=True, text=True, timeout=30)
        assert result.returncode != 0 and 'R_MEMORY_BUDGET' in result.stderr, result
        assert result.stdout == '' and output.read_bytes() == b'' and issue.read_bytes() == b''
        evidence[name] = {'limit_bytes': 4096, 'binary_sha256': sha(ARMS[name]),
                          'exit_code': result.returncode, 'stdout': result.stdout,
                          'stderr': result.stderr, 'svg_bytes': 0}
    (OUT / 'memory-budget-qualification.json').write_text(json.dumps(evidence, indent=2) + '\n')

if __name__ == '__main__':
    main()

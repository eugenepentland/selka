#!/usr/bin/env python3
"""Run one instrumented arm on the fixture and print its host-call count.

usage: run_count.py <binary> <declared-file>
"""
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / 'schematic-parity-gap-20260922/scripts'))
import bench_svg  # noqa: E402


def main() -> None:
    binary, declared = Path(sys.argv[1]), Path(sys.argv[2]).read_text().strip()
    project = bench_svg.BASE / 'projects/fixture'
    output, issue = bench_svg.WORK / 'count.svg', bench_svg.WORK / 'count.issue'
    output.write_bytes(b'')
    issue.write_bytes(b'')
    env = bench_svg.clean_env()
    docs = [str(project / p) for p in bench_svg.DOCS]
    env.update(MYLANG_SCHEMATIC_DECLARED=declared, MYLANG_SCHEMATIC_OUTPUT=str(output), MYLANG_SCHEMATIC_ISSUE=str(issue))
    env.update({f'MYLANG_SCHEMATIC_INPUT_{i}': p for i, p in enumerate(docs)})
    r = subprocess.run([str(binary), '--print-result'], env=env, capture_output=True, timeout=60)
    assert r.returncode == 0 and r.stdout == b'0\n' and not issue.read_bytes(), r.stderr[-400:]
    line = next(l for l in r.stderr.decode().splitlines() if l.startswith('HOSTCALLS '))
    print(f'{binary.parent.parent.name}: {line}  svg={bench_svg.sha(output.read_bytes())[:16]} bytes={output.stat().st_size}')


if __name__ == '__main__':
    main()

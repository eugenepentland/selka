#!/usr/bin/env python3
"""Qualify existing native object sharing across two separate project roots."""
import argparse
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / '.mylang-cache/cache-wave6/native-sharing'
OUT = Path(__file__).resolve().parent
COMPILER = ROOT / '.mylang-cache/cache-wave6/hash/object-mylang'
SOURCE = 'func main(out: Stream) -> int:\n    out.print(42)\n    return 0\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--relative', action='store_true')
    args = parser.parse_args()
    work = WORK.with_name('native-relative') if args.relative else WORK
    label = 'native-relative' if args.relative else 'native-sharing'
    env = dict(os.environ, MYLANG_CORE_RUNTIME_CACHE=str(work / 'shared-native-objects'))
    results = []
    for name in ('first', 'second'):
        project = work / name
        project.mkdir(parents=True, exist_ok=True)
        (project / 'main.my').write_text(SOURCE)
        (project / 'mylang.json').write_text('{"version":2}\n')
        result = subprocess.run([str(COMPILER), 'build', 'main.my' if args.relative else str(project / 'main.my'),
                                 '-o', str(project / 'program'), '--cache-dir', str(project / 'cache'),
                                 '--report'], env=env, cwd=project if args.relative else ROOT,
                                capture_output=True, text=True)
        (OUT / (label + '-' + name + '.log')).write_text(result.stdout + result.stderr)
        assert result.returncode == 0, result.stderr
        report = next(json.loads(line) for line in (result.stdout + result.stderr).splitlines()
                      if line.startswith('{') and 'cache-report-v1' in line)
        guest = subprocess.run([str(project / 'program')], capture_output=True, text=True)
        assert (guest.returncode, guest.stdout, guest.stderr) == (0, '42\n', '')
        results.append(dict(project=str(project), report=report, stdout=guest.stdout))
    (OUT / (label + '.json')).write_text(json.dumps(dict(version=1, relative_entry=args.relative, results=results), indent=2) + '\n')


if __name__ == '__main__':
    main()

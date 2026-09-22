#!/usr/bin/env python3
"""Sample a retained benchmark binary; keep perf data local and named reports here."""
import argparse
import json
import subprocess
import sys
from pathlib import Path


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--binary', required=True)
    p.add_argument('--input', required=True)
    p.add_argument('--manifest', required=True)
    p.add_argument('--output', required=True)
    p.add_argument('--data', required=True)
    p.add_argument('--render', action='store_true')
    p.add_argument('--repeat', type=int, default=40)
    p.add_argument('--cpu', type=int, default=6)
    args = p.parse_args()
    command = [str(Path(args.binary).resolve()), str(Path(args.input).resolve())]
    if args.render:
        command.append('--render')
    loop = ('import subprocess,sys; '
            'command=sys.argv[2:]; '
            '[subprocess.run(command,stdout=subprocess.DEVNULL,check=True) '
            'for _ in range(int(sys.argv[1]))]')
    subprocess.run(['taskset', '-c', str(args.cpu), 'perf', 'record', '-e',
                    'cycles:u', '-c', '100000', '-o', args.data, '--',
                    sys.executable, '-c', loop, str(args.repeat), *command], check=True)
    report = subprocess.run(['perf', 'report', '-i', args.data, '--stdio',
                             '--no-children', '--sort=dso,symbol',
                             '--percent-limit=0', '--show-total-period'],
                            check=True, capture_output=True, text=True).stdout
    manifest = json.loads(Path(args.manifest).read_text())
    for function in manifest['functions']:
        report = report.replace(function['symbol'], function['name'])
    Path(args.output).write_text(report)
    print('\n'.join(report.splitlines()[:48]))


if __name__ == '__main__':
    main()

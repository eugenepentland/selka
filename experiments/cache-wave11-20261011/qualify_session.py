#!/usr/bin/env python3
"""Run the complete gate twice through one retained developer session."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--zig', required=True)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    with (output / 'session-verification.log').open('w') as log:
        child = subprocess.Popen([sys.executable, '-B', 'scripts/cache_session.py'],
                                 cwd=root, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                 stderr=log, text=True)
        responses = []
        try:
            for name in ('cold', 'warm'):
                request = {'id': name, 'command': 'verify', 'args': ['--zig', args.zig]}
                child.stdin.write(json.dumps(request) + '\n')
                child.stdin.flush()
                line = child.stdout.readline()
                if not line:
                    raise RuntimeError('session ended without completion; inspect session-verification.log')
                response = json.loads(line)
                responses.append(response)
                print(json.dumps(response), flush=True)
                if not response['ok']:
                    raise RuntimeError('verification session request failed: ' + str(response))
                shutil.copyfile(root / '.mylang-cache/verification-v1/last-run.json',
                                output / ('verification-' + name + '.json'))
            child.stdin.write('{"id":"stop","command":"stop"}\n')
            child.stdin.flush()
            stop = json.loads(child.stdout.readline())
            if not stop['ok'] or child.wait(timeout=30) != 0:
                raise RuntimeError('session failed to close cleanly')
            warm = responses[1]['snapshot_work']
            if warm['files_hashed'] != 0 or warm['directories_enumerated'] != 0:
                raise RuntimeError('unchanged warm request unexpectedly reconstructed snapshots')
            (output / 'session-summary.json').write_text(json.dumps(
                {'passed': True, 'responses': responses, 'stop': stop}, indent=2) + '\n')
        finally:
            if child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=30)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait()
            child.stdin.close()
            child.stdout.close()


if __name__ == '__main__':
    main()

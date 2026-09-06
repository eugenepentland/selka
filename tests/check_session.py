#!/usr/bin/env python3
"""Exercise repeated checking against source/input edits in one compiler process."""
import argparse
import json
from pathlib import Path
import selectors
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True)
    compiler = str(Path(parser.parse_args().compiler).resolve())
    with tempfile.TemporaryDirectory(prefix='mylang-check-session-') as directory:
        root = Path(directory)
        entry, data = root / 'main.my', root / 'data.my'
        entry.write_text('module main;import data;fn main()->i64{return data::value();}')
        valid = 'module data;export value;fn value()->i64{return 7;}'
        data.write_text(valid)
        with tempfile.TemporaryFile() as diagnostics:
            process = subprocess.Popen([compiler, 'check-session', str(entry)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=diagnostics)
            with selectors.DefaultSelector() as ready:
                ready.register(process.stdout, selectors.EVENT_READ)

                def request(command, status=0):
                    process.stdin.write(command.encode() + b'\n')
                    process.stdin.flush()
                    assert ready.select(30), 'session reply timed out'
                    response = json.loads(process.stdout.readline())
                    assert response['version'] == 'check-session-v1'
                    assert response['status'] == status, response
                    assert response['cache']['retained_bytes'] <= 16 * 1024 * 1024
                    return response

                try:
                    assert request('check')['reuse'] == {'hits': 0, 'misses': 2}
                    assert request('check')['reuse'] == {'hits': 2, 'misses': 0}
                    data.write_text(valid.replace('return 7', 'return 9'))
                    assert request('check')['reuse'] == {'hits': 1, 'misses': 1}
                    data.write_text(valid.replace('return 7', 'return true'))
                    assert request('check', 1)['reuse'] == {'hits': 1, 'misses': 1}
                    assert request('check', 1)['reuse'] == {'hits': 2, 'misses': 0}
                    data.write_text(valid.replace('export value;', ''))
                    request('check', 1)
                    data.unlink()
                    request('check', 1)
                    data.write_text(valid)
                    request('check')
                    cleared = request('clear')
                    assert cleared['cache']['retained_bytes'] == 0
                    assert request('check')['reuse'] == {'hits': 0, 'misses': 2}
                    assert request('not-a-command', 2)['failure'] == 'UnknownSessionCommand'
                    for _ in range(20):
                        assert request('check')['reuse'] == {'hits': 2, 'misses': 0}
                    request('quit')
                    assert process.wait(timeout=10) == 0
                finally:
                    process.stdin.close()
                    process.stdout.close()
                    if process.poll() is None:
                        process.kill()
                        process.wait()
            diagnostics.seek(0)
            errors = diagnostics.read().decode()
            assert 'E_TYPE' in errors and 'E_PRIVATE_SYMBOL' in errors
        for text, code in ((b'check', 0), (b'x' * 129 + b'\n', 2), (b'x' * 512 + b'\n', 2), (b'', 0)):
            run = subprocess.run([compiler, 'check-session', str(entry)], input=text, capture_output=True, timeout=30)
            assert run.returncode == code, run.stderr
            if code:
                assert json.loads(run.stdout)['failure'] == 'RequestTooLong'
        bad = subprocess.run([compiler, 'check-session', str(entry), '--max-steps=1'], input=b'check\n', capture_output=True)
        assert bad.returncode == 2 and not bad.stdout
        manifest = root / 'inputs.json'
        entry.write_text('module main;import config;fn main()->i64{return config::value();}')
        manifest.write_text(json.dumps({'version': 1, 'module': 'config', 'values': [{'name': 'value', 'type': 'i64', 'value': '7'}]}))
        with tempfile.TemporaryFile() as diagnostics:
            process = subprocess.Popen([compiler, 'check-session', str(entry), '--inputs=' + str(manifest)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=diagnostics)
            try:
                process.stdin.write(b'check\n')
                process.stdin.flush()
                assert json.loads(process.stdout.readline())['status'] == 0
                manifest.write_text('{}')
                process.stdin.write(b'check\nquit\n')
                process.stdin.flush()
                assert json.loads(process.stdout.readline())['status'] == 2
                assert json.loads(process.stdout.readline())['action'] == 'quit'
                assert process.wait(timeout=10) == 0
            finally:
                process.stdin.close()
                process.stdout.close()
                if process.poll() is None:
                    process.kill()
                    process.wait()
    print('Checking session: cold/warm reuse, source/privacy/removal recovery, bounded retention, clear, invalid commands, EOF, line limits and fresh manifests passed')


if __name__ == '__main__':
    main()

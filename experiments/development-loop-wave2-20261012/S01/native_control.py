#!/usr/bin/env python3
"""Paired actual pinned-runner transport/selection control; operational only."""
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import threading

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'scripts'))
import verification_native_telemetry as native
import verification_report as report


def frame(tag, body=b''):
    return struct.pack('<II', tag, len(body)) + body


def read_exact(source, size):
    value = b''
    while len(value) < size:
        more = source.read(size - len(value))
        if not more:
            raise ValueError('truncated runner wire')
        value += more
    return value


def receive(source):
    header = read_exact(source, 8)
    tag, size = struct.unpack('<II', header)
    if size > native.MAX_FRAME:
        raise ValueError('protocol byte bound')
    body = read_exact(source, size)
    return tag, body, header + body


def run(command, env):
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, env=env)
    stderr = []
    reader = threading.Thread(target=lambda: stderr.append(process.stderr.read()))
    reader.start()
    transcript = b''
    tag, body, raw = receive(process.stdout)
    transcript += raw
    if tag != 0 or body.decode() != native.PINNED_ZIG:
        raise ValueError('wrong pinned version')
    process.stdin.write(frame(4)); process.stdin.flush()
    tag, body, raw = receive(process.stdout)
    transcript += raw
    if tag != 3:
        raise ValueError('metadata missing')
    observer = native.Observation('fixture')
    observer.server(0, native.PINNED_ZIG.encode())
    observer.server(3, body)
    for index in range(len(observer.names)):
        process.stdin.write(frame(5, struct.pack('<I', index))); process.stdin.flush()
        while True:
            tag, body, raw = receive(process.stdout)
            transcript += raw
            if tag == 4:
                break
    process.stdin.write(frame(0)); process.stdin.flush()
    process.stdin.close()
    tail = process.stdout.read()
    transcript += tail
    status = process.wait(timeout=10)
    reader.join(timeout=10)
    return dict(status=status, wire_hex=transcript.hex(), stderr=stderr[0].decode('utf-8', errors='replace'))


def main():
    evidence = Path(__file__).parent
    binary = str(ROOT / '.tmp/native-telemetry-fixture')
    direct = run([binary, '--listen=-'], dict(os.environ))
    directory = ROOT / '.tmp/native-telemetry-sidecars'
    directory.mkdir(exist_ok=True)
    proxied = run([sys.executable, str(ROOT / 'scripts/verification_native_telemetry.py'),
                   '--action-id', 'native-fixture', '--member', '0', '--root-id', 'native-fixture.zig',
                   '--', binary, '--listen=-'], dict(os.environ, MYLANG_TEST_TELEMETRY_DIR=str(directory)))
    observed = report.test_timings(directory / 'native-fixture.member.0.json',
                                  action_id='native-fixture', member='native-fixture/member/0')
    (evidence / 'native-direct.json').write_text(json.dumps(direct, indent=2) + '\n')
    (evidence / 'native-proxied.json').write_text(json.dumps(proxied, indent=2) + '\n')
    (evidence / 'native-observed.json').write_text(json.dumps(observed, indent=2) + '\n')
    assert direct['status'] == proxied['status'] == 0
    assert direct['wire_hex'] == proxied['wire_hex']
    assert observed['complete'] and observed['selected'] > 0
    assert all(row['elapsed_scope'] == native.INTERVAL_SCOPE for row in observed['tests'])
    print(json.dumps(dict(equal_wire=True, equal_status=True, selected=observed['selected'],
                          timed=observed['timed'], skipped=observed['skipped'],
                          elapsed_scope=native.INTERVAL_SCOPE)))


if __name__ == '__main__':
    main()

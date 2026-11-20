#!/usr/bin/env python3
"""Native test-index boundary qualification; takes an already-built component."""
import argparse
import os
import random
import struct
import subprocess
import tempfile
import time


def word(value):
    return struct.pack('<I', value)


def frame(payload, identity=bytes(range(40))):
    return b'SLKIDX01' + struct.pack('<IIII', 1, 1, 0, len(payload)) + identity + payload


def request(graph, tests):
    payload = word(len(graph)) + word(len(tests)) + b''.join(map(word, tests))
    for row in graph:
        payload += word(len(row)) + b''.join(map(word, row))
    return frame(payload)


def expected(graph, tests):
    direct = [[] for _ in graph]
    reached = [[] for _ in graph]
    for test in tests:
        for target in graph[test]:
            direct[target].append(test)
        seen = {test}
        pending = [test]
        while pending:
            current = pending.pop()
            reached[current].append(test)
            for target in graph[current]:
                if target not in seen:
                    seen.add(target)
                    pending.append(target)
    payload = word(len(graph))
    for d, r in zip(direct, reached):
        for row in (d, r):
            payload += word(len(row)) + b''.join(map(word, row))
    return payload


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--component', required=True)
    args = parser.parse_args()
    binary = os.path.abspath(args.component)
    with tempfile.TemporaryDirectory() as directory:
        path = os.path.join(directory, 'request.bin')

        def invoke(data):
            with open(path, 'wb') as handle:
                handle.write(data)
            start = time.perf_counter()
            result = subprocess.run([binary, '--request', path], capture_output=True, timeout=30)
            return result, time.perf_counter() - start

        valid = request([], [])
        malformed = [b'', valid[:63], valid[:71], valid + b'\0']
        for offset in (0, 8, 12, 16, 20):
            changed = bytearray(valid)
            changed[offset] = 255
            malformed.append(bytes(changed))
        malformed += [
            frame(word(100001) + word(0)),
            frame(word(0) + word(100001)),
            frame(word(1) + word(1)),
            frame(word(1) + word(1) + word(1) + word(0)),
            frame(word(1) + word(0)),
            frame(word(1) + word(0) + word(1000001)),
            frame(word(1) + word(0) + word(0xffffffff)),
            frame(word(1) + word(0) + word(1)),
            frame(word(1) + word(0) + word(1) + word(1)),
            valid + b'\0' * (16777217 - len(valid)),
        ]
        for number, data in enumerate(malformed):
            result, _ = invoke(data)
            assert result.returncode != 0 and not result.stdout and result.stderr, (number, result)
        # Many root occurrences and repeated edges exceed the reply budget with
        # a compact request; the component must fail before emitting any reply.
        oversized = request([[0] * 200], [0] * 100000)
        result, overflow_time = invoke(oversized)
        assert result.returncode != 0 and not result.stdout
        assert b'response frame exceeds limit' in result.stderr, result.stderr
        missing = subprocess.run([binary, '--request', os.path.join(directory, 'missing')], capture_output=True)
        assert missing.returncode != 0 and not missing.stdout and b'open' in missing.stderr
        invoke(valid)
        with open('/dev/full', 'wb') as full:
            failed_output = subprocess.run([binary, '--request', path], stdout=full, stderr=subprocess.PIPE)
        assert failed_output.returncode != 0 and b'R_OUTPUT' in failed_output.stderr, failed_output.stderr
        rng = random.Random(1337)
        for case in range(100):
            nodes = rng.randrange(20)
            graph = [[rng.randrange(nodes) for _ in range(rng.randrange(8))] for _ in range(nodes)]
            tests = [rng.randrange(nodes) for _ in range(rng.randrange(10))] if nodes else []
            data = request(graph, tests)
            result, _ = invoke(data)
            payload = expected(graph, tests)
            header = bytearray(data[:64])
            header[16:20] = word(1)
            header[20:24] = word(len(payload))
            assert result.returncode == 0 and result.stdout == bytes(header) + payload, case
        graph = [[(node + delta) % 1000 for delta in range(1, 11)] for node in range(1000)]
        tests = list(range(0, 1000, 10))
        data = request(graph, tests)
        payload = expected(graph, tests)
        durations = []
        for _ in range(5):
            result, elapsed = invoke(data)
            assert result.returncode == 0 and result.stdout[64:] == payload
            durations.append(elapsed)
        print(f'{len(malformed)} malformed frames, reply overflow, missing file, output failure, 100 random oracle graphs: passed')
        print(f'1000 nodes/100 tests/10000 edges: request={len(data)} reply={len(result.stdout)} bytes; '
              f'min={min(durations):.6f}s median={sorted(durations)[2]:.6f}s max={max(durations):.6f}s')
        print(f'bounded reply-overflow rejection: {overflow_time:.6f}s')


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Independent native cache-plan protocol oracle; Python is test-only."""
import argparse
import hashlib
import os
import random
import struct
import subprocess
import tempfile
import time


def word(value):
    return struct.pack('<I', value)


def frame(payload):
    return b'SLKCP001' + struct.pack('<IIIIQ', 1, 1, 0, len(payload), 17) + hashlib.sha256(payload).digest() + payload


def request(graph, digests, batches):
    payload = struct.pack('<IIIII', 0, 0, 0, len(graph), len(batches))
    for digest, row in zip(digests, graph):
        payload += digest + word(len(row)) + b''.join(map(word, row))
    for roots in batches:
        payload += word(len(roots)) + b''.join(map(word, roots))
    return frame(payload)


def expected(graph, digests, batches):
    payload = word(len(batches))
    for roots in batches:
        seen = set(roots)
        pending = list(seen)
        reached = []
        while pending:
            for target in graph[pending.pop()]:
                if target not in seen:
                    seen.add(target)
                    pending.append(target)
                    reached.append(target)
        reached.sort(key=lambda node: (digests[node], node))
        payload += word(len(reached)) + b''.join(map(word, reached))
    return payload


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--component', required=True)
    args = parser.parse_args()
    binary = os.path.abspath(args.component)
    with tempfile.TemporaryDirectory(prefix='cache-plan-oracle-') as directory:
        path = os.path.join(directory, 'request.bin')

        def invoke(data):
            with open(path, 'wb') as handle:
                handle.write(data)
            start = time.perf_counter()
            result = subprocess.run([binary, '--request', path], capture_output=True, timeout=30)
            return result, time.perf_counter() - start

        valid = request([], [], [])
        malformed = [b'', valid[:63], valid[:83], valid + b'\0']
        for offset in (0, 8, 12, 16, 20, 64, 68, 72):
            changed = bytearray(valid)
            changed[offset] = 255
            malformed.append(bytes(changed))
        prefix = struct.pack('<III', 0, 0, 0)
        malformed += [
            frame(prefix + word(100001) + word(0)),
            frame(prefix + word(0) + word(100001)),
            frame(prefix + word(1) + word(0)),
            frame(prefix + word(1) + word(0) + bytes(32) + word(1000001)),
            frame(prefix + word(1) + word(0) + bytes(32) + word(1) + word(1)),
            frame(prefix + word(0) + word(1)),
            frame(prefix + word(0) + word(1) + word(1000001)),
            frame(prefix + word(0) + word(1) + word(1) + word(0)),
            valid + b'\0' * (16777217 - len(valid)),
        ]
        for number, data in enumerate(malformed):
            result, _ = invoke(data)
            assert result.returncode != 0 and not result.stdout and result.stderr, (number, result)
        missing = subprocess.run([binary, '--request', os.path.join(directory, 'missing')], capture_output=True)
        assert missing.returncode != 0 and not missing.stdout and missing.stderr
        invoke(valid)
        with open('/dev/full', 'wb') as full:
            failed = subprocess.run([binary, '--request', path], stdout=full, stderr=subprocess.PIPE)
        assert failed.returncode != 0 and b'R_OUTPUT' in failed.stderr, failed.stderr
        rng = random.Random(1337)
        cases = [([], [], []), ([[1, 2, 3], [0], [], []], [b'z'*32, b'a'*32, b'a'*32, b'\xff'*32], [[0, 0, 3], [2], []])]
        for _ in range(100):
            nodes = rng.randrange(25)
            graph = [[rng.randrange(nodes) for _ in range(rng.randrange(8))] for _ in range(nodes)]
            digests = [bytes([rng.randrange(6)]) * 32 for _ in range(nodes)]
            batches = [[rng.randrange(nodes) for _ in range(rng.randrange(8))] if nodes else [] for _ in range(rng.randrange(12))]
            cases.append((graph, digests, batches))
        for case, (graph, digests, batches) in enumerate(cases):
            data = request(graph, digests, batches)
            result, _ = invoke(data)
            payload = expected(graph, digests, batches)
            header = bytearray(data[:64])
            header[16:20] = word(1)
            header[20:24] = word(len(payload))
            assert result.returncode == 0 and result.stdout == bytes(header) + payload, (case, result.stderr)
        # Compact cyclic requests can exceed work even with a tiny reply.
        result, elapsed = invoke(request([[0] * 200], [bytes(32)], [[0]] * 100000))
        assert result.returncode != 0 and not result.stdout and b'planning work exceeds limit' in result.stderr, result.stderr
        print(f'{len(malformed)} malformed frames, missing file, output failure, {len(cases)} independent oracle graphs: passed')
        print(f'bounded work rejection: {elapsed:.6f}s')
        graph = [[(node + delta) % 1000 for delta in range(1, 11)] for node in range(1000)]
        digests = [hashlib.sha256(word(node)).digest() for node in range(1000)]
        batches = [[node] for node in range(0, 1000, 10)]
        data = request(graph, digests, batches)
        payload = expected(graph, digests, batches)
        durations = []
        for _ in range(5):
            result, elapsed = invoke(data)
            assert result.returncode == 0 and result.stdout[64:] == payload, result.stderr
            durations.append(elapsed)
        print(f'1000 nodes/100 batches/10000 edges: request={len(data)} reply={len(result.stdout)} bytes; '
              f'min={min(durations):.6f}s median={sorted(durations)[2]:.6f}s max={max(durations):.6f}s')


if __name__ == '__main__':
    main()

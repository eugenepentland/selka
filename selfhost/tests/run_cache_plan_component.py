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


def frame_v2(payload):
    return b'SLKCP002' + struct.pack('<IIIIQ', 2, 2, 0, len(payload), 19) + hashlib.sha256(payload).digest() + payload


def request_v2(graph, digests, batches, changed, candidates, prior=None):
    topology = hashlib.sha256(b''.join(word(len(row)) + b''.join(map(word, row)) for row in graph)).digest()
    payload = bytearray(bytes(12) + topology + struct.pack('<IIII', len(graph), len(batches), len(changed), prior is not None))
    for digest, row in zip(digests, graph):
        payload += digest + word(len(row)) + b''.join(map(word, row))
    for roots, candidate in zip(batches, candidates):
        payload += word(candidate) + word(len(roots)) + b''.join(map(word, roots))
    payload += b''.join(map(word, changed))
    if prior is not None:
        groups, reverse = prior
        payload += topology + b''.join(map(word, groups))
        for row in reverse:
            payload += word(len(row)) + b''.join(map(word, row))
    return frame_v2(bytes(payload))


def reverse_graph(graph):
    reverse = [[] for _ in graph]
    for source, row in enumerate(graph):
        for target in row:
            reverse[target].append(source)
    return reverse


def reachable(graph, roots):
    seen = set(roots)
    pending = list(seen)
    while pending:
        for target in graph[pending.pop()]:
            if target not in seen:
                seen.add(target)
                pending.append(target)
    return seen


def independent_groups(graph):
    # Mutual reachability is independent of the native Kosaraju and Zig Tarjan.
    closures = [reachable(graph, [node]) for node in range(len(graph))]
    return [min(other for other in closures[node] if node in closures[other]) for node in range(len(graph))]


def decode_v2(data, request):
    assert data[:16] == b'SLKCP002' + word(2) + word(2)
    assert data[16:20] == word(1) and data[24:64] == request[24:64]
    assert struct.unpack_from('<I', data, 20)[0] == len(data) - 64
    counts = struct.unpack_from('<7Q', data, 64)
    nodes, tests = struct.unpack_from('<II', data, 120)
    at = 128
    groups = list(struct.unpack_from(f'<{nodes}I', data, at))
    at += nodes * 4

    def row():
        nonlocal at
        count = struct.unpack_from('<I', data, at)[0]
        at += 4
        values = list(struct.unpack_from(f'<{count}I', data, at))
        at += count * 4
        return values

    reverse = [row() for _ in range(nodes)]
    reused = []
    batches = []
    for _ in range(tests):
        flag = struct.unpack_from('<I', data, at)[0]
        at += 4
        assert flag in (0, 1)
        reused.append(bool(flag))
        batches.append(row())
    assert at == len(data)
    assert counts[5] == sum(reused) and counts[6] == tests - sum(reused)
    assert sum(counts[:5]) <= 64000000
    return counts, groups, reverse, reused, batches


def qualify_v2(invoke, cases):
    rng = random.Random(2048)
    operations = 0
    for graph, digests, batches in cases:
        changed = rng.sample(range(len(graph)), rng.randrange(len(graph) + 1))
        candidates = [bool(rng.randrange(2)) for _ in batches]
        reverse = reverse_graph(graph)
        groups = independent_groups(graph)
        dirty = reachable(reverse, changed)
        reuse = [candidate and not any(root in dirty for root in roots) for roots, candidate in zip(batches, candidates)]
        closures = [[] if reuse[index] else sorted(reachable(graph, roots) - set(roots), key=lambda node: (digests[node], node)) for index, roots in enumerate(batches)]
        for prior in (None, (groups, reverse)):
            request = request_v2(graph, digests, batches, changed, candidates, prior)
            result, _ = invoke(request)
            assert result.returncode == 0, result.stderr
            counts, actual_groups, actual_reverse, actual_reuse, actual_closures = decode_v2(result.stdout, request)
            assert (actual_groups, actual_reverse, actual_reuse, actual_closures) == (groups, reverse, reuse, closures)
            operations += 1
            # Every prior test is now eligible and no facts changed: no closure work.
            request = request_v2(graph, digests, batches, [], [True] * len(batches), (actual_groups, actual_reverse))
            result, _ = invoke(request)
            assert result.returncode == 0, result.stderr
            counts, _, _, reused, _ = decode_v2(result.stdout, request)
            assert all(reused) and counts[3:5] == (0, 0)
            operations += 1
    # Coherent checksummed-looking partitions still need semantic validation.
    # Invoke the actual native planner: the reference path would silently recompute.
    partitions = [
        ([[1, 3], [], [3], []], [0, 0, 0, 0], [[0], [2]], [1]),
        ([[1], [], []], [0, 0, 2], [[1], [2]], [1]),
        ([[1], [0, 2], []], [0, 1, 2], [[0], [2]], [1]),
    ]
    for graph, supplied_groups, batches, changed in partitions:
        digests = [bytes([node + 1]) * 32 for node in range(len(graph))]
        reverse = reverse_graph(graph)
        request = request_v2(graph, digests, batches, changed, [True] * len(batches), (supplied_groups, reverse))
        result, _ = invoke(request)
        assert result.returncode == 0, result.stderr
        counts, groups, actual_reverse, reuse, closures = decode_v2(result.stdout, request)
        dirty = reachable(reverse, changed)
        expected_reuse = [not any(root in dirty for root in roots) for roots in batches]
        expected_closures = [[] if expected_reuse[index] else sorted(reachable(graph, roots) - set(roots), key=lambda node: (digests[node], node)) for index, roots in enumerate(batches)]
        assert groups == independent_groups(graph) and actual_reverse == reverse
        assert reuse == expected_reuse and closures == expected_closures
    # Creation and splitting both recompute recursive groups under new topology.
    for graph, groups in (([[1], [0, 2], []], [0, 0, 2]), ([[1], [], []], [0, 1, 2])):
        request = request_v2(graph, [bytes([node]) * 32 for node in range(3)], [[0], [2]], [1], [True, True])
        result, _ = invoke(request)
        assert result.returncode == 0, result.stderr
        counts, actual_groups, _, reuse, closures = decode_v2(result.stdout, request)
        assert actual_groups == groups and reuse == [False, True]
        assert closures == ([ [1, 2], [] ] if groups[1] == 0 else [[1], []])
    # One demanded group in a long chain must not materialize all suffix closures.
    nodes = 100000
    graph = [[node + 1] for node in range(nodes - 1)] + [[]]
    request = request_v2(graph, [bytes(32)] * nodes, [[0]], [], [False])
    result, elapsed = invoke(request)
    assert result.returncode == 0, result.stderr
    counts, groups, reverse, reused, closures = decode_v2(result.stdout, request)
    assert groups == list(range(nodes)) and closures == [list(range(1, nodes))]
    assert counts[3] <= 2 * nodes and counts[4] <= nodes
    request = request_v2(graph, [bytes(32)] * nodes, [[0]], [], [True], (groups, reverse))
    warm_result, warm_elapsed = invoke(request)
    assert warm_result.returncode == 0, warm_result.stderr
    warm_counts, warm_groups, _, warm_reused, warm_closures = decode_v2(warm_result.stdout, request)
    assert warm_groups == groups and warm_reused == [True] and warm_closures == [[]]
    assert warm_counts[3:5] == (0, 0)
    assert warm_counts[0] <= 8 * nodes and warm_counts[1] <= 6 * nodes
    # Malformed indexes, candidate flags, duplicate changes, and unsupported headers fail.
    valid = request_v2([[1], []], [bytes(32)] * 2, [[0]], [], [True], ([0, 1], [[], [0]]))
    bad = [valid[:123], valid + b'\0', request_v2([[1], []], [bytes(32)] * 2, [[0]], [], [True], ([0, 1], [[], []])),
           request_v2([[1], []], [bytes(32)] * 2, [[0]], [0, 0], [True]),
           request_v2([[1], []], [bytes(32)] * 2, [[0]], [], [2])]
    for offset in (0, 8, 12, 16, 20, 64, 68, 72):
        damaged = bytearray(valid)
        damaged[offset] = 255
        bad.append(bytes(damaged))
    for data in bad:
        result, _ = invoke(data)
        assert result.returncode != 0 and not result.stdout and result.stderr
    print(f'incremental v2: {operations} independent cold/retained/warm batches, {len(partitions)} coherent invalid SCC partitions, creation/splitting, {len(bad)} malformed frames: passed')
    print(f'{nodes}-node single-root chain: closure_nodes={counts[3]} closure_edges={counts[4]} time={elapsed:.6f}s')
    print(f'{nodes}-node retained chain: index_nodes={warm_counts[0]} index_edges={warm_counts[1]} closure_work=0 time={warm_elapsed:.6f}s')

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
        qualify_v2(invoke, cases)
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

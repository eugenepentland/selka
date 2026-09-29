#!/usr/bin/env python3
"""Reference implementations of T1 wordfreq, T3 route and T5 csvstats (hidden)."""
import heapq
import re
import sys


def wordfreq(argv):
    if len(argv) != 2:
        print("usage: wordfreq FILE N", file=sys.stderr)
        return 2
    path, n_text = argv
    if not re.fullmatch(r"[0-9]+", n_text) or int(n_text) == 0:
        print("error: bad count", file=sys.stderr)
        return 2
    n = int(n_text)
    try:
        with open(path, "rb") as f:
            data = f.read()
    except OSError:
        print(f"error: cannot read {path}", file=sys.stderr)
        return 1
    counts = {}
    for w in re.findall(rb"[A-Za-z0-9]+", data):
        w = w.lower()
        counts[w] = counts.get(w, 0) + 1
    ranked = sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))
    out = sys.stdout.buffer
    for w, c in ranked[:n]:
        out.write(w + b" " + str(c).encode() + b"\n")
    return 0


def route(argv):
    if len(argv) != 3:
        print("usage: route GRAPH FROM TO", file=sys.stderr)
        return 2
    path, start, goal = argv
    try:
        with open(path) as f:
            lines = f.read().split("\n")
    except OSError:
        print(f"error: cannot read {path}", file=sys.stderr)
        return 2
    adj = {}
    for lineno, line in enumerate(lines, 1):
        s = line.strip()
        if s == "" or s.startswith("#"):
            continue
        parts = s.split()
        if len(parts) != 3 or not re.fullmatch(r"[0-9]+", parts[2]):
            print(f"error: line {lineno}: bad edge", file=sys.stderr)
            return 2
        a, b, w = parts[0], parts[1], int(parts[2])
        adj.setdefault(a, []).append((b, w))
        adj.setdefault(b, []).append((a, w))
    if start not in adj or goal not in adj:
        print("unreachable")
        return 1
    dist = {start: 0}
    prev = {}
    ways = {start: 1}
    heap = [(0, start)]
    done = set()
    while heap:
        d, u = heapq.heappop(heap)
        if u in done:
            continue
        done.add(u)
        for v, w in adj[u]:
            nd = d + w
            if v not in dist or nd < dist[v]:
                dist[v] = nd
                prev[v] = u
                ways[v] = ways[u]
                heapq.heappush(heap, (nd, v))
            elif nd == dist[v] and v not in done:
                ways[v] = ways[v] + ways[u]
    if goal not in dist:
        print("unreachable")
        return 1
    if ways[goal] != 1:
        print(f"REFERENCE: shortest path not unique ({ways[goal]})", file=sys.stderr)
        return 99
    seq = [goal]
    while seq[-1] != start:
        seq.append(prev[seq[-1]])
    seq.reverse()
    print(f"cost {dist[goal]}")
    print("path " + " -> ".join(seq))
    return 0


class CsvError(Exception):
    pass


def parse_csv(text):
    records = []
    field = []
    record = []
    i = 0
    n = len(text)
    quoted = False
    at_start = True
    while i < n:
        c = text[i]
        if quoted:
            if c == '"':
                if i + 1 < n and text[i + 1] == '"':
                    field.append('"')
                    i += 2
                    continue
                quoted = False
                i += 1
                continue
            field.append(c)
            i += 1
            continue
        if c == '"' and at_start:
            quoted = True
            at_start = False
            i += 1
            continue
        if c == ",":
            record.append("".join(field))
            field = []
            at_start = True
            i += 1
            continue
        if c == "\r" and i + 1 < n and text[i + 1] == "\n":
            i += 1
            continue
        if c == "\n":
            record.append("".join(field))
            records.append(record)
            field = []
            record = []
            at_start = True
            i += 1
            continue
        field.append(c)
        at_start = False
        i += 1
    if field or record or not at_start:
        record.append("".join(field))
        records.append(record)
    return records


def fmt2(x):
    return f"{x:.2f}"


def csvstats(argv):
    if len(argv) != 3:
        print("usage: csvstats FILE GROUP VALUE", file=sys.stderr)
        return 2
    path, gcol, vcol = argv
    try:
        with open(path, encoding="utf-8", newline="") as f:
            text = f.read()
    except OSError:
        print(f"error: cannot read {path}", file=sys.stderr)
        return 2
    records = parse_csv(text)
    header = records[0]
    rows = records[1:]
    for name in (gcol, vcol):
        if name not in header:
            print(f"error: no column '{name}'", file=sys.stderr)
            return 2
    gi = header.index(gcol)
    vi = header.index(vcol)
    order = []
    stats = {}
    for r, row in enumerate(rows, 1):
        if len(row) != len(header):
            print(f"error: row {r}: expected {len(header)} fields", file=sys.stderr)
            return 1
        v = row[vi]
        if v == "":
            continue
        if not re.fullmatch(r"-?[0-9]+(\.[0-9]+)?", v):
            print(f"error: row {r}: bad number '{v}'", file=sys.stderr)
            return 1
        x = float(v)
        g = row[gi]
        if g not in stats:
            order.append(g)
            stats[g] = [0, 0.0, x, x]
        s = stats[g]
        s[0] += 1
        s[1] += x
        s[2] = min(s[2], x)
        s[3] = max(s[3], x)
    for g in order:
        c, total, lo, hi = stats[g]
        mean = total / c
        for val in (total, mean, lo, hi):
            frac = abs(val * 100) % 1
            if abs(frac - 0.5) < 1e-6:
                print(f"REFERENCE: rounding tie in {val!r}", file=sys.stderr)
                return 99
        print(f"{g}: count={c} sum={fmt2(total)} mean={fmt2(mean)} min={fmt2(lo)} max={fmt2(hi)}")
    return 0


if __name__ == "__main__":
    tool = sys.argv[1]
    sys.exit({"wordfreq": wordfreq, "route": route, "csvstats": csvstats}[tool](sys.argv[2:]))

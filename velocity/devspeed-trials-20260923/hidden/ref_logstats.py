#!/usr/bin/env python3
"""Reference implementation of the held-out T6 `logstats` task (hidden)."""
import math
import re
import sys

LINE = re.compile(r'^(\S+) \S+ \S+ \[([^\]]+)\] "(\S+) (\S+) (\S+)" ([0-9]{3}) ([0-9]+|-) ([0-9]+)$')


def main(argv):
    if len(argv) != 2:
        print("usage: logstats FILE K", file=sys.stderr)
        return 2
    path, k_text = argv
    if not re.fullmatch(r"[0-9]+", k_text) or int(k_text) == 0:
        print("error: bad k", file=sys.stderr)
        return 2
    k = int(k_text)
    try:
        with open(path, "rb") as f:
            text = f.read().decode("utf-8")
    except OSError:
        print(f"error: cannot read {path}", file=sys.stderr)
        return 2
    lines = 0
    malformed = 0
    classes = [0, 0, 0, 0, 0]
    paths = {}
    ips = {}
    for raw in text.split("\n"):
        line = raw[:-1] if raw.endswith("\r") else raw
        if line.strip() == "":
            continue
        lines += 1
        m = LINE.match(line)
        if not m or not ("1" <= m.group(6)[0] <= "5"):
            malformed += 1
            continue
        ip, _, _, p, _, status, nbytes, dur = m.groups()
        classes[int(status[0]) - 1] += 1
        entry = paths.setdefault(p, [[], 0])
        entry[0].append(int(dur))
        entry[1] += 0 if nbytes == "-" else int(nbytes)
        ips[ip] = ips.get(ip, 0) + 1
    print(f"lines {lines}")
    print(f"malformed {malformed}")
    print("status " + " ".join(f"{i + 1}xx={classes[i]}" for i in range(5)))
    for p, (durs, total) in sorted(paths.items(), key=lambda kv: (-len(kv[1][0]), kv[0])):
        durs.sort()
        n = len(durs)
        p50 = durs[math.ceil(0.50 * n) - 1]
        p95 = durs[math.ceil(0.95 * n) - 1]
        print(f"path {p} count={n} p50={p50} p95={p95} bytes={total}")
    for ip, c in sorted(ips.items(), key=lambda kv: (-kv[1], kv[0]))[:k]:
        print(f"top_ip {ip} {c}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

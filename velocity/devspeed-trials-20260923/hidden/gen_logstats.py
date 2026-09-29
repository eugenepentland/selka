#!/usr/bin/env python3
"""Generate the hidden cases for the held-out T6 `logstats` task from ref_logstats.py.

Writes cases/logstats/<name>/{a.log, case.json}; deterministic (seed 3).
"""
import json
import os
import random
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE / "cases" / "logstats"


def case(name, files, args, limit=10.0, check_stderr=True):
    d = OUT / name
    d.mkdir(parents=True)
    for f, c in files.items():
        (d / f).write_bytes(c if isinstance(c, bytes) else c.encode())
    real = [a.replace("{dir}", str(d.resolve())) for a in args]
    p = subprocess.run([sys.executable, str(HERE / "ref_logstats.py")] + real, capture_output=True)
    json.dump({"args": args, "stdout": p.stdout.decode(), "exit": p.returncode,
               "stderr_first_line": p.stderr.decode().split("\n")[0] if (check_stderr and p.stderr) else None,
               "limit_s": limit}, open(d / "case.json", "w"), indent=1)


def line(ip, path, status, b, dur, method="GET", ts="10/Oct/2026:13:55:36 +0000"):
    return f'{ip} - - [{ts}] "{method} {path} HTTP/1.1" {status} {b} {dur}'


def main():
    shutil.rmtree(OUT, ignore_errors=True)
    small = "\n".join([
        line("10.0.0.1", "/index", 200, 512, 12), line("10.0.0.2", "/index", 200, "-", 30),
        line("10.0.0.1", "/api/items", 404, 0, 5), line("10.0.0.3", "/api/items", 500, 120, 250),
        line("10.0.0.1", "/index", 304, 0, 3), "garbage line here",
        line("10.0.0.2", "/login", 302, 0, 40, method="POST"), "", line("10.0.0.9", "/index", 200, 100, 18)]) + "\n"
    case("basic", {"a.log": small}, ["{dir}/a.log", "2"])
    case("k_larger", {"a.log": small}, ["{dir}/a.log", "10"])
    case("ip_tie_order", {"a.log": "\n".join([line("9.9.9.9", "/a", 200, 1, 1), line("10.0.0.10", "/a", 200, 1, 1),
                                              line("10.0.0.2", "/a", 200, 1, 1)]) + "\n"}, ["{dir}/a.log", "3"])
    case("percentiles", {"a.log": "\n".join(line("1.1.1.1", "/p", 200, 1, d) for d in
                                            [5, 1, 9, 3, 7, 2, 8, 4, 6, 10, 100, 50, 20, 30, 40, 60, 70, 80, 90, 95]) + "\n"},
         ["{dir}/a.log", "1"])
    case("malformed_variants", {"a.log": "\n".join([
        line("1.1.1.1", "/ok", 200, 1, 1),
        '1.1.1.1 - - [10/Oct/2026:13:55:36 +0000] "GET /x HTTP/1.1" 200 1',
        '1.1.1.1 - - [10/Oct/2026:13:55:36 +0000] "GET /x" 200 1 5',
        '1.1.1.1 - - [10/Oct/2026:13:55:36 +0000] "GET /x HTTP/1.1" 20 1 5',
        '1.1.1.1 - - [10/Oct/2026:13:55:36 +0000] "GET /x HTTP/1.1" 600 1 5',
        '1.1.1.1 - - [10/Oct/2026:13:55:36 +0000] "GET /x HTTP/1.1" 200 1 5 extra',
        '1.1.1.1 - - 10/Oct/2026:13:55:36 "GET /x HTTP/1.1" 200 1 5',
        '1.1.1.1 - - [10/Oct/2026:13:55:36 +0000] "GET /x HTTP/1.1" 200 x 5',
        line("1.1.1.2", "/ok", 199, 1, 2)]) + "\n"}, ["{dir}/a.log", "5"])
    case("crlf_no_trailing_newline", {"a.log": (line("1.1.1.1", "/a", 200, 1, 1) + "\r\n" + line("1.1.1.2", "/b", 201, 2, 2))},
         ["{dir}/a.log", "5"])
    case("empty", {"a.log": ""}, ["{dir}/a.log", "3"])
    case("missing_file", {}, ["{dir}/nope.log", "3"])
    case("bad_k", {"a.log": small}, ["{dir}/a.log", "0"])
    case("bad_k_word", {"a.log": small}, ["{dir}/a.log", "x"])
    case("usage", {"a.log": small}, ["{dir}/a.log"], check_stderr=False)
    rng = random.Random(3)
    paths = [f"/api/v1/r{i}" for i in range(40)] + ["/", "/index", "/login"]
    ips = [f"10.{rng.randrange(256)}.{rng.randrange(256)}.{rng.randrange(256)}" for _ in range(3000)]
    lines = []
    for i in range(500000):
        if rng.random() < 0.001:
            lines.append("corrupt entry %d" % i)
            continue
        lines.append(line(rng.choice(ips), rng.choice(paths), rng.choice([200, 200, 200, 201, 301, 304, 404, 500]),
                          rng.choice(["-", str(rng.randrange(100000))]), rng.randrange(1, 2000)))
    case("large_500k", {"a.log": "\n".join(lines) + "\n"}, ["{dir}/a.log", "10"])
    for n in sorted(os.listdir(OUT)):
        print(n, json.load(open(OUT / n / "case.json"))["exit"])


if __name__ == "__main__":
    main()

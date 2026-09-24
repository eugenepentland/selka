#!/usr/bin/env python3
"""Capture the exact `ld.lld` argv (and every other tool argv) a build runs.

usage: capture_link.py OUT.json -- BUILD_CMD...

Runs BUILD_CMD under `strace -f -v -s 10000000 -e trace=execve` and writes
{"tools": [[argv...], ...], "link": [argv of the last ld.lld run]} to OUT.json.
Run it after an edit so the build actually links.
"""
import ast
import json
import os
import re
import subprocess
import sys


def main():
    out = sys.argv[1]
    cmd = sys.argv[sys.argv.index("--") + 1:]
    trace = out + ".strace"
    env = dict(os.environ)
    env.setdefault("TMPDIR", "/home/epentland/.cache/mylang-tmp")
    subprocess.run(["strace", "-f", "-v", "-s", "10000000", "-e", "trace=execve", "-o", trace] + cmd,
                   env=env, capture_output=True)
    tools = []
    for line in open(trace, errors="replace"):
        m = re.match(r'\d+ +execve\("([^"]*)", (\[.*?\]), (?:\[|0x)', line)
        if not m or line.rstrip().endswith("= -1 ENOENT (No such file or directory)"):
            continue
        try:
            argv = ast.literal_eval(m.group(2))
        except Exception:
            continue
        tools.append([m.group(1)] + argv[1:])
    link = [t for t in tools if len(t) > 1 and t[1] == "ld.lld"]
    json.dump({"tools": tools, "link": link[-1] if link else None}, open(out, "w"))
    os.remove(trace)
    print(json.dumps({"tools": len(tools), "link_args": len(link[-1]) if link else 0}))


if __name__ == "__main__":
    main()

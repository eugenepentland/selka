#!/usr/bin/env python3
"""Innermost loop body sizes (bytecode instructions) per function, and whether
the function's release IL versions a loop at that head.
usage: loopsizes.py MYLANG FILE.my..."""
import json
import re
import subprocess
import sys

mylang, *files = sys.argv[1:]
for path in files:
    dump = subprocess.run([mylang, "dump-bytecode", path], capture_output=True, text=True).stdout
    emit = subprocess.run([mylang, "emit-qbe", path, "--drop-debug", "--drop-step-checks", "--drop-frame-checks"],
                          capture_output=True, text=True).stdout
    versioned = {}
    try:
        for unit in json.loads(emit)["functions"]:
            versioned[unit["name"]] = set(int(h) for h in re.findall(r"^@oi(\d+)$", unit["il"], re.M))
    except json.JSONDecodeError:
        pass
    function = None
    for line in dump.splitlines():
        m = re.match(r"function (\w+)\(", line)
        if m:
            function = m.group(1)
            continue
        m = re.match(r"\s+(\d+)\s+JUMP (\d+)\b", line)
        if m and int(m.group(2)) < int(m.group(1)):
            back, head = int(m.group(1)), int(m.group(2))
            mark = "V" if head in versioned.get(function, set()) else "-"
            print(f"{path.split('/')[-1]:28} {function:16} head {head:5} size {back - head:5} {mark}")

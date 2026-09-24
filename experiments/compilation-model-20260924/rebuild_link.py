#!/usr/bin/env python3
"""Rebuild a link that failed with E2BIG and time it through a response file.

usage: rebuild_link.py FAILED.strace TEMPLATE_LINK.json OUT_LINK.json OUT_EXE

FAILED.strace is `strace -f -v -s 100000000 -e trace=execve` of a build whose
`zig cc -###` link failed with E2BIG. TEMPLATE_LINK.json is a capture_link.py
capture of a smaller build of the same shape; its non-object arguments (crt files,
runtime archive, flags) are kept and its guest objects are replaced with the objects of
the failed command. Writes OUT_LINK.json (argv with an @response file) and runs it once
under `taskset -c 0-11`, printing wall time and output size.
"""
import ast
import json
import os
import re
import subprocess
import sys
import time


def main():
    trace, template, out_json, exe = sys.argv[1:5]
    failed = None
    for line in open(trace, errors="replace"):
        if "E2BIG" in line and "execve(" in line:
            m = re.search(r'execve\("[^"]*", (\[.*?\]), \[', line)
            failed = ast.literal_eval(m.group(1))
    if not failed:
        sys.exit("no E2BIG execve in trace")
    objects = [a for a in failed if a.endswith(".o") and "/objects/" in a]
    tmpl = json.load(open(template))["link"]
    head = [a for a in tmpl if not (a.endswith(".o") and "/objects/" in a)]
    head[head.index("-o") + 1] = exe
    # guest objects go where the template's first guest object was
    first = next(i for i, a in enumerate(tmpl) if a.endswith(".o") and "/objects/" in a)
    before = [a for a in tmpl[:first] if not (a.endswith(".o") and "/objects/" in a)]
    before[before.index("-o") + 1] = exe
    after = [a for a in tmpl[first:] if not (a.endswith(".o") and "/objects/" in a)]
    rsp = out_json + ".rsp"
    with open(rsp, "w") as f:
        f.write("\n".join(objects) + "\n")
    argv = before + [f"@{rsp}"] + after
    json.dump({"link": argv, "objects": len(objects), "argv_bytes_without_rsp": sum(len(a) + 1 for a in failed)}, open(out_json, "w"))
    t = time.perf_counter()
    p = subprocess.run(["taskset", "-c", "0-11"] + argv, capture_output=True, text=True)
    dt = time.perf_counter() - t
    print(json.dumps({"objects": len(objects), "failed_argv_bytes": sum(len(a) + 1 for a in failed), "rc": p.returncode,
                      "link_s": round(dt, 3), "output_bytes": os.path.getsize(exe) if p.returncode == 0 else None,
                      "load": round(os.getloadavg()[0], 2), "err": p.stderr[-500:]}))


if __name__ == "__main__":
    main()

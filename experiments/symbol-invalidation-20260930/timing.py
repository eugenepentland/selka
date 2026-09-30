#!/usr/bin/env python3
"""Wall time and module_build counts of each oracle edit's incremental build,
without the whole-program oracle builds: timing.py COMPILER SOURCE WORK [--gc-runtime]."""
import json, os, shutil, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import oracle

compiler, source, work = (os.path.abspath(x) for x in sys.argv[1:4])
extra = sys.argv[4:]
shutil.rmtree(work, ignore_errors=True)
project = os.path.join(work, "project")
shutil.copytree(source, project, ignore=shutil.ignore_patterns(".mylang-cache"))
cache = os.path.join(work, "cache")
for edit in [("cold", "", None, None, None)] + oracle.EDITS:
    oracle.apply(project, edit)
    if edit[0] in oracle.PAIRED:
        continue
    done, elapsed, counts = oracle.build(compiler, project, "incremental", cache, extra)
    print(json.dumps({"edit": edit[0], "compiled": counts and counts["compiled"], "seconds": round(elapsed, 3), "ok": done.returncode == 0}), flush=True)

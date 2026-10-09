#!/usr/bin/env python3
"""Run a mylang fixture under CPython: strips `module`, `mut` and the Stream type."""
import re, sys
src = open(sys.argv[1]).read()
src = re.sub(r"^module .*$", "", src, flags=re.M)
src = src.replace("mut ", "").replace("    e = d\n", "    e = dict(d)\n")
class Stream:
    def print(self, *a):
        print(*[("True" if x is True else "False" if x is False else x) for x in a])
ns = {"Stream": Stream}
exec(compile(src, sys.argv[1], "exec"), ns)
sys.exit(ns["main"](Stream()))

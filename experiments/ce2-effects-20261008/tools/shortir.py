#!/usr/bin/env python3
"""Shorten `mylang dump-ir` output: every type spelling longer than 40 characters becomes Tn
(a legend at the top). usage: shortir.py IN [FUNCTION_PREFIX]"""
import sys

def scan_types(text):
    out, names, i = [], {}, 0
    starts = ("record{", "union{", "list[", "option[", "dict[", "box[", "array[")
    while i < len(text):
        if any(text.startswith(s, i) for s in starts):
            depth, j = 0, i
            while j < len(text):
                c = text[j]
                if c in "{[":
                    depth += 1
                elif c in "}]":
                    depth -= 1
                    if depth == 0:
                        j += 1
                        break
                j += 1
            ty = text[i:j]
            if len(ty) > 40:
                if ty not in names:
                    names[ty] = f"T{len(names)}"
                out.append(names[ty])
            else:
                out.append(ty)
            i = j
        else:
            out.append(text[i])
            i += 1
    return "".join(out), names

text = open(sys.argv[1]).read()
if len(sys.argv) > 2:
    keep, on = [], False
    for line in text.splitlines():
        if line.startswith("fn "):
            on = line.startswith("fn " + sys.argv[2])
        if on:
            keep.append(line)
    text = "\n".join(keep) + "\n"
short, names = scan_types(text)
for ty, n in names.items():
    print(f"; {n} = {ty[:300]}")
print(short)

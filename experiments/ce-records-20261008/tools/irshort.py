#!/usr/bin/env python3
"""Shorten Core IR text: name each distinct compound type T1, T2, ... (printed once at the end)."""
import sys, re
names = {}
def collapse(text):
    out, i = [], 0
    while i < len(text):
        m = re.compile(r"(record|union|list|option|box|dict)\{").match(text, i) if text[i] in "rulobd" else None
        if m:
            depth, j = 0, m.end() - 1
            while j < len(text):
                if text[j] == "{": depth += 1
                elif text[j] == "}":
                    depth -= 1
                    if depth == 0: break
                j += 1
            full = text[i:j + 1]
            if len(full) > 40:
                names.setdefault(full, f"T{len(names) + 1}")
                out.append(names[full]); i = j + 1; continue
        out.append(text[i]); i += 1
    return "".join(out)
want = sys.argv[1] if len(sys.argv) > 1 else None
printing = want is None
for line in sys.stdin:
    if line.startswith("fn "):
        printing = want is None or line.startswith(f"fn {want}(")
    if printing:
        sys.stdout.write(collapse(line))

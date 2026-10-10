#!/usr/bin/env python3
"""FU-PORT: migrate the mylang sources embedded as Zig multiline strings (`\\` lines) in the
given test files with `mylang fix`, one snippet at a time, and write the result back in place.
usage: migrate_embedded.py MYLANG WORKDIR FILE.zig...   Prints per snippet: edits and leftovers."""
import pathlib, re, subprocess, sys

mylang, work = sys.argv[1], pathlib.Path(sys.argv[2])
work.mkdir(parents=True, exist_ok=True)
LINE = re.compile(r"^(\s*)\\\\(.*)$")
total = 0
for name in sys.argv[3:]:
    path = pathlib.Path(name)
    lines = path.read_text().split("\n")
    out, i, n = [], 0, 0
    while i < len(lines):
        m = LINE.match(lines[i])
        if not m:
            out.append(lines[i]); i += 1; continue
        start, prefix, body = i, m.group(1), []
        while i < len(lines) and (mm := LINE.match(lines[i])):
            body.append(mm.group(2)); i += 1
        text = "\n".join(body)
        if not re.search(r"\b(def|record|union|enum)\b|list\[", text):
            out.extend(lines[start:i]); continue
        n += 1
        snippet = work / f"{path.stem}_{n:02d}.my"
        snippet.write_text(text)
        done = subprocess.run([mylang, "fix", f"--cache-dir={work}/cache", str(snippet)], capture_output=True, text=True)
        report = (done.stdout + done.stderr).strip().splitlines()
        edits = sum(int(x) for x in re.findall(r"^fix: (\d+) edits", done.stdout + done.stderr, re.M))
        total += edits
        print(f"{path.name} snippet {n} (line {start + 1}): status {done.returncode}, {edits} edits")
        for line in report:
            if "error" in line or "warning" in line:
                print("   ", line)
        new = snippet.read_text().split("\n")
        out.extend(f"{prefix}\\\\{t}" for t in new)
    path.write_text("\n".join(out))
print(f"total edits {total}")

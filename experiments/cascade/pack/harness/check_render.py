#!/usr/bin/env python3
"""Byte-compare the arm's renderings with the pack's hidden goldens.

Run from the verification directory (the one holding ``verify.json``), which
holds ``cases.tsv``, ``golden/<name>.txt`` and this script::

    python3 harness/check_render.py ../project ../bin/mylang cases.tsv

``cases.tsv`` is ``name<TAB>input-path`` (input paths relative to the project or
absolute). Each golden is the exact byte sequence ``printer.render`` must
produce; this script strips trailing newlines from both sides because the CLI's
``out.print`` appends one of its own. The trailing-newline contract itself is
asserted by the guest tests, not here.

Exit status: 0 when every case matches, 1 on a mismatch, 2 on a usage error.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: check_render.py <project-root> <binary> <cases.tsv>", file=sys.stderr)
        return 2
    project = Path(sys.argv[1]).resolve()
    binary = Path(sys.argv[2]).resolve()
    cases = Path(sys.argv[3])
    if not (project / "main.my").is_file():
        print(f"check_render: no main.my under {project}", file=sys.stderr)
        return 2
    rows = []
    for line in cases.read_text().splitlines():
        if line.strip() and not line.startswith("#"):
            name, _, source = line.partition("\t")
            rows.append((name.strip(), source.strip()))
    if not rows:
        print("check_render: no cases", file=sys.stderr)
        return 2
    failures = 0
    for name, source in rows:
        path = Path(source)
        if not path.is_absolute():
            path = (cases.parent / path).resolve()
        golden = (cases.parent / "golden" / f"{name}.txt").read_bytes().rstrip(b"\n")
        result = subprocess.run(
            [str(binary), "run", str(project / "main.my"), "--", str(path), "--render"],
            cwd=project,
            capture_output=True,
        )
        produced = result.stdout.rstrip(b"\n")
        if result.returncode != 0 or produced != golden:
            failures += 1
            print(f"FAIL {name}: exit {result.returncode}, {len(produced)} bytes vs {len(golden)} expected", file=sys.stderr)
            if produced != golden:
                for index, (want, got) in enumerate(zip(golden, produced)):
                    if want != got:
                        print(f"  first difference at byte {index}: expected {want!r}, got {got!r}", file=sys.stderr)
                        break
                else:
                    print(f"  common prefix of {min(len(golden), len(produced))} bytes", file=sys.stderr)
            if result.stderr.strip():
                print(f"  stderr: {result.stderr.decode(errors='replace').strip()[:300]}", file=sys.stderr)
        else:
            print(f"ok   {name}")
    if failures:
        print(f"check_render: {failures} of {len(rows)} cases failed", file=sys.stderr)
        return 1
    print(f"check_render: {len(rows)} cases match")
    return 0


if __name__ == "__main__":
    sys.exit(main())

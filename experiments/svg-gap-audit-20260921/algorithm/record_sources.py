#!/usr/bin/env python3
"""Record the exact isolated source delta without touching production."""
from pathlib import Path
import difflib

ROOT = Path(__file__).resolve().parents[3]
WORK = ROOT / ".tmp/svg-gap-audit-20260921/algorithm"
OUT = Path(__file__).resolve().parent
before = (WORK / "control/guest/layout.my").read_text().splitlines(keepends=True)
after = (WORK / "indexed/guest/layout.my").read_text().splitlines(keepends=True)
patch = difflib.unified_diff(before, after,
    fromfile="control/guest/layout.my", tofile="indexed/guest/layout.my")
(OUT / "indexed-net-facts.patch").write_text("".join(patch))
before = (WORK / "control/guest/circuit.my").read_text().splitlines(keepends=True)
after = (WORK / "normalize/guest/circuit.my").read_text().splitlines(keepends=True)
patch = difflib.unified_diff(before, after,
    fromfile="control/guest/circuit.my", tofile="normalize/guest/circuit.my")
(OUT / "normalize-early-exit.patch").write_text("".join(patch))

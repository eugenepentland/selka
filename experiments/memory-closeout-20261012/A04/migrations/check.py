#!/usr/bin/env python3
"""Check the assigned migration corpus under one bounded shared build lease."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
sys.path.insert(0, str(ROOT / "experiments/memory-closeout-20261012/A04"))
import ownership_commands as ownership
parser = argparse.ArgumentParser(description=__doc__)
ownership.add_option(parser)
parser.add_argument("--compiler", type=Path, required=True)
parser.add_argument("--phase", required=True)
args = parser.parse_args()
report = HERE / (args.phase + ".json")
assert not report.exists(), "choose a new evidence phase"
manifest = json.loads((HERE / "sources.json").read_text())
mirror = ROOT / ".tmp/memory-closeout/A04/migrations" / args.phase
shutil.copytree(ROOT / "tests", mirror / "tests", dirs_exist_ok=True)
rows = []
for original in manifest["sources"]:
    source = ROOT / original["source"]
    checked = mirror / original["source"]
    text = source.read_text()
    if not re.search(r"^(?:public )?func main\(", text, re.M):
        checked.write_text(text + "\n\nfunc main() -> int:\n    return 0\n")
    command = [str(args.compiler), "check", str(checked), *ownership.flags(args), "--cache-dir", str(mirror / "cache")]
    ran = subprocess.run(command, capture_output=True, text=True, cwd=ROOT)
    row = dict(original, source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
               command=command, status=ran.returncode, stdout=ran.stdout, stderr=ran.stderr)
    rows.append(row)
    print(original["source"], ran.returncode, ran.stderr.splitlines()[0] if ran.stderr else "", flush=True)
report.write_text(json.dumps({"compiler": str(args.compiler), "compiler_sha256": hashlib.sha256(args.compiler.read_bytes()).hexdigest(),
                             "default_ownership": args.default_ownership, "ownership_support_sha256": ownership.digest(), "rows": rows, "passed": sum(row["status"] == 0 for row in rows), "total": len(rows)}, indent=2) + "\n")

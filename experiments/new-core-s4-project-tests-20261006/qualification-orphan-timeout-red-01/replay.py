"""Replay the preserved historical failure in a fresh, fixture-owned directory."""
import argparse
import hashlib
from pathlib import Path
import subprocess
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--evidence", type=Path, required=True)
args = parser.parse_args()
original = Path(__file__).resolve().parent
destination = args.evidence.resolve()
destination.mkdir(parents=True, exist_ok=False)
data = (original / "qualification_support.pre-repair.py.txt").read_bytes()
assert hashlib.sha256(data).hexdigest() == "b708dd0023ec89a5c2e156ee71027030116ce9e4355a76c157d6eab22769eb62"
(destination / "qualification_support.py").write_bytes(data)
run = destination / "run"
run.mkdir()
for name in ("fixture.py", "runner.py", "reduce.py"):
    source = (original / name).read_text().replace(str(original), str(run))
    (run / name).write_text(source)
raise SystemExit(subprocess.call([sys.executable, str(run / "reduce.py")]))

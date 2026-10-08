#!/usr/bin/env python3
"""S4-E's strict 50-case package matrix, preserving S3's generators and checks."""
from pathlib import Path

root = Path(__file__).resolve().parents[2]
source = root / "experiments/new-core-s3-20261006/wave-x/integration/fuzz_matrix.py"
code = source.read_text().replace('Path(__file__).resolve().parents[4]', 'Path(__file__).resolve().parents[2]')
code = code.replace('HERE = Path(__file__).resolve().parent', 'HERE = ROOT / "experiments/new-core-s3-20261006/wave-x/integration"')
code = code.replace('200', '50')
exec(compile(code, str(source), "exec"), {"__name__": "__main__", "__file__": str(Path(__file__).resolve())})

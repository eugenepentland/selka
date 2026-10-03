#!/usr/bin/env python3
"""Verify immutable reviewed evidence; never builds or runs a guest."""
import gzip
import hashlib
import json
from pathlib import Path


def sha(data):
    return hashlib.sha256(data).hexdigest()


here = Path(__file__).resolve().parent
review = json.loads((here / "review.json").read_text())
assert sha((here / "proof-v2.json").read_bytes()) == review["proof_receipt_sha256"]
frozen = Path(review["frozen_source"])
for relative, expected in review["frozen_files"].items():
    assert sha((frozen / relative).read_bytes()) == expected, relative
for name, record in review["authored_checks_read_not_rerun"].items():
    data = gzip.decompress((here / (name + ".log.gz")).read_bytes())
    assert sha(data) == record["log_sha256"], name
    assert record["status"] == 0
failed = review["original_v2_failure"]
assert sha((here / "focused-v2-rejected.json").read_bytes()) == failed["receipt_sha256"]
data = gzip.decompress((here / "focused-v2-rejected.log.gz").read_bytes())
assert sha(data) == failed["log_sha256"]
assert failed["status"] == 1
print(json.dumps({"frozen_files_verified": len(review["frozen_files"]),
                  "retained_logs_verified": 3,
                  "qualification_rerun": False,
                  "performance_claim": False}, sort_keys=True))

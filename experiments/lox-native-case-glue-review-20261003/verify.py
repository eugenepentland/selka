#!/usr/bin/env python3
"""Read-only identity check; no compiler build, qualification, or performance run."""
import gzip
import hashlib
import json
from pathlib import Path


def sha(data):
    return hashlib.sha256(data).hexdigest()


here = Path(__file__).resolve().parent
review = json.loads((here / "review.json").read_text())
assert sha((here / "proof-bounded.json").read_bytes()) == review["proof_receipt_sha256"]
frozen = Path(review["frozen_source"])
for relative, expected in review["final_files"].items():
    assert sha((frozen / relative).read_bytes()) == expected, relative
for name in ("focused", "guardian"):
    record = review["qualifications_read_not_rerun"][name]
    data = gzip.decompress((here / (name + "-bounded.log.gz")).read_bytes())
    assert sha(data) == record["log_sha256"], name
    assert record["outer_status"] == 0
print(json.dumps({"frozen_source_files_verified": len(review["final_files"]),
                  "retained_logs_verified": 2,
                  "qualification_rerun": False,
                  "performance_claim": False}, sort_keys=True))

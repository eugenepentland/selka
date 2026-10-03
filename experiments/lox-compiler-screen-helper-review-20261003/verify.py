#!/usr/bin/env python3
"""Check reviewed helper identities without executing a helper or guest."""
import gzip
import hashlib
import json
from pathlib import Path

here = Path(__file__).resolve().parent
review = json.loads((here / "review.json").read_text())
for name, record in review["helpers"].items():
    retained = gzip.decompress((here / (name + ".gz")).read_bytes())
    assert hashlib.sha256(retained).hexdigest() == record["sha256"]
    assert hashlib.sha256(Path(record["original"]).read_bytes()).hexdigest() == record["sha256"]
print(json.dumps({"helpers_verified": len(review["helpers"]),
                  "helper_execution": False, "performance_claim": False}, sort_keys=True))

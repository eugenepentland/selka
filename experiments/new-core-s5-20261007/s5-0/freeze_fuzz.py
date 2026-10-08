#!/usr/bin/env python3
"""S5-0: freeze the old core's fuzz outcomes from a strict matrix run's journals.

Reads EVIDENCE/<kind>/commands.jsonl and EVIDENCE/<kind>/sources of a
fuzz_matrix.py run made against the old oracle (S4's x-matrix-01, 9 kinds x 200
cases), and keeps every old-core build status and native run, keyed by the
generated source's SHA-256 and the run's arguments. The generators are
deterministic per seed, so the same matrix regenerates exactly these sources.
Usage: freeze_fuzz.py --evidence DIR --output references/fuzz-v1.json.gz
"""
import argparse
import gzip
import hashlib
import json
from pathlib import Path

KINDS = ("s0", "s1", "rc", "rebinding", "iteration", "dict", "text", "number", "functions")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit("output exists; keep it and choose a new path")
    matrix = json.loads((args.evidence / "matrix.json").read_text())
    references = {"version": "s5-fuzz-references-v1", "oracle": matrix["oracles"]["old"],
                  "matrix_source_commit": matrix["source_commit"], "cases_per_kind": matrix["cases_per_kind"], "kinds": {}}
    counts = {}
    for kind in KINDS:
        sources = {}
        kept = references["kinds"].setdefault(kind, {})
        for line in (args.evidence / kind / "commands.jsonl").open():
            record = json.loads(line)
            if record["role"] != "old":
                continue
            name = Path(record["source"]).name
            if name not in sources:
                sources[name] = hashlib.sha256((args.evidence / kind / "sources" / name).read_bytes()).hexdigest()
            entry = kept.setdefault(sources[name], {"build": None, "runs": []})
            if record["building"]:
                entry["build"] = record["status"]
            else:
                entry["runs"].append({"args": record["command"][1:], "status": record["status"],
                                      "stdout_b64": record["stdout_b64"], "stderr_b64": record["stderr_b64"]})
        counts[kind] = {"sources": len(kept), "runs": sum(len(e["runs"]) for e in kept.values())}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with gzip.open(args.output, "wt") as out:
        json.dump(references, out, sort_keys=True)
    print(json.dumps(counts))


if __name__ == "__main__":
    main()

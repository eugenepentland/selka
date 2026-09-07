#!/usr/bin/env python3
"""Behavioral replay of an existing pack; this is not a timed agent trial."""
import argparse
import base64
import hashlib
import json
import subprocess
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify(pack):
    executable = REPO / "zig-out/bin/mylang-io"
    rows = []
    for item in json.loads(pack.read_bytes()):
        case = item["case"]
        raw = (base64.b64decode(case["request_base64"], validate=True)
               if "request_base64" in case else
               json.dumps(case["request"], separators=(",", ":")).encode())
        start = time.monotonic()
        result = subprocess.run([str(executable), "--project", str(HERE)],
                                input=raw, capture_output=True, timeout=180)
        assert result.returncode == 0, (item["name"], result.stderr.decode(errors="replace"))
        assert not result.stderr, (item["name"], result.stderr)
        assert json.loads(result.stdout) == case["expected"], item["name"]
        rows.append({"name": item["name"], "accepted": True,
                     "seconds": round(time.monotonic() - start, 6),
                     "input_bytes": len(raw),
                     "board_cases": len(case.get("request", {}).get("cases", []))})
    sources = [*HERE.glob("*.my"), *(REPO / "src/stdlib").glob("*.my")]
    return {"kind": "coordinator-ergonomics-refactor", "comparative_claim": False,
            "pack_sha256": sha(pack), "byte_io_sha256": sha(executable),
            "compiler_sha256": sha(REPO / "zig-out/bin/mylang"),
            "source_sha256": {str(p.relative_to(REPO)): sha(p) for p in sorted(sources)},
            "groups": rows, "all_accepted": all(row["accepted"] for row in rows)}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("cases", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = verify(args.cases)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(f'{len(report["groups"])} groups passed; '
          f'{sum(row["board_cases"] for row in report["groups"])} board cases')

#!/usr/bin/env python3
"""Inventory golden outcomes and deterministic immutable source preparation work."""
import base64
import collections
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
harness = (ROOT / "test/golden_parity.zig").read_text()
fixtures = dict(re.findall(r'\.name = "([^"]+)", \.relative_path = "([^"]+)"', harness))
retired_keys = set(re.findall(r'"([0-9a-f]{32})"', harness.split('const per_dispatch_cases =', 1)[1].split(';', 1)[0]))
counts = collections.Counter()
payloads = []
rows = []
corpora = {}
for path in sorted((ROOT / "tests/goldens").glob("qbe_*.json")):
    raw = path.read_bytes()
    doc = json.loads(raw)
    assert doc["version"] == "golden-outcomes-v1"
    corpora[path.name] = {"sha256": hashlib.sha256(raw).hexdigest(), "entries": len(doc["entries"])}
    for key, entry in sorted(doc["entries"].items()):
        case = entry.get("case", []) if isinstance(entry, dict) else []
        label = case[0] if case and isinstance(case[0], str) else None
        options = [value for group in case[1:] if isinstance(group, list) for value in group if isinstance(value, str)] if label else []
        source = label.encode() if label and "\n" in label else (ROOT / fixtures[label]).read_bytes() if label in fixtures else None
        if source is not None:
            if key in retired_keys or "--legacy-sharing" in options or b"R_ARENA_ESCAPE" in base64.b64decode(entry.get("stderr", "")):
                kind = "retired"
            else:
                kind = "source" if "\n" in label else "fixture"
                payloads.append(source)
        elif label is None or "returncode" not in entry:
            kind = "data"
        elif path.stem == "qbe_docs" or label.startswith("docs/"):
            kind = "docs"
        else:
            kind = "unmatched"
        counts[kind] += 1
        outcome = hashlib.sha256(json.dumps(entry, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        rows.append(f"{path.stem}\t{key}\t{kind}\t{outcome}")
manifest = "corpus\tkey\tclassification\tentry_sha256\n" + "\n".join(rows) + "\n"
(OUT / "corpus-manifest.tsv").write_text(manifest)
unique = set(payloads)
summary = {"base": "fbfcaa7a923186a8e773c3760f81c10aa345a432", "counts": dict(counts), "total": len(rows), "checked": len(payloads), "distinct_checked_sources": len(unique), "source_writes_before": len(payloads), "source_writes_after": len(unique), "source_bytes_before": sum(map(len, payloads)), "source_bytes_after": sum(map(len, unique)), "compiler_launches_before_and_after": len(payloads), "fresh_work_directories_before_and_after": len(payloads), "mutable_fixture_file_writes_before_and_after": 2 * len(payloads), "manifest_sha256": hashlib.sha256(manifest.encode()).hexdigest(), "corpora": corpora}
(OUT / "corpus-work.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
print(json.dumps({key: value for key, value in summary.items() if key != "corpora"}, sort_keys=True))

#!/usr/bin/env python3
"""Export exact native-root imports and authenticate the scalar-text closure."""
from pathlib import Path
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[3]
IMPORT = re.compile(r'@import\("([^"]+)"\)')
EMBED = re.compile(r'@embedFile\("([^"]+)"\)')
TEST = re.compile(r'^test "((?:[^"\\]|\\.)*)" \{', re.M)
ROOTS = ("src/root_test.zig", "src/core/root_test.zig", "test/integration.zig",
         "src/tooling_root_test.zig", "src/text_scalar_root_test.zig")
EXPECTED = {
    "src/text_scalar_root_test.zig", "src/number_text.zig",
    "src/number_text_test.zig", "src/number_grammar.txt",
    "src/format_spec.zig", "src/format_spec_test.zig", "src/format_spec_cases.tsv",
}

def closure(entry):
    seen, pending = set(), [entry]
    while pending:
        path = pending.pop()
        if path in seen:
            continue
        seen.add(path)
        if not path.endswith('.zig'):
            continue
        text = (ROOT / path).read_text()
        for kind, names in (("import", IMPORT.findall(text)), ("embed", EMBED.findall(text))):
            for name in names:
                if kind == "import" and name == "std":
                    continue
                assert kind == "embed" or name.endswith('.zig'), (path, name)
                target = str(Path(path).parent / name)
                assert (ROOT / target).is_file(), target
                pending.append(target)
    return seen

actual = closure(ROOTS[-1])
assert actual == EXPECTED, (actual - EXPECTED, EXPECTED - actual)
named = {path: TEST.findall((ROOT / path).read_text()) for path in sorted(actual) if path.endswith('.zig')}
assert sum(map(len, named.values())) == 8, named
report = {
    "schema": "text-scalar-boundary-audit-v1",
    "roots": {path: {"direct_imports": IMPORT.findall((ROOT / path).read_text()),
                     "direct_named_tests": TEST.findall((ROOT / path).read_text()),
                     "direct_embeds": EMBED.findall((ROOT / path).read_text())} for path in ROOTS},
    "closure": [{"path": path, "sha256": hashlib.sha256((ROOT / path).read_bytes()).hexdigest()} for path in sorted(actual)],
    "named_tests": named,
    "named_count": 8,
    "unnamed_root_count": 1,
    "live_repository_reads": [],
}
print(json.dumps(report, indent=2, sort_keys=True))

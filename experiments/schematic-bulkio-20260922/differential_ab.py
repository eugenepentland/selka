#!/usr/bin/env python3
"""Malformed-input differential between two schematic guest arms.

usage: differential_ab.py <before-binary> <before.declared> <after-binary> <after.declared> <scratch> <out.json>

The mutation set is the one `experiments/full-svg-benchmark/differential.py`
defines, so the located issue codes it covers are exactly the ones this compares.
Both arms must agree on the process status, the printed result, the located issue
the provider recorded, and the published SVG bytes, for every mutant and for the
unmutated fixture.
"""
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / 'full-svg-benchmark'))
import differential as source_mutations  # noqa: E402
from measure import DOCUMENTS  # noqa: E402

# The frozen fixture projects live with the retained native comparators, which a
# lane worktree reads but never writes; `AUDIT_BENCH` names them as it does for
# the timing harness.
WORK = Path(os.environ.get('AUDIT_BENCH', '/home/epentland/ai/canopy/mylang/.tmp/full-svg-benchmark-20260921'))


def cases(scratch):
    scratch.mkdir(parents=True, exist_ok=True)
    fixture = [WORK / 'projects/fixture' / path for path in DOCUMENTS]
    out = {'fixture': fixture}
    for index, mutate in enumerate((source_mutations.mutate_module,
                                    source_mutations.mutate_pinout,
                                    source_mutations.mutate_interface)):
        for name, data in mutate(fixture[index].read_bytes()):
            path = scratch / f'{name}.sexp'
            path.write_bytes(data)
            documents = list(fixture)
            documents[index] = path
            out[name] = documents
    return out


def run(binary, declared, documents, scratch, tag):
    svg, issue = scratch / f'{tag}.svg', scratch / f'{tag}.issue'
    svg.write_bytes(b'')
    issue.write_bytes(b'')
    environment = {k: v for k, v in os.environ.items() if not k.startswith('MYLANG_')}
    environment.update(MYLANG_MEMORY_LIMIT='268435456', MYLANG_SCHEMATIC_DECLARED=declared,
                       MYLANG_SCHEMATIC_OUTPUT=str(svg), MYLANG_SCHEMATIC_ISSUE=str(issue))
    environment.update({f'MYLANG_SCHEMATIC_INPUT_{i}': str(p) for i, p in enumerate(documents)})
    result = subprocess.run([str(binary), '--print-result'], env=environment, capture_output=True, timeout=60)
    published = svg.read_bytes()
    return {'status': result.returncode, 'stdout': result.stdout.decode().strip(),
            'stderr': result.stderr.decode().strip(), 'issue': issue.read_text().strip(),
            'svg_sha256': hashlib.sha256(published).hexdigest(), 'svg_bytes': len(published)}


def main() -> None:
    before, before_declared, after, after_declared, scratch, out = (
        Path(sys.argv[1]), Path(sys.argv[2]).read_text().strip(),
        Path(sys.argv[3]), Path(sys.argv[4]).read_text().strip(),
        Path(sys.argv[5]), Path(sys.argv[6]))
    records, failures = [], []
    for name, documents in cases(scratch).items():
        a = run(before, before_declared, documents, scratch, 'before')
        b = run(after, after_declared, documents, scratch, 'after')
        agrees = a == b
        records.append({'case': name, 'agrees': agrees, 'before': a, 'after': b})
        if not agrees:
            failures.append(name)
    out.write_text(json.dumps({'passed': not failures, 'records': records}, indent=1) + '\n')
    for name in failures:
        print('FAIL', name)
    print(f'{len(records)} cases: {"all agree" if not failures else str(len(failures)) + " disagreements"}')
    raise SystemExit(1 if failures else 0)


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Archive exact emitted ownership sites for the sweep read-projection change."""
import argparse
from collections import Counter
import gzip
import hashlib
import json
from pathlib import Path
import re


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--control-dump', type=Path, required=True)
    p.add_argument('--candidate-dump', type=Path, required=True)
    p.add_argument('--control-manifest', type=Path, required=True)
    p.add_argument('--candidate-manifest', type=Path, required=True)
    p.add_argument('--control-source', type=Path, required=True)
    p.add_argument('--candidate-source', type=Path, required=True)
    p.add_argument('--out', type=Path, required=True)
    a = p.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    receipt = {'interpretation': 'Static emitted call sites, including branch cleanup paths; these are not dynamic execution counts.',
               'manifests': {}, 'units': {}}
    obj_glue = 'myl_t_a83873657e77deb1bf51281383ae925ccb1b4b6510284b93a36500031c0efc14_rcg_'
    for arm in ['control', 'candidate']:
        manifest = getattr(a, arm + '_manifest')
        dump = getattr(a, arm + '_dump')
        receipt['manifests'][arm] = {'path': str(manifest.resolve()), 'sha256': sha(manifest)}
        functions = json.loads(manifest.read_text())['functions']
        for f in functions:
            if f['name'] not in ['heap::sweep', 'heap::is_free', 'heap::object_cost_at', 'object::cost']:
                continue
            path = dump / (f['symbol'] + '.ssa')
            ssa = path.read_text()
            calls = [{'line': i, 'callee': match.group(1)}
                     for i, line in enumerate(ssa.splitlines(), 1)
                     if (match := re.search(r'call \$([^ (]+)\(', line))]
            ownership = [row for row in calls if '_rcg_' in row['callee']]
            stats = Counter(row['callee'].split('_rcg_', 1)[1] for row in ownership)
            obj_stats = Counter(row['callee'][len(obj_glue):]
                                for row in ownership if row['callee'].startswith(obj_glue))
            stem = f"{arm}-{f['name'].replace('::', '-')}.ssa.gz"
            with (a.out / stem).open('wb') as out:
                with gzip.GzipFile(fileobj=out, mode='wb', mtime=0) as z:
                    z.write(ssa.encode())
            receipt['units'][arm + '/' + f['name']] = {
                'symbol': f['symbol'], 'ssa_sha256': sha(path), 'ssa_lines': len(ssa.splitlines()),
                'archive': stem, 'archive_sha256': sha(a.out / stem),
                'ownership_calls': dict(sorted(stats.items())),
                'obj_ownership_calls': dict(sorted(obj_stats.items())),
                'ownership_sites': ownership,
                'fail_calls': [row for row in calls if row['callee'].startswith('myl_qbe_fail_')]}
    original = (a.control_source / 'object.my').read_text().split('public def cost(', 1)[1].split('public def new_function', 1)[0]
    scalar = (a.candidate_source / 'heap.my').read_text().split('def object_cost_at(', 1)[1].split('def sweep', 1)[0]
    returns = lambda body: re.findall(r'^\s+return (.+)$', body, flags=re.M)
    assert returns(original) == returns(scalar)
    receipt['cost_return_expressions'] = returns(original)
    receipt['cost_return_expressions_preserved'] = True
    (a.out / 'ownership.json').write_text(json.dumps(receipt, indent=2) + '\n')


if __name__ == '__main__':
    main()

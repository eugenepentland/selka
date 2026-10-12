#!/usr/bin/env python3
"""Freeze verified five-arm baseline or six-arm candidate comparison specs."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
BENCH = Path(__file__).resolve().parents[1]
FOREIGN = ('zig-safe', 'zig-fast', 'rust', 'go')
CASES = ('string_split', 'json_transform', 'csv_aggregate')


def digest(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def load(p):
    return json.loads(Path(p).read_text())


def verify(entry, manifest=None):
    assert entry['status'] in ('ok', 'built'), entry
    assert digest(entry['binary']) == entry['sha256'], entry['binary']
    source = Path(entry['source'])
    source_hash = digest(source)
    if 'source_sha256' in entry:
        assert source_hash == entry['source_sha256'], source
    if manifest:
        relative = str(source.relative_to(manifest['source_root']))
        frozen = manifest['sources'][relative]
        assert source_hash == frozen['sha256'] == digest(ROOT / frozen['canonical']), source
        matched = [e for e in manifest['entries'] if e['binary'] == entry['binary']]
        assert len(matched) == 1 and matched[0]['sha256'] == entry['sha256']
        assert matched[0]['flags'] == entry['flags'], entry['binary']
    return {**entry, 'status': 'ok', 'source_sha256': source_hash}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--run', required=True)
    p.add_argument('--baseline-manifest', type=Path, default=ROOT / 'experiments/micro-gaps-20261012/coordinator/builds.json')
    p.add_argument('--candidate-runtime', type=Path)
    p.add_argument('--candidate-counted', type=Path)
    p.add_argument('--candidate-manifest', type=Path)
    a = p.parse_args()
    assert a.run and '/' not in a.run and a.run not in ('.', '..')
    run = BENCH / 'runs' / a.run
    assert not run.exists(), 'never overwrite an evidence run'
    baseline = load(a.baseline_manifest)
    assert digest(baseline['compiler']) == baseline['compiler_sha256']
    assert baseline['compiler_sha256'] == 'ec423f5ff7dba37f5d39489fec12b9c851754c0ad69125fc8aaafe85e31ea44e'
    old = ROOT / 'experiments/micro-ownership-20261012'
    reference_path = old / 'references/manifest.json'
    references = load(reference_path)
    entries = [e for e in baseline['entries'] if Path(e['binary']).name in ('expanded-text-runtime', 'expanded-text-counted')]
    assert len(entries) == 2
    base = {e['kind']: {**verify(e), 'zero_rc': True} for e in entries}
    candidate = None
    if any((a.candidate_runtime, a.candidate_counted, a.candidate_manifest)):
        assert all((a.candidate_runtime, a.candidate_counted, a.candidate_manifest)), 'candidate requires both binaries and build manifest'
        m = load(a.candidate_manifest)
        assert digest(m['compiler']) == m['compiler_sha256']
        candidate = {}
        for kind, binary in (('runtime', a.candidate_runtime), ('counted', a.candidate_counted)):
            found = [e for e in m['entries'] if Path(e['binary']).resolve() == binary.resolve()]
            assert len(found) == 1
            candidate[kind] = {**verify(found[0]), 'zero_rc': True}
            assert candidate[kind]['source_sha256'] == base[kind]['source_sha256'], 'benchmark contract changed'
    pinned = {str(a.baseline_manifest.resolve()), str(reference_path.resolve()), baseline['compiler']}
    if candidate:
        pinned |= {str(a.candidate_manifest.resolve()), m['compiler']}
    specs = []
    for case in CASES:
        for profile in ('small', 'large'):
            original = old / f'specs-expanded/{case}.{profile}.json'
            spec = load(original)
            foreign = {name: verify(spec['arms'][name], references) for name in FOREIGN}
            spec['arms'] = {'checked-baseline': base['runtime'], **({'checked-candidate': candidate['runtime']} if candidate else {}), **foreign}
            spec['counted'] = {'checked-baseline': base['counted'], **({'checked-candidate': candidate['counted']} if candidate else {})}
            spec['files'] = sorted(set(spec['files']) | pinned | {str(original.resolve()), str(ROOT / 'benchmarks/runtime/expanded/registry.py'), str(Path(__file__).resolve()), str(Path(__file__).with_name('measure.py').resolve())})
            for entry in list(spec['arms'].values()) + list(spec['counted'].values()):
                spec['files'].append(entry['source'])
                flags = entry['flags']
                for index, flag in enumerate(flags):
                    if flag == '--link':
                        linked = flags[index + 1]
                        assert digest(linked) == digest(ROOT / 'benchmarks/runtime/ports/native_clock.c'), 'changed native clock'
                        spec['files'].append(linked)
            for path in references['sources']:
                if '/sources/text/' in path:
                    frozen = references['sources'][path]
                    source = Path(references['source_root']) / path
                    assert digest(source) == frozen['sha256']
                    spec['files'].append(str(source))
            spec['files'] = sorted(set(spec['files']))
            spec['cell'] = f'text-gaps/{a.run}/{case}/{profile}' 
            spec['provenance'] = {'old_spec': str(original), 'old_spec_sha256': digest(original), 'reference_manifest_sha256': digest(reference_path), 'baseline_compiler_sha256': baseline['compiler_sha256'], 'foreign_reused': True, 'timing_fresh': True}
            specs.append((f'{case}.{profile}.json', spec))
    # All inputs validated before reserving the new evidence destination.
    (run / 'specs').mkdir(parents=True)
    for name, spec in specs:
        (run / 'specs' / name).write_text(json.dumps(spec, indent=2) + '\n')
    print(run)


if __name__ == '__main__':
    main()

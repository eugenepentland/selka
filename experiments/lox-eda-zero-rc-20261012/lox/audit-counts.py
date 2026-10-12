#!/usr/bin/env python3
"""Run three frozen counted Lox arms on all 26 normal smoke workloads."""
from pathlib import Path
import argparse
import hashlib
import gzip
import json
import os
import subprocess


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--binaries', type=Path, required=True)
    p.add_argument('--bench', type=Path, required=True)
    p.add_argument('--work', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    binaries = json.loads(args.binaries.read_text())['binaries']
    sizes = json.loads((args.bench / 'sizes.json').read_text())
    args.work.mkdir(parents=True, exist_ok=True)
    args.output.mkdir(parents=True, exist_ok=True)
    rows = []
    for script in sorted((args.bench / 'scripts').glob('*.lox')):
        first, rest = script.read_text().split('\n', 1)
        assert first.startswith('var N = '), script
        source = f"var N = {sizes[script.stem]['smoke']};\n" + rest
        prepared = args.work / script.name
        prepared.write_text(source)
        expected = (args.bench / 'expected' / f'{script.stem}.smoke.out').read_bytes()
        for engine in ['vm', 'tree']:
            for arm in ['original-rc', 'migrated-rc', 'zero']:
                binary = binaries[arm + '-counted']
                assert hashlib.sha256(Path(binary['path']).read_bytes()).hexdigest() == binary['sha256']
                name = f'{arm}-{engine}-{script.stem}'
                path = (args.output / (name + '.json')).resolve()
                env = dict(os.environ, MYLANG_COUNTERS=str(path), MYL_CORE_LEAKCHECK='1')
                cmd = [binary['path'], '--engine=' + engine, str(prepared.resolve())]
                compressed = path.with_suffix('.json.gz')
                cached = compressed.exists()
                if cached:
                    raw_counts = gzip.decompress(compressed.read_bytes())
                    stdout = (args.output / (name + '.stdout')).read_bytes()
                    stderr = (args.output / (name + '.stderr')).read_bytes()
                    assert stdout == expected and not stderr, name
                else:
                    proc = subprocess.run(cmd, env=env, capture_output=True, timeout=120)
                    (args.output / (name + '.stdout')).write_bytes(proc.stdout)
                    (args.output / (name + '.stderr')).write_bytes(proc.stderr)
                    assert proc.returncode == 0 and proc.stdout == expected and not proc.stderr, name
                    raw_counts = path.read_bytes()
                    compressed.write_bytes(gzip.compress(raw_counts, mtime=0))
                    path.unlink()
                counts = json.loads(raw_counts)
                totals = counts['totals']
                kinds = counts['kinds']
                managed = {key: kinds.get(key, {}).get('count', 0) for key in ['retain', 'release', 'unique_test']}
                if arm == 'zero':
                    assert not any(managed.values()), (name, managed)
                    assert totals['runtime_retains'] == totals['runtime_releases'] == 0, name
                    assert totals['shared_retains'] == totals['shared_releases'] == 0, name
                assert totals['live_bytes_at_exit'] == 0, name
                rows.append({'arm': arm, 'engine': engine, 'case': script.stem, 'n': sizes[script.stem]['smoke'], 'input_sha256': hashlib.sha256(source.encode()).hexdigest(), 'command': cmd, 'counts_file': str(compressed.resolve()), 'counts_sha256': hashlib.sha256(raw_counts).hexdigest(), 'binary_sha256': binary['sha256'], 'managed': managed, 'direct_destructions': kinds.get('release_unique', {}).get('count', 0), 'totals': totals, 'cached_raw_artifact': cached})
                print(name + ': ok', flush=True)
    (args.output / 'summary.json').write_text(json.dumps({'rows': rows}, indent=2) + '\n')


if __name__ == '__main__':
    main()

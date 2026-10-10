#!/usr/bin/env python3
"""Interleave release guest compile times with compiler-isolated warm runtimes."""
import argparse
import json
from pathlib import Path
import random
import resource
import shutil
import statistics
import sys
import time

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'experiments/runtime-parity-3-20261009/tools'))
import ce


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--base', type=Path, required=True)
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    rows = []
    rng = random.Random(20261010)
    for name, source, cwd in [('lox', ce.LOX_SRC / 'main.my', ce.LOX_SRC), ('eda', ce.EDA_SRC / 'src/main.my', ce.EDA_SRC)]:
        for round_no in range(4):
            order = [('base', args.base), ('u2', args.candidate)]
            rng.shuffle(order)
            for tag, compiler in order:
                lane = ce.Lane(compiler, 'compile-' + tag)
                root = ROOT / '.mylang-cache/u2/compile-fresh' / tag / name / str(round_no)
                if root.exists():
                    raise RuntimeError(f"Fresh compile cache required: {root}")
                root.mkdir(parents=True)
                runtime = root / 'runtime'
                runtime.mkdir()
                # Runtime and guest units share a parent store. Copy only the
                # runtime files, never units-v1: a fresh --cache-dir alone
                # would still reuse guest LLVM objects from the shared store.
                for artifact in lane.runtime_cache.iterdir():
                    if artifact.is_file():
                        shutil.copy2(artifact, runtime / artifact.name)
                output = root / name
                command = [compiler.resolve(), 'build', source, '--release', '-o', output, '--cache-dir', root / 'cache', '--cache-report']
                before = resource.getrusage(resource.RUSAGE_CHILDREN)
                started = time.monotonic()
                status, stdout, stderr = ce.run(command, cwd=cwd, extra_env={'MYLANG_CORE_RUNTIME_CACHE': str(runtime)})
                wall = time.monotonic() - started
                after = resource.getrusage(resource.RUSAGE_CHILDREN)
                row = {'program': name, 'tag': tag, 'round': round_no, 'status': status, 'wall_seconds': wall,
                    'cpu_seconds': after.ru_utime + after.ru_stime - before.ru_utime - before.ru_stime,
                    'compiler_sha256': ce.digest(compiler), 'binary_sha256': ce.digest(output) if output.exists() else None,
                    'runtime_cache': str(runtime.relative_to(ROOT)), 'stderr': stderr.decode()[-2000:]}
                rows.append(row)
                if status:
                    args.out.write_text(json.dumps({'rows': rows}, indent=1) + '\n')
                    raise RuntimeError(str(row))
                print(name, tag, round_no, wall, flush=True)
    medians = {}
    for name in ('lox', 'eda'):
        values = {tag: {metric: statistics.median(row[metric] for row in rows if row['program'] == name and row['tag'] == tag and row['round'] > 0)
                       for metric in ('wall_seconds', 'cpu_seconds')} for tag in ('base', 'u2')}
        medians[name] = {'median': values, 'ratios': {metric: values['u2'][metric] / values['base'][metric] for metric in values['base']}}
    args.out.write_text(json.dumps({'method': 'Every round uses a fresh program cache and fresh units-v1 store. Only compiler-isolated runtime files are prewarmed. Round0 is excluded; rounds1–3 interleave compilers on identical source within one build slot.', 'medians': medians, 'rows': rows}, indent=1) + '\n')


if __name__ == '__main__':
    main()

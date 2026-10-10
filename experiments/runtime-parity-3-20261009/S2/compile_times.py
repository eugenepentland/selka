#!/usr/bin/env python3
"""Interleave EDA/Lox release builds with fresh guest caches and hash-owned runtimes."""
import argparse
import hashlib
import json
from pathlib import Path
import random
import shutil
import statistics
import sys
import time

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'experiments/runtime-parity-3-20261009/tools'))
import ce

p = argparse.ArgumentParser()
p.add_argument('--candidate', type=Path, required=True)
p.add_argument('--out', type=Path, required=True)
p.add_argument('--rounds', type=int, default=3)
a = p.parse_args()
base = Path('/home/epentland/.cache/mylang/rp3-base-41ed360fb/bin/mylang')
lanes = {'base': ce.Lane(base, 'base'), 's2': ce.Lane(a.candidate, 's2')}
work = ROOT / '.mylang-cache/rp3/s2-compile-times'
work.mkdir(parents=True, exist_ok=True)
rows = []
rng = random.Random(20261010)
for repeat in range(-1, a.rounds):
    jobs = [(tag, name, cwd, source) for tag in lanes for name, cwd, source in
            [('eda', ce.EDA_SRC, ce.EDA_SRC / 'src/main.my'), ('lox', ce.LOX_SRC, ce.LOX_SRC / 'main.my')]]
    rng.shuffle(jobs)
    for tag, name, cwd, source in jobs:
        lane = lanes[tag]
        run = work / f'{repeat}-{tag}-{name}'
        run.mkdir()
        runtime = run / 'runtime'
        runtime.mkdir()
        artifacts = []
        for artifact in lane.runtime_cache.iterdir():
            if artifact.is_file():
                shutil.copy2(artifact, runtime / artifact.name)
                artifacts.append({'name': artifact.name, 'sha256': ce.digest(artifact)})
        assert artifacts and not (runtime / 'units-v1').exists()
        output = run / 'program'
        command = [lane.compiler, 'build', source, '-o', output, '--release', '--cache-dir', run / 'cache', '--cache-report']
        start = time.monotonic()
        status, stdout, stderr = ce.run(command, cwd=cwd, extra_env={'MYLANG_CORE_RUNTIME_CACHE': str(runtime)}, slot=False)
        seconds = time.monotonic() - start
        (run / 'stdout').write_bytes(stdout)
        (run / 'stderr').write_bytes(stderr)
        rows.append({'round': repeat, 'tag': tag, 'program': name, 'seconds': seconds, 'status': status,
                     'command': list(map(str, command)), 'compiler_sha256': ce.digest(lane.compiler),
                     'binary_sha256': ce.digest(output) if output.exists() else None,
                     'stderr_sha256': hashlib.sha256(stderr).hexdigest(), 'scratch': str(run),
                     'runtime_seed': artifacts, 'cache_report': stderr.decode(errors='replace').splitlines(),
                     'guest_unit_objects': len(list((runtime / 'units-v1').glob('*.o')))})
        a.out.write_text(json.dumps({'samples': rows}, indent=1) + '\n')
        print(name, tag, repeat, status, seconds, flush=True)
        if status:
            raise RuntimeError(stderr.decode()[-3000:])
summary = {}
for name in ('eda', 'lox'):
    times = {tag: [row['seconds'] for row in rows if row['program'] == name and row['tag'] == tag and row['round'] >= 0] for tag in lanes}
    medians = {tag: statistics.median(values) for tag, values in times.items()}
    summary[name] = {'samples_seconds': times, 'median_seconds': medians, 'ratio': medians['s2'] / medians['base']}
a.out.write_text(json.dumps({'method': 'ReleaseFast compilers; shuffled interleaved release guest builds; fresh front-end/semantic/native-unit/program stores per arm, copying only compiler-hash runtime cache top-level files (no units-v1 directory); --cache-report retained; one unmeasured warm-up per compiler/program; one outer shared build slot, CPUs2/3/10/11 excluded; shared-machine compile-time noise remains.', 'summary': summary, 'samples': rows}, indent=1) + '\n')

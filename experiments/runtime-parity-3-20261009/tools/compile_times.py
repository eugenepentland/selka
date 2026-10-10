#!/usr/bin/env python3
"""Compare release guest compile times with warm runtimes and fresh guest stores.

Run inside scripts/build-slot.sh build. No units-v1 files are copied from the
runtime seed; every cache report must prove that the guest was recompiled.
"""
import argparse
import json
import os
from pathlib import Path
import random
import re
import resource
import shutil
import statistics
import time

import ce


def fresh_report(stderr):
    reports = re.findall(r'mylang-core: cache: (\d+) units, (\d+) reused, (\d+) compiled, '
                         r'(\d+) verified; program (\w+); (\d+) processes', stderr)
    if reports != [('1', '0', '1', '0', 'linked', '2')]:
        raise RuntimeError('Expected one freshly compiled guest unit: ' + stderr)
    return reports[0]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--base', type=Path, required=True)
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--tag', required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    slot = os.readlink('/proc/self/fd/9')
    if not re.fullmatch(r'/run/user/\d+/mylang-slots/build\d+\.lock', slot):
        raise RuntimeError('Run inside scripts/build-slot.sh build')
    if not re.fullmatch('[a-z0-9-]+', args.tag):
        raise ValueError('tag must contain lowercase letters, digits and hyphens')
    os.sched_setaffinity(0, os.sched_getaffinity(0) - {2, 3, 10, 11})
    compilers = {'base': args.base.resolve(), 'candidate': args.candidate.resolve()}
    identities = {tag: ce.digest(compiler) for tag, compiler in compilers.items()}
    work = ce.ROOT / '.mylang-cache/rp3/compile-times' / args.tag
    work.mkdir(parents=True, exist_ok=False)
    lanes = {tag: ce.Lane(compiler, 'compile-' + tag) for tag, compiler in compilers.items()}
    rows = []
    result = {'complete': False, 'source_commit': ce.run(['git', 'rev-parse', 'HEAD'])[1].decode().strip(),
              'compiler_sha256': identities, 'samples': rows,
              'method': 'One excluded warmup and three measured rounds, shuffled across both compilers and programs. '
                        'Every arm gets fresh guest front-end/unit/program stores and only compiler-hash runtime '
                        'top-level seed files. Cache reports must show one compiled unit, zero reuse and a linked '
                        'program. All builds are serial within one admitted build slot. Shared-machine load can '
                        'affect wall time; child CPU time is retained separately.'}
    rng = random.Random(20261010)
    sources = {'lox': (ce.LOX_SRC / 'main.my', ce.LOX_SRC),
               'eda': (ce.EDA_SRC / 'src/main.my', ce.EDA_SRC)}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    for round_no in range(4):
        order = [(tag, program) for tag in lanes for program in sources]
        rng.shuffle(order)
        for tag, program in order:
            lane = lanes[tag]
            source, cwd = sources[program]
            run = work / f'{round_no}-{tag}-{program}'
            runtime = run / 'runtime'
            runtime.mkdir(parents=True)
            artifacts = []
            for artifact in sorted(lane.runtime_cache.iterdir()):
                if artifact.is_file():
                    shutil.copy2(artifact, runtime / artifact.name)
                    artifacts.append({'name': artifact.name, 'sha256': ce.digest(artifact)})
            if not artifacts or (runtime / 'units-v1').exists():
                raise RuntimeError('Warm runtime seed required, without guest units: ' + str(runtime))
            command = [lane.compiler, 'build', source, '--release', '-o', run / 'program',
                       '--cache-dir', run / 'cache', '--cache-report']
            before = resource.getrusage(resource.RUSAGE_CHILDREN)
            started = time.monotonic()
            status, stdout, stderr = ce.run(command, cwd=cwd,
                                           extra_env={'MYLANG_CORE_RUNTIME_CACHE': str(runtime)})
            wall = time.monotonic() - started
            after = resource.getrusage(resource.RUSAGE_CHILDREN)
            (run / 'stdout').write_bytes(stdout)
            (run / 'stderr').write_bytes(stderr)
            row = {'round': round_no, 'tag': tag, 'program': program, 'status': status,
                   'wall_seconds': wall,
                   'cpu_seconds': after.ru_utime + after.ru_stime - before.ru_utime - before.ru_stime,
                   'command': list(map(str, command)), 'cwd': str(cwd), 'runtime_seed': artifacts,
                   'cache_report': stderr.decode(errors='replace'),
                   'scratch': str(run.relative_to(ce.ROOT)),
                   'binary_sha256': ce.digest(run / 'program') if (run / 'program').exists() else None}
            rows.append(row)
            args.out.write_text(json.dumps(result, indent=1) + '\n')
            if status:
                raise RuntimeError(str(row))
            fresh_report(row['cache_report'])
            assert ce.digest(lane.compiler) == identities[tag]
            print(program, tag, round_no, wall, flush=True)
    summary = {}
    for program in sources:
        medians = {tag: {metric: statistics.median(row[metric] for row in rows
                        if row['program'] == program and row['tag'] == tag and row['round'] > 0)
                        for metric in ('wall_seconds', 'cpu_seconds')} for tag in lanes}
        ratio = {metric: medians['candidate'][metric] / medians['base'][metric]
                 for metric in ('wall_seconds', 'cpu_seconds')}
        summary[program] = {'medians': medians, 'candidate_over_base': ratio,
                            'above_1_10_wall': ratio['wall_seconds'] > 1.10}
    result.update(complete=True, summary=summary)
    args.out.write_text(json.dumps(result, indent=1) + '\n')


if __name__ == '__main__':
    main()

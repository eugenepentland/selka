#!/usr/bin/env python3
"""Build plain/counting corpus binaries serially inside one shared build slot.

A resume manifest may name completed, hash-verified binaries from the same
compiler. All other jobs build normally. Output gates run after this step.
"""
import argparse
import json
import os
from pathlib import Path
import time

import ce


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--tag', required=True)
    parser.add_argument('--resume', type=Path)
    args = parser.parse_args()
    admission = Path(os.readlink('/proc/self/fd/9'))
    if not admission.name.startswith('build') or admission.suffix != '.lock':
        raise RuntimeError('launch through scripts/build-slot.sh build')
    resume = json.loads(args.resume.read_text()) if args.resume else {}
    if resume:
        assert ce.digest(args.compiler) == resume['compiler_sha256']
    lane = ce.Lane(args.compiler, args.tag)
    lane.bins.mkdir(parents=True, exist_ok=True)
    jobs = [('lox', ce.LOX_SRC / 'main.my', ce.LOX_SRC, ()),
            ('eda', ce.EDA_SRC / 'src/main.my', ce.EDA_SRC, ())]
    jobs += [('parity-' + name, ce.ROOT / ('bench/parity/' + path + '.my'), ce.ROOT, ()) for name, path in ce.PARITY.items()]
    clock = ce.ROOT / 'benchmarks/runtime/ports/native_clock.c'
    jobs += [('row-' + name, source, ce.ROOT, (clock,)) for name, source in ce.row_sources().items()]
    built = reused = 0
    for label, source, cwd, links in jobs:
        for kind, counting in (('plain', False), ('count', True)):
            output = lane.bins / (label + '-' + kind)
            expected = resume.get('binaries', {}).get(output.name)
            if expected:
                assert output.is_file() and ce.digest(output) == expected, output
                reused += 1
                continue
            command = [lane.compiler, 'build', source, '-o', output, '--cache-dir', lane.cache, '--release']
            if counting:
                command.append('--counters')
            for link in links:
                command += ['--link', link]
            started = time.monotonic()
            status, _, error = ce.run(command, cwd=cwd,
                                      extra_env={'MYLANG_CORE_RUNTIME_CACHE': str(lane.runtime_cache)}, slot=False)
            if status or not output.is_file():
                raise RuntimeError(f'{label}/{kind}: {status}: {error.decode(errors="replace")[-3000:]}')
            built += 1
            print(f'built {output.name} in {time.monotonic() - started:.2f}s', flush=True)
    assert built + reused == 186, (built, reused)
    print(f'counting builds complete: {built} built, {reused} hash-verified retained; all 186 binaries present', flush=True)


if __name__ == '__main__':
    main()

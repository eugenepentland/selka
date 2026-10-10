#!/usr/bin/env python3
"""Measure complete warm dump-tokens reference/shadow exchanges after isolated admission.

Build beforehand through admission. Run this script only while the root coordinator
holds isolated timing admission, pinned to reserved timing CPUs. Builds/gates must
remain stopped for its duration. This script does not build anything.
"""
import argparse
import json
import os
from pathlib import Path
import statistics
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--component-dir', type=Path, required=True)
    parser.add_argument('--iterations', type=int, default=20)
    parser.add_argument('--isolated', action='store_true', help='assert coordinator granted isolated timing admission')
    args = parser.parse_args()
    if not args.isolated or args.iterations < 3:
        parser.error('requires explicit isolated admission and at least three iterations')
    compiler = args.compiler.resolve()
    environment = dict(os.environ, MYLANG_COMPONENT_DIR=str(args.component_dir.resolve()))
    with tempfile.TemporaryDirectory(prefix='lexer-timing-') as directory:
        path = Path(directory)/'source.lex'
        for name, source in [('small', b'func main() -> int:\n    return 42\n'),
                             ('64KiB-comments', b'#' + b'x' * 65535),
                             ('64KiB-token-rich', b'a ' * 32768)]:
            path.write_bytes(source)
            command = [str(compiler), 'dump-tokens', str(path), '--diagnostics=json']
            outputs = {}
            timings = {}
            for mode in ('reference', 'shadow'):
                env = dict(environment, MYLANG_LEXER_MODE=mode)
                warm = subprocess.run(command, env=env, capture_output=True, timeout=30)
                if warm.returncode:
                    raise RuntimeError(warm.stderr.decode(errors='replace'))
                samples = []
                for _ in range(args.iterations):
                    start = time.perf_counter_ns()
                    result = subprocess.run(command, env=env, capture_output=True, timeout=30)
                    samples.append((time.perf_counter_ns() - start) / 1000000)
                    if (result.returncode, result.stdout, result.stderr) != (warm.returncode, warm.stdout, warm.stderr):
                        raise RuntimeError('nonrepeatable correctness during timing')
                outputs[mode] = warm.stdout
                timings[mode] = statistics.median(samples)
            if outputs['reference'] != outputs['shadow']:
                raise RuntimeError('reference/shadow output mismatch')
            print(json.dumps({'fixture': name, 'source_bytes': len(source),
                              'host_output_bytes': len(outputs['shadow']),
                              'iterations': args.iterations, 'median_ms': timings,
                              'added_ms': timings['shadow'] - timings['reference']}))


if __name__ == '__main__':
    main()

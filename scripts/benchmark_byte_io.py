"""Measure identical binary round trips including project checking and process startup."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import statistics
import subprocess
import tempfile
import time

IO = ('\n\n\n'
      'public class Block:\n    bytes: [256]u8\n    count: i64\n\n\n'
      'host func length() -> i64 effects(host)\n\n\n'
      'host func byte(index: i64) -> u8 effects(host)\n\n\n'
      'host func put(value: u8) -> i64 effects(host)\n\n\n'
      'host func read_block(offset: i64) -> Block effects(host)\n\n\n'
      'host func write_block(block: Block) -> i64 effects(host)\n')
SOURCES = {
    'scalar': ('func main() -> i64:\n    mut size = io.length()\n    mut i = 0\n    while i < size:\n        _ = io.put(io.byte(i))\n        i += 1\n    return 0\n'),
    'block256': ('func main() -> i64:\n    mut size = io.length()\n    mut i = 0\n    while i < size:\n        mut block = io.read_block(i)\n        mut count = block.count\n        if io.write_block(block) != count:\n            return 1\n        i += count\n    return 0\n'),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runner', required=True, type=Path)
    parser.add_argument('--bytes', type=int, default=65539)
    parser.add_argument('--repetitions', type=int, default=5)
    args = parser.parse_args()
    if args.bytes < 1 or args.repetitions < 1:
        parser.error('bytes and repetitions must be positive')
    runner = args.runner.resolve()
    payload = bytes(i % 256 for i in range(args.bytes))
    report = {'version': 'byte-io-benchmark-v1', 'platform': platform.platform(),
              'runner_sha256': hashlib.sha256(runner.read_bytes()).hexdigest(),
              'input_bytes': len(payload), 'input_sha256': hashlib.sha256(payload).hexdigest(),
              'measurement': 'end-to-end subprocess; includes source checking, VM execution, and copied stdin/stdout',
              'samples_seconds': {}, 'median_seconds': {}, 'callback_limit': {}}
    with tempfile.TemporaryDirectory(prefix='byte-io-benchmark-') as directory:
        root = Path(directory)
        (root / 'io.selka').write_text(IO)
        for mode, source in SOURCES.items():
            (root / 'main.selka').write_text('' + source)
            count = 2 * (len(payload) if mode == 'scalar' else (len(payload) + 255) // 256) + 1
            command = [str(runner), '--project', str(root), f'--max-calls={count}']
            samples = []
            for _ in range(args.repetitions):
                start = time.perf_counter()
                result = subprocess.run(command, input=payload, capture_output=True, timeout=120)
                samples.append(time.perf_counter() - start)
                if result.returncode or result.stdout != payload:
                    raise RuntimeError(f'{mode} round trip failed: {result.stderr!r}')
            report['samples_seconds'][mode] = samples
            report['median_seconds'][mode] = statistics.median(samples)
            report['callback_limit'][mode] = count
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == '__main__':
    main()

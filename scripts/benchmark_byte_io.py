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

IO = ('module io;export length;export byte;export put;export Block;export read_block;export write_block;'
      'struct Block{bytes:[256]u8,count:i64}'
      'host fn length()->i64 effects(host);host fn byte(index:i64)->u8 effects(host);'
      'host fn put(value:u8)->i64 effects(host);host fn read_block(offset:i64)->Block effects(host);'
      'host fn write_block(block:Block)->i64 effects(host);')
SOURCES = {
    'scalar': ('fn main()->i64{let size=io::length();let mut i=0;'
               'while i<size{_ = io::put(io::byte(i));i+=1;}return 0;}'),
    'block256': ('fn main()->i64{let size=io::length();let mut i=0;while i<size{'
                 'let block=io::read_block(i);let count=block.count;'
                 'if io::write_block(block)!=count{return 1;}i+=count;}return 0;}'),
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
        (root / 'io.my').write_text(IO)
        for mode, source in SOURCES.items():
            (root / 'main.my').write_text('module main;import io;' + source)
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

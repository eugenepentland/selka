"""Run independent numeric batches through copied, schema-pinned worker messages."""
import argparse
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from workers import Pool, canonical, schema_identity


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', type=Path, default=ROOT / 'zig-out/bin/mylang')
    args = parser.parse_args()
    sources = {'main.my': Path(__file__).with_name('main.my').read_bytes()}
    with Pool(args.compiler, directory=ROOT / '.zig-cache') as pool:
        schema = pool.schema(sources)
        if schema.state != 'succeeded':
            raise RuntimeError(schema.diagnostics.decode(errors='replace'))
        identity = schema_identity(schema.output)
        jobs = [pool.submit(sources, canonical({
            'version': 'typed-call-v1', 'schema_sha256': identity, 'function': 'main::analyze',
            'arguments': {'values': [str(n) for n in range(start, start + 4)]},
        })) for start in [1, 5, 9, 13]]
        combined = {'sum': 0, 'squares': 0}
        for job in jobs:
            result = pool.wait(job)
            if result.state != 'succeeded':
                raise RuntimeError(result.state + ': ' + result.diagnostics.decode(errors='replace'))
            for key, value in json.loads(result.output)['value'].items():
                combined[key] += int(value)
        print(json.dumps(combined))


if __name__ == '__main__':
    main()

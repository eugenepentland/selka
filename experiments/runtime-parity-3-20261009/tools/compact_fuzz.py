#!/usr/bin/env python3
"""Compress completed fuzz workers' raw JSON journals without changing summaries."""
import argparse
import collections
import gzip
import hashlib
import json
from pathlib import Path
import shutil
import tarfile

AREA = Path(__file__).resolve().parents[1]
ROOT = AREA.parents[1]


def summarize_commands(area):
    directory = area.resolve()
    if not directory.is_relative_to(AREA):
        raise ValueError('only this wave\'s owned evidence may be compacted')
    matrix = json.loads((directory / 'matrix.json').read_text())
    assert matrix['qualified'] and matrix['source_unchanged'] and matrix['oracles_unchanged']
    archive = ROOT / '.mylang-cache/rp3/fuzz-journals' / directory.relative_to(AREA)
    for kind, outcome in matrix['kinds'].items():
        summary = outcome['summary']
        assert outcome['passed'] and summary['qualified'] and summary['complete']
        assert not summary['failures'] and summary['native_complete']
        source = directory / kind / 'commands.jsonl.gz'
        if not source.exists():
            raise FileNotFoundError(source)
        counts = collections.Counter()
        sources = set()
        uncompressed = hashlib.sha256()
        size = rows = 0
        with gzip.open(source, 'rb') as stream:
            for line in stream:
                uncompressed.update(line)
                size += len(line)
                row = json.loads(line)
                counts[(row.get('role'), row.get('building'), str(row['status']))] += 1
                if row.get('source'):
                    sources.add(row['source'])
                rows += 1
        assert rows == summary['command_count'], (kind, rows, summary['command_count'])
        target = archive / kind / source.name
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.exists():
            raise FileExistsError(target)
        sha = hashlib.sha256(source.read_bytes()).hexdigest()
        shutil.copy2(source, target)
        assert hashlib.sha256(target.read_bytes()).hexdigest() == sha
        receipt = {'method': 'Completed command journal retained in owned cache; matrix.json retains every family\'s native comparison and qualification totals. No failed or incomplete run is compacted.',
                   'command_count': rows, 'source_paths': len(sources),
                   'counts': [{'role': role, 'building': building, 'status': status, 'count': count}
                              for (role, building, status), count in sorted(counts.items(), key=lambda pair: str(pair[0]))],
                   'uncompressed_bytes': size, 'uncompressed_sha256': uncompressed.hexdigest(),
                   'gzip_sha256': sha, 'raw_scratch': str(target.relative_to(ROOT)),
                   'worker_qualified': summary['qualified'], 'native_complete': summary['native_complete']}
        (source.parent / 'commands-summary.json').write_text(json.dumps(receipt, indent=1) + '\n')
        source.unlink()
    print('completed command journals summarized and retained in', archive)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('area', type=Path)
    parser.add_argument('--summarize-commands', action='store_true')
    args = parser.parse_args()
    total = 0
    for log in args.area.glob('*.txt'):
        if not log.read_text().endswith('\nexit=0\n'):
            continue
        kind = args.area / log.stem
        for path in kind.glob('*.jsonl'):
            target = path.with_suffix(path.suffix + '.gz')
            with path.open('rb') as source, gzip.open(target, 'wb', compresslevel=9) as dest:
                shutil.copyfileobj(source, dest)
            total += path.stat().st_size - target.stat().st_size
            path.unlink()
        sources = kind / 'sources'
        if sources.is_dir():
            with tarfile.open(kind / 'sources.tar.gz', 'w:gz') as archive:
                archive.add(sources, arcname='sources')
            shutil.rmtree(sources)
    print('completed journals and source archives compressed; journal bytes saved:', total)
    if args.summarize_commands:
        summarize_commands(args.area)


if __name__ == '__main__':
    main()

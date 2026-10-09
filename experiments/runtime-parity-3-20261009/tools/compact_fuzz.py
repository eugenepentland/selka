#!/usr/bin/env python3
"""Compress completed fuzz workers' raw JSON journals without changing summaries."""
import argparse
import gzip
from pathlib import Path
import shutil
import tarfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('area', type=Path)
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


if __name__ == '__main__':
    main()

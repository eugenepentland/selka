#!/usr/bin/env python3
"""Declaration listings account for every byte of every example and experiment module."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
ENTRY = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*$')
# index-project checks a whole module graph and hashes the running executable, so
# the symbol comparison uses representative projects rather than every file.
INDEXED = ('examples/modules/main.my', 'src/schematic/guest/main.my')


def listing(compiler, path):
    result = subprocess.run([compiler, 'list-declarations', str(path)], capture_output=True, text=True, timeout=60)
    return result


def trivia_only(text):
    """Whitespace and # line comments are the only bytes permitted outside listed ranges."""
    at = 0
    while at < len(text):
        if text[at].isspace():
            at += 1
        elif text.startswith('#', at):
            newline = text.find('\n', at)
            at = len(text) if newline < 0 else newline
        else:
            return False
    return True


def check(path, document):
    source = path.read_text(encoding='utf-8')
    ranges = []
    if document['header'] is not None:
        ranges.append((document['header']['start'], document['header']['end'], 'header'))
    for imported in document['imports']:
        ranges.append((imported['bytes']['start'], imported['bytes']['end'], 'import ' + imported['name']))
    for exported in document['exports']:
        ranges.append((exported['bytes']['start'], exported['bytes']['end'], 'export ' + exported['name']))
    starts = [declaration['bytes']['start'] for declaration in document['declarations']]
    assert starts == sorted(starts), f'{path}: declarations are not ordered by start'
    for declaration in document['declarations']:
        assert declaration['comment_start'] <= declaration['bytes']['start'], f'{path}: {declaration["name"]}'
        assert declaration['bytes']['end'] <= len(source), f'{path}: {declaration["name"]} exceeds the file'
        ranges.append((declaration['comment_start'], declaration['bytes']['end'], declaration['name']))
    accounted = 0
    for start, end, label in sorted(ranges):
        assert start >= accounted, f'{path}: {label} overlaps an earlier range'
        assert end > start, f'{path}: {label} has an empty range'
        assert trivia_only(source[accounted:start]), f'{path}: unaccounted bytes before {label}'
        accounted = end
    assert trivia_only(source[accounted:]), f'{path}: unaccounted trailing bytes'


def compare_index(compiler, entry):
    index = subprocess.run([compiler, 'index-project', str(entry), '--full'], capture_output=True, text=True, timeout=300)
    assert index.returncode == 0, (str(entry), index.stderr)
    document = json.loads(index.stdout)
    assert document['checked'], str(entry)
    compared = 0
    for path in sorted(entry.parent.rglob('*.my')):
        relative = str(path.relative_to(entry.parent))
        names = {symbol['name'] for symbol in document['symbols'] if symbol['location']['path'] == relative}
        if not names:
            continue
        result = listing(compiler, path)
        assert result.returncode == 0, (relative, result.stderr)
        for declaration in json.loads(result.stdout)['declarations']:
            assert declaration['name'] in names, f'{relative}: {declaration["name"]} is not an indexed symbol'
            compared += 1
    return compared


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', required=True)
    compiler = str(Path(parser.parse_args().compiler).resolve())
    files = sorted(path for base in ('examples', 'experiments') for path in (ROOT / base).rglob('*.my'))
    assert len(files) > 100, 'expected the example and experiment corpus'
    listed = 0
    unparsed = []
    for path in files:
        result = listing(compiler, path)
        if result.returncode == 1:
            command = 'fmt-module' if path.read_text(encoding='utf-8').startswith('module') else 'fmt'
            formatted = subprocess.run([compiler, command, str(path)], capture_output=True, text=True, timeout=60)
            assert formatted.returncode == 1, (str(path), result.stderr)
            unparsed.append(str(path.relative_to(ROOT)))
            continue
        assert result.returncode == 0, (str(path), result.stderr)
        assert result.stderr == '', (str(path), result.stderr)
        check(path, json.loads(result.stdout))
        listed += 1
    compared = sum(compare_index(compiler, ROOT / entry) for entry in INDEXED)
    print(f'list-declarations: {listed} modules accounted, {len(unparsed)} unparsed, {compared} indexed names compared')


if __name__ == '__main__':
    main()

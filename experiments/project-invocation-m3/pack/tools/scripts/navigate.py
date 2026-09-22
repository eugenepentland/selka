#!/usr/bin/env python3
"""Bounded navigation queries over fresh, source-pinned compiler facts; no VM execution."""
import argparse
import hashlib
import json
import os
import stat
from pathlib import Path
import subprocess
import sys
import tempfile

MAX_INDEX_BYTES = 64 * 1024 * 1024


def digest(value):
    return hashlib.sha256(json.dumps(value, separators=(',', ':'), ensure_ascii=False).encode()).hexdigest()


def bounded_read(path, limit):
    descriptor = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
    with os.fdopen(descriptor, 'rb') as stream:
        metadata = os.fstat(stream.fileno())
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_size > limit:
            raise ValueError('navigation requires a bounded regular file: ' + str(path))
        data = stream.read(limit + 1)
        if len(data) > limit:
            raise ValueError('navigation file grew beyond its byte budget')
        return data


def sources(root):
    inventory, total, visited = {}, 0, 0
    for directory, directories, files in os.walk(root, followlinks=False):
        visited += len(directories) + len(files)
        if visited > 50000:
            raise ValueError('navigation directory traversal exceeds its entry budget')
        for name in directories:
            if (Path(directory) / name).is_symlink():
                raise ValueError('navigation source inventory rejects symbolic-link directories')
        for name in sorted(files):
            if not name.endswith('.my'):
                continue
            path = Path(directory) / name
            data = bounded_read(path, 16 * 1024 * 1024 - total)
            total += len(data)
            inventory[path.relative_to(root).as_posix()] = hashlib.sha256(data).hexdigest()
    return dict(sorted(inventory.items()))


def compiler_identity(compiler):
    """Ask the compiler for its own identity.

    The compiler embeds a build-time digest of its sources, Zig version and optimize
    mode and reports it as `compiler_sha256`, in `--features` and in every receipt.
    Hashing the executable here instead would compare two different things, and cost
    seconds per call on a large debug build.
    """
    result = subprocess.run([str(compiler), '--features'], capture_output=True, timeout=60)
    if result.returncode or len(result.stdout) > MAX_INDEX_BYTES:
        raise ValueError('compiler identity query failed: ' + result.stderr.decode(errors='replace')[:4096])
    report = json.loads(result.stdout)
    if report.get('version') != 'language-features-v1' or not isinstance(report.get('compiler_sha256'), str):
        raise ValueError('unsupported compiler feature report')
    return report['compiler_sha256']


def prune(directory, keep):
    entries = []
    for path in directory.glob('*.json'):
        try:
            metadata = path.lstat()
            if stat.S_ISREG(metadata.st_mode):
                entries.append((metadata.st_mtime_ns, path, metadata.st_size))
        except FileNotFoundError:
            continue
    total, count = sum(row[2] for row in entries), len(entries)
    for _, path, size in sorted(entries):
        if count <= 128 and total <= MAX_INDEX_BYTES:
            break
        if path != keep:
            path.unlink(missing_ok=True)
            total -= size
            count -= 1


def validate(index, inventory, compiler_hash):
    if index.get('version') != 'navigation-v1' or not isinstance(index.get('checked'), bool):
        raise ValueError('unsupported navigation index')
    snapshot = index['snapshot']
    if digest(snapshot) != index['snapshot_sha256']:
        raise ValueError('navigation snapshot digest mismatch')
    if snapshot['implementation']['compiler_sha256'] != compiler_hash:
        raise ValueError('navigation compiler identity mismatch')
    for item in snapshot['inputs']:
        if not item['path'].startswith('@stdlib/') and inventory.get(item['path']) != item['sha256']:
            raise ValueError('navigation source identity mismatch: ' + item['path'])
    if not index['checked'] and index['references']:
        raise ValueError('unchecked navigation index must not contain checked edges')


def load(compiler, entry, cache_dir=None):
    compiler, entry = compiler.resolve(), entry.resolve()
    before = sources(entry.parent)
    compiler_hash = compiler_identity(compiler)
    key = digest({'version': 'navigation-cache-v1', 'compiler': compiler_hash,
                  'entry': entry.name, 'sources': before})
    path = cache_dir / (key + '.json') if cache_dir else None
    index, reused = None, False
    if path is not None:
        try:
            wrapper = json.loads(bounded_read(path, MAX_INDEX_BYTES))
            if wrapper['key'] == key and digest(wrapper['index']) == wrapper['index_sha256']:
                validate(wrapper['index'], before, compiler_hash)
                index, reused = wrapper['index'], True
        except (OSError, ValueError, TypeError, KeyError):
            pass  # Corrupt receipts are misses, never successful navigation facts.
    if index is None:
        result = subprocess.run([str(compiler), 'index-project', str(entry)], capture_output=True, timeout=120)
        if result.returncode or len(result.stdout) > MAX_INDEX_BYTES:
            raise ValueError('index generation failed: ' + result.stderr.decode(errors='replace')[:4096])
        index = json.loads(result.stdout)
        validate(index, before, compiler_hash)
    if sources(entry.parent) != before or compiler_identity(compiler) != compiler_hash:
        raise ValueError('source or compiler changed during navigation; retry on a stable snapshot')
    if path is not None and not reused:
        path.parent.mkdir(parents=True, exist_ok=True)
        wrapper = {'key': key, 'index_sha256': digest(index), 'index': index}
        encoded = json.dumps(wrapper, separators=(',', ':'), ensure_ascii=False)
        if len(encoded.encode()) <= MAX_INDEX_BYTES:
            temporary = tempfile.NamedTemporaryFile(mode='w', dir=path.parent, delete=False)
            name = Path(temporary.name)
            try:
                with temporary:
                    temporary.write(encoded)
                name.replace(path)
                prune(path.parent, path)
            finally:
                name.unlink(missing_ok=True)

    return index, reused


def query(index, *, text='', symbol=None, relation='definition', type_name=None, effect=None,
          limit=20, context_bytes=8192, scan_limit=20000):
    if not 1 <= limit <= 1000 or not 0 <= context_bytes <= 1024 * 1024 or not 1 <= scan_limit <= 250000:
        raise ValueError('query limits exceed supported bounds')
    symbols = {item['id']: item for item in index['symbols']}
    seeds = {name for name, item in symbols.items()
             if (symbol is None or name == symbol) and text.casefold() in name.casefold()
             and (type_name is None or item['type_name'] == type_name)
             and (effect is None or effect in item['effects'])}
    selected, edges, truncated = set(seeds), [], False
    references = index['references'] if index['checked'] else []
    if relation in ('references', 'callers', 'callees', 'context'):
        for edge in references:
            incoming = edge['to'] in seeds
            outgoing = edge['from'] in seeds
            include = (incoming if relation in ('references', 'callers') else outgoing if relation == 'callees' else incoming or outgoing)
            if include and (relation not in ('callers', 'callees') or edge['kind'] == 'call'):
                edges.append(edge)
                selected.update((edge['from'], edge['to']))
    elif relation == 'impact':
        reverse = {}
        for edge in references:
            reverse.setdefault(edge['to'], []).append(edge)
        queue = sorted(seeds)
        scanned = 0
        while queue and scanned < scan_limit:
            target = queue.pop()
            for edge in reverse.get(target, []):
                scanned += 1
                if scanned > scan_limit:
                    truncated = True
                    break
                edges.append(edge)
                if edge['from'] not in selected:
                    selected.add(edge['from'])
                    queue.append(edge['from'])
        truncated = truncated or bool(queue)
    elif relation != 'definition':
        raise ValueError('unsupported navigation relation')
    rows, budget = [], context_bytes
    for name in sorted(selected)[:limit]:
        if name not in symbols:
            continue
        item = dict(symbols[name])
        raw = item.get('snippet', '').encode()
        snippet = raw[:budget].decode(errors='ignore')
        item['snippet'] = snippet
        item['snippet_truncated'] = item.get('snippet_truncated', False) or len(snippet.encode()) != len(raw)
        budget -= len(snippet.encode())
        rows.append(item)
    return {'version': 'navigation-query-v1', 'checked': index['checked'],
            'snapshot_sha256': index['snapshot_sha256'], 'relation': relation,
            'scope': 'static source relationships; impact is not test coverage or proof of complete change impact',
            'symbols': rows, 'references': edges[:limit], 'omitted_symbols': max(0, len(selected) - len(rows)),
            'omitted_references': max(0, len(edges) - limit), 'traversal_truncated': truncated,
            'semantic_relations_available': index['checked']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--entry', type=Path, required=True)
    parser.add_argument('--cache-dir', type=Path)
    parser.add_argument('--query', default='')
    parser.add_argument('--symbol')
    parser.add_argument('--relation', choices=['definition', 'references', 'callers', 'callees', 'impact', 'context'], default='definition')
    parser.add_argument('--type', dest='type_name')
    parser.add_argument('--effect')
    parser.add_argument('--limit', type=int, default=20)
    parser.add_argument('--context-bytes', type=int, default=8192)
    parser.add_argument('--scan-limit', type=int, default=20000)
    args = parser.parse_args()
    try:
        index, reused = load(args.compiler, args.entry, args.cache_dir)
        result = query(index, text=args.query, symbol=args.symbol, relation=args.relation,
                       type_name=args.type_name, effect=args.effect, limit=args.limit,
                       context_bytes=args.context_bytes, scan_limit=args.scan_limit)
        result['index_cached'] = reused
        print(json.dumps(result, ensure_ascii=False))
    except (OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired) as error:
        print('navigate: ' + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())

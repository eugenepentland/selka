#!/usr/bin/env python3
"""Summarize a retained trace without inferring semantic completeness."""
import ast
import hashlib
import json
import os
import re
import stat
import struct
from pathlib import Path

HERE = Path(__file__).resolve().parent
TOOL = Path('/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig')
INVROOT = Path('/home/epentland/.cache/mylang/core-tools-v1/tool-identity')
MAGIC = b'core-tool-inventory-v3\0'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def decode(path):
    data = path.read_bytes()
    if not data.startswith(MAGIC):
        return None
    offset = len(MAGIC) + 32
    count, = struct.unpack_from('<I', data, offset)
    offset += 4
    inputs = []
    for _ in range(count):
        pair = []
        for _ in range(2):
            size, = struct.unpack_from('<I', data, offset)
            offset += 4
            pair.append(data[offset:offset+size].decode())
            offset += size
        present = data[offset]
        offset += 1
        assert present in (0, 1)
        info = None
        if present:
            inode, size = struct.unpack_from('<QQ', data, offset)
            mtime = int.from_bytes(data[offset+16:offset+32], 'little', signed=True)
            ctime = int.from_bytes(data[offset+32:offset+48], 'little', signed=True)
            mode, = struct.unpack_from('<I', data, offset+48)
            kind = data[offset+52]
            info = dict(inode=inode, size=size, mtime_ns=mtime, ctime_ns=ctime, mode=mode, kind=kind)
            offset += 53
        inputs.append(dict(path=pair[0], resolved=pair[1], info=info))
    assert offset == len(data)-32
    return inputs


inventories = [(path, decode(path)) for path in sorted(INVROOT.glob('*.inventory'))]
selected = [(path, values) for path, values in inventories if values and
            any(row['path'] == str(TOOL) for row in values)]
assert len(selected) == 1
invpath, inventory = selected[0]
known = {row['path'] for row in inventory} | {row['resolved'] for row in inventory}


def joined(trace):
    pending = {}
    result = []
    for number, line in enumerate(trace.splitlines(), 1):
        match = re.match(r'^(\d+)\s+(.*)$', line)
        if not match:
            continue
        pid, text = match.groups()
        superseded = re.match(r'^\+\+\+ superseded by execve in pid (\d+) \+\+\+$', text)
        if superseded:
            pending[pid] = pending.pop(superseded.group(1))
            continue
        if text.endswith('<unfinished ...>'):
            assert pid not in pending
            pending[pid] = (number, text[:-len('<unfinished ...>')].rstrip())
            continue
        resumed = re.match(r'^<\.\.\. \w+ resumed>(.*)$', text)
        if resumed:
            start, prefix = pending.pop(pid)
            result.append((start, prefix + resumed.group(1)))
        else:
            result.append((number, text))
    assert not pending
    return result


def symlinks(path):
    if path.startswith('/proc/'):
        return []
    links = []
    parts = Path(path).parts
    current = Path(parts[0])
    for part in parts[1:]:
        current /= part
        try:
            if current.is_symlink():
                links.append(dict(path=str(current), target=os.readlink(current), source='post-probe lstat snapshot'))
        except OSError:
            pass
    return links


def summary(name):
    receipt = json.loads((HERE / (name+'.json')).read_text())
    cwd = receipt['cwd']
    trace = (HERE / (name+'.strace')).read_text()
    events = []
    for number, line in joined(trace):
        match = re.match(r'^(\w+)\((.*)\)\s+=\s+(.+)$', line)
        if not match:
            continue
        call, args, result = match.groups()
        annotations = re.findall(r'\d*<(/[^>]+)>', args)
        quote = re.search(r'"(?:[^"\\]|\\.)*"', args)
        path = None
        if call in ('read', 'pread64', 'mmap', 'getdents64'):
            if annotations:
                path = annotations[0]
        elif call in ('open', 'openat', 'stat', 'statx', 'lstat', 'newfstatat',
                      'access', 'faccessat', 'faccessat2', 'readlink', 'readlinkat',
                      'execve', 'mkdir', 'mkdirat', 'unlink', 'unlinkat', 'rename', 'renameat'):
            if quote:
                path = ast.literal_eval(quote.group(0))
                if not path:
                    path = annotations[0] if annotations else None
                elif not os.path.isabs(path):
                    base = annotations[0] if annotations and (call.endswith('at') or call in ('statx', 'newfstatat', 'faccessat2')) else cwd
                    path = os.path.normpath(os.path.join(base, path))
        if path is None:
            continue
        path = os.path.normpath(path)
        if path.startswith('/dev/urandom'):
            path = '/dev/urandom'
        success = not result.startswith('-1 ')
        amount = re.match(r'^(\d+)', result)
        amount = int(amount.group(1)) if amount else 0
        content = success and call in ('read', 'pread64', 'mmap') and amount > 0
        events.append(dict(line=number, call=call, path=path, result=result,
                           success=success, content_read=content,
                           in_tool_inventory=path in known,
                           private=path.startswith(cwd+'/') or path == cwd,
                           readlink_target=(ast.literal_eval(re.search(r'"(?:[^"\\]|\\.)*"', result).group(0))
                                            if success and call in ('readlink', 'readlinkat') and re.search(r'"(?:[^"\\]|\\.)*"', result) else None)))
    paths = sorted({row['path'] for row in events})
    links = {link['path']: link for path in paths for link in symlinks(path)}
    for row in events:
        if row['readlink_target'] is not None:
            links[row['path']] = dict(path=row['path'], target=row['readlink_target'], source='retained readlink syscall')
    reads = sorted({row['path'] for row in events if row['content_read']})
    outside = [row for row in events if not row['private'] and not row['in_tool_inventory']]
    directories = sorted({row['path'] for row in events if row['call']=='getdents64'})
    external_reads = [p for p in reads if not p.startswith(cwd+'/') and p not in known]
    (HERE / (name+'-accesses.json')).write_text(json.dumps(events, indent=2)+'\n')
    item = dict(status=receipt['status'], object=receipt['object'], path_count=len(paths),
                content_reads=reads, external_content_reads_not_in_inventory=external_reads,
                enumerated_directories=directories, symlinks=list(links.values()),
                failed_lookups=sorted({row['path'] for row in events if not row['success']}),
                nonprivate_not_in_inventory=sorted({row['path'] for row in outside}))
    return item


names = ('baseline', 'no-default-config', 'no-header-search', 'depfile', 'driver-argv',
         'empty-gcc', 'sysroot-only', 'confined-search', 'resource-confined')
result = {name: summary(name) for name in names}
meta = dict(path=str(invpath), sha256=digest(invpath), inputs=len(inventory),
            file_inputs=sum(row['info'] is not None and row['info']['kind']==5 for row in inventory),
            note='Decoded existing hint for observational path comparison; its opaque BLAKE3 checksum is not validated by this Python reader.')
(HERE / 'inventory-comparison.json').write_text(json.dumps(dict(inventory=meta, traces=result), indent=2)+'\n')
for name, item in result.items():
    print(name, 'paths', item['path_count'], 'external reads', item['external_content_reads_not_in_inventory'],
          'enumerated nonprivate', [p for p in item['enumerated_directories'] if '/.mylang-cache/' not in p])
print('inventory',meta)

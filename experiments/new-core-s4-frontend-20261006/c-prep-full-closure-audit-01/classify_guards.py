#!/usr/bin/env python3
"""Compare observed lookup paths with the frozen full helper inventory."""
import collections
import hashlib
import json
import os
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
EARLIER = HERE.parent / 'c-prep-action-closure-01'
WORK = ROOT / '.mylang-cache/s4-frontend/c-prep-full-closure-audit-01'
namespace = {'__file__': str(EARLIER / 'analyze.py')}
exec((EARLIER / 'analyze.py').read_text().split('\nnames = ')[0], namespace)
inventory = namespace['inventory']
direct = {p for row in inventory for p in (row['path'], row['resolved'])}
directories = {p for row in inventory if row['info'] and row['info']['kind'] == 2
               for p in (row['path'], row['resolved'])}


def parents(path):
    result = []
    candidate = Path(path).parent
    while True:
        if str(candidate) in directories:
            result.append(str(candidate))
        if candidate.parent == candidate:
            return result
        candidate = candidate.parent


def write(name, value):
    (HERE / name).write_text(json.dumps(value, indent=2) + '\n')


summaries = {}
for label in ('runtime-c', 'program-link'):
    records = json.loads((HERE / (label + '-accesses.json')).read_text())
    paths = {}
    for record in records:
        paths.setdefault(record['path'], []).append(record)
    classifications = []
    for path, events in sorted(paths.items()):
        ancestors = parents(path)
        if path in direct:
            category = 'direct existing snapshot'
        elif ancestors:
            category = 'existing directory snapshot guards lookup membership'
        elif path == str(ROOT) or path == str(WORK):
            category = 'owned CWD/output parent traversal; exclude through actual argv provenance'
        elif path.startswith(str(WORK) + '/'):
            category = 'task-owned input/output; classify through argv/producer provenance'
        elif path in ('/home', '/home/epentland') and all(e['call'] == 'readlink' for e in events):
            category = 'tool canonicalization traversal; bind alias selection, not directory membership'
        elif path.startswith('/proc/'):
            category = 'process-local kernel view; traced target needed'
        elif path == '/dev/urandom':
            category = 'entropy for invocation staging; not a file-content certificate'
        elif path.startswith('/tmp/'):
            category = 'generated staging only if retained create/producer proves ownership'
        else:
            category = 'unguarded external discovery'
        classifications.append(dict(path=path, classification=category,
                                    directory_snapshots=ancestors,
                                    successful=any(e['success'] for e in events),
                                    content_read=any(e['content_read'] for e in events),
                                    calls=sorted({e['call'] for e in events})))
    counts = dict(collections.Counter(row['classification'] for row in classifications))
    unguarded = [row for row in classifications if row['classification'] == 'unguarded external discovery']
    unguarded_reads = [row['path'] for row in unguarded if row['content_read']]
    write(label + '-path-guards.json', classifications)
    summaries[label] = dict(paths=len(paths), counts=counts,
                            unguarded_external_content_reads=unguarded_reads,
                            ancestor_guarded_content_reads_without_direct_snapshot=[row['path'] for row in classifications
                              if row['content_read'] and row['directory_snapshots'] and row['path'] not in direct],
                            unguarded_external_paths=[row['path'] for row in unguarded])
    # Post-probe snapshots describe the current observed search state only.
    snapshots = []
    for row in unguarded:
        path = Path(row['path'])
        item = dict(path=str(path), role='post-probe metadata; not race proof')
        try:
            st = path.lstat()
            item.update(inode=st.st_ino, device=st.st_dev, size=st.st_size,
                        mtime_ns=st.st_mtime_ns, ctime_ns=st.st_ctime_ns, mode=st.st_mode,
                        resolved=os.path.realpath(path),
                        link_target=os.readlink(path) if path.is_symlink() else None)
            if path.is_file():
                item['sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
            elif path.is_dir() and '/gcc/' in str(path):
                item['entries'] = sorted(p.name for p in path.iterdir())
        except FileNotFoundError:
            item['absent'] = True
        snapshots.append(item)
    write(label + '-unguarded-snapshots.json', snapshots)

inventory_path = namespace['invpath']
write('path-guard-summary.json', dict(inventory=str(inventory_path),
      inventory_sha256=hashlib.sha256(inventory_path.read_bytes()).hexdigest(),
      inputs=len(inventory), directory_inputs=len(directories),
      decoder='Path comparison only: opaque BLAKE3 checksum is not verified by this Python reader.',
      actions=summaries))

trace = (HERE / 'program-link.strace').read_text()
generated = []
for line, text in namespace['joined'](trace):
    if '/tmp/' in text and ('O_EXCL' in text or text.startswith('rename(')):
        generated.append(dict(line=line, syscall=text))
write('generated-staging-provenance.json', dict(scope='Actual descendants of protected M native final action.',
      rule='Only successful exclusive creation and subsequent same-action producer/rename establish generated output; /tmp prefix alone is insufficient.',
      events=generated))
print(json.dumps({label: {'paths': data['paths'], 'counts': data['counts'],
                          'unguarded_content_reads': data['unguarded_external_content_reads']}
                  for label, data in summaries.items()}, indent=2))
